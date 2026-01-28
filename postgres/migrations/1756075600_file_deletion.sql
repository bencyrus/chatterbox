-- file deletion domain: generic per-file deletion process
--
-- this migration implements file deletion via a supervisor pattern

-- =============================================================================
-- foundation: extend task domain
-- =============================================================================

alter domain queues.task_type drop constraint if exists task_type_check;

alter domain queues.task_type
    add constraint task_type_allowed_values
    check (value in ('db_function', 'email', 'sms', 'file_delete'));

grant usage on schema accounts to worker_service_user;
grant usage on schema files to worker_service_user;
grant usage on schema learning to worker_service_user;

-- =============================================================================
-- file deletion tables
-- =============================================================================

create table if not exists files.file_deletion_task (
    file_deletion_task_id bigserial primary key,
    file_id bigint not null unique references files.file(file_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists files.file_deletion_task_scheduled (
    file_deletion_task_scheduled_id bigserial primary key,
    file_deletion_task_id bigint not null references files.file_deletion_task(file_deletion_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists files.file_deletion_task_succeeded (
    file_deletion_task_id bigint primary key references files.file_deletion_task(file_deletion_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists files.file_deletion_task_failed (
    file_deletion_task_failed_id bigserial primary key,
    file_deletion_task_id bigint not null references files.file_deletion_task(file_deletion_task_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- fact helpers
-- =============================================================================

create or replace function files.has_file_deletion_task(
    _file_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.file_deletion_task fdt
        where fdt.file_id = _file_id
    );
$$;

create or replace function files.has_file_deletion_task_succeeded(
    _file_deletion_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.file_deletion_task_succeeded s
        where s.file_deletion_task_id = _file_deletion_task_id
    );
$$;

create or replace function files.count_file_deletion_task_failures(
    _file_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from files.file_deletion_task_failed f
    where f.file_deletion_task_id = _file_deletion_task_id;
$$;

create or replace function files.count_file_deletion_task_scheduled(
    _file_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from files.file_deletion_task_scheduled s
    where s.file_deletion_task_id = _file_deletion_task_id;
$$;

create or replace function files.is_file_deletion_stuck(
    _file_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.file_deletion_task fdt
        where fdt.file_id = _file_id
          and not exists (
              select 1
              from files.file_deletion_task_succeeded fdts
              where fdts.file_deletion_task_id = fdt.file_deletion_task_id
          )
          -- unique constraint on file_id prevents more than 1 task so the max retries
          -- is what is set in the supervisor function
          and (
              select count(*)
              from files.file_deletion_task_failed fdtf
              where fdtf.file_deletion_task_id = fdt.file_deletion_task_id
          ) >= 3
    );
$$;

-- =============================================================================
-- handlers: before / success / error for file deletion channel
-- =============================================================================

create or replace function files.get_file_delete_payload(
    payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _file_id bigint := (payload->>'file_id')::bigint;
    _file_record files.file;
begin
    if _file_id is null then
        return jsonb_build_object(
            'status', 'missing_file_id'
        );
    end if;

    select f.*
    into _file_record
    from files.file f
    join files.file_metadata fm using (file_id)
    where f.file_id = _file_id
      and fm.key != 'deleted';

    if not found then
        return jsonb_build_object(
            'status', 'file_not_found_for_deletion'
        );
    end if;

    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'file_id', _file_record.file_id
        )
    );
end;
$$;

grant execute on function files.get_file_delete_payload(jsonb) to worker_service_user;

create or replace function files.record_file_delete_success(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _original jsonb := coalesce(payload->'original_payload', '{}'::jsonb);
    _worker jsonb := coalesce(payload->'worker_payload', '{}'::jsonb);
    _file_deletion_task_id bigint := coalesce(
        (_original->>'file_deletion_task_id')::bigint,
        (payload->>'file_deletion_task_id')::bigint
    );
    _file_id bigint := coalesce(
        (_worker->>'file_id')::bigint,
        (_original->>'file_id')::bigint
    );
begin
    if _file_id is null then
        return jsonb_build_object(
            'status', 'missing_file_id'
        );
    end if;

    -- logically mark the file as deleted (metadata flag)
    perform files.mark_file_deleted(_file_id);

    if _file_deletion_task_id is not null then
        insert into files.file_deletion_task_succeeded (file_deletion_task_id)
        values (_file_deletion_task_id)
        on conflict (file_deletion_task_id) do nothing;
    end if;

    return jsonb_build_object(
        'status', 'succeeded'
    );
end;
$$;

grant execute on function files.record_file_delete_success(jsonb) to worker_service_user;

create or replace function files.record_file_delete_failure(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _original jsonb := coalesce(payload->'original_payload', '{}'::jsonb);
    _file_deletion_task_id bigint := coalesce(
        (_original->>'file_deletion_task_id')::bigint,
        (payload->>'file_deletion_task_id')::bigint
    );
    _error_message text := (payload->>'error')::text;
begin
    if _file_deletion_task_id is null then
        return jsonb_build_object(
            'status', 'missing_file_deletion_task_id'
        );
    end if;

    insert into files.file_deletion_task_failed (file_deletion_task_id, error_message)
    values (_file_deletion_task_id, _error_message);

    return jsonb_build_object(
        'status', 'succeeded'
    );
end;
$$;

grant execute on function files.record_file_delete_failure(jsonb) to worker_service_user;

-- =============================================================================
-- kickoff: idempotent entry point
-- =============================================================================

create or replace function files.kickoff_file_deletion(
    _file_id bigint,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
declare
    _file_deletion_task_id bigint;
    _exists boolean;
begin
    if _file_id is null then
        validation_failure_message := 'missing_file_id';
        return;
    end if;

    select exists (
        select 1
        from files.file f
        where f.file_id = _file_id
    )
    into _exists;

    if not _exists then
        validation_failure_message := 'file_not_found';
        return;
    end if;

    -- if task already exists, skip (supervisor already running)
    if files.has_file_deletion_task(_file_id) then
        return;
    end if;

    insert into files.file_deletion_task (file_id)
    values (_file_id)
    returning file_deletion_task_id
    into _file_deletion_task_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'files.file_deletion_supervisor',
            'file_deletion_task_id', _file_deletion_task_id,
            'file_id', _file_id
        ),
        coalesce(_scheduled_at, now())
    );

    return;
end;
$$;

-- =============================================================================
-- supervisor: orchestrates single file deletion via worker
-- =============================================================================

create or replace function files.file_deletion_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _file_deletion_task_id bigint := (payload->>'file_deletion_task_id')::bigint;
    _file_id bigint := (payload->>'file_id')::bigint;
    _has_success boolean;
    _num_failures integer;
    _num_scheduled integer;
    _max_attempts integer := 3;
    _base_delay_seconds integer := 10;
    _next_check_at timestamptz;
begin
    -- only take in the task id and look up the file id instead of having it in the payload
    if _file_deletion_task_id is null then
        return jsonb_build_object(
            'status', 'missing_file_deletion_task_id'
        );
    end if;

    if _file_id is null then
        return jsonb_build_object(
            'status', 'missing_file_id'
        );
    end if;

    -- lock root task
    perform 1
    from files.file_deletion_task t
    where t.file_deletion_task_id = _file_deletion_task_id
    for update;

    select files.has_file_deletion_task_succeeded(_file_deletion_task_id)
    into _has_success;

    if _has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    -- if file already marked deleted, mark supervisor success
    if files.is_file_deleted(_file_id) then
        insert into files.file_deletion_task_succeeded (file_deletion_task_id)
        values (_file_deletion_task_id)
        on conflict (file_deletion_task_id) do nothing;

        return jsonb_build_object('status', 'succeeded');
    end if;

    select files.count_file_deletion_task_failures(_file_deletion_task_id)
    into _num_failures;

    if _num_failures >= _max_attempts then
        return jsonb_build_object('status', 'succeeded');
    end if;

    select files.count_file_deletion_task_scheduled(_file_deletion_task_id)
    into _num_scheduled;

    _next_check_at := (
        now() +
        ((_base_delay_seconds)::double precision * power(2, coalesce(_num_failures, 0))) *
        interval '1 second'
    );

    -- schedule a deletion attempt if none outstanding
    -- if there is a scheduled file deletion task for this file, skips the if block below
    if coalesce(_num_scheduled, 0) <= coalesce(_num_failures, 0) then
        insert into files.file_deletion_task_scheduled (file_deletion_task_id)
        values (_file_deletion_task_id);

        perform queues.enqueue(
            'file_delete',
            jsonb_build_object(
                'task_type', 'file_delete',
                'file_deletion_task_id', _file_deletion_task_id,
                'file_id', _file_id,
                'before_handler', 'files.get_file_delete_payload',
                'success_handler', 'files.record_file_delete_success',
                'error_handler', 'files.record_file_delete_failure'
            ),
            now()
        );
    end if;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'files.file_deletion_supervisor',
            'file_deletion_task_id', _file_deletion_task_id,
            'file_id', _file_id
        ),
        _next_check_at
    );

    return jsonb_build_object('status', 'succeeded');
end;
$$;

grant execute on function files.file_deletion_supervisor(jsonb) to worker_service_user;

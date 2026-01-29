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

-- file deletion process: task and attempts (append-only)
create table files.file_deletion_task (
    file_deletion_task_id bigserial primary key,
    file_id bigint not null unique references files.file(file_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempts (append-only, one per scheduled attempt)
create table files.file_deletion_attempt (
    file_deletion_attempt_id bigserial primary key,
    file_deletion_task_id bigint not null references files.file_deletion_task(file_deletion_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt succeeded (one per attempt at most)
create table files.file_deletion_attempt_succeeded (
    file_deletion_attempt_id bigint primary key references files.file_deletion_attempt(file_deletion_attempt_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt failed (one per attempt at most)
create table files.file_deletion_attempt_failed (
    file_deletion_attempt_id bigint primary key references files.file_deletion_attempt(file_deletion_attempt_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- fact helpers
-- =============================================================================

-- facts: has a file deletion task for this file?
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

-- facts: has a succeeded attempt for file_deletion_task?
create or replace function files.has_file_deletion_succeeded_attempt(
    _file_deletion_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.file_deletion_attempt a
        join files.file_deletion_attempt_succeeded s on s.file_deletion_attempt_id = a.file_deletion_attempt_id
        where a.file_deletion_task_id = _file_deletion_task_id
    );
$$;

-- facts: count failed attempts for file_deletion_task
create or replace function files.count_file_deletion_failed_attempts(
    _file_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from files.file_deletion_attempt a
    join files.file_deletion_attempt_failed f on f.file_deletion_attempt_id = a.file_deletion_attempt_id
    where a.file_deletion_task_id = _file_deletion_task_id;
$$;

-- facts: count attempts for file_deletion_task
create or replace function files.count_file_deletion_attempts(
    _file_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from files.file_deletion_attempt a
    where a.file_deletion_task_id = _file_deletion_task_id;
$$;

-- facts: aggregated facts for file_deletion_supervisor
create or replace function files.file_deletion_supervisor_facts(
    _file_deletion_task_id bigint,
    out is_deleted boolean,
    out has_success boolean,
    out num_failures integer,
    out num_attempts integer
)
language sql
stable
as $$
    select
        (select files.is_file_deleted(t.file_id) from files.file_deletion_task t where t.file_deletion_task_id = _file_deletion_task_id),
        files.has_file_deletion_succeeded_attempt(_file_deletion_task_id),
        files.count_file_deletion_failed_attempts(_file_deletion_task_id),
        files.count_file_deletion_attempts(_file_deletion_task_id);
$$;

-- facts: get file deletion payload facts from attempt_id
create or replace function files.get_file_deletion_payload_facts(
    _file_deletion_attempt_id bigint,
    out file_id bigint,
    out is_deleted boolean
)
language sql
stable
as $$
    select
        t.file_id,
        files.is_file_deleted(t.file_id)
    from files.file_deletion_attempt a
    join files.file_deletion_task t on t.file_deletion_task_id = a.file_deletion_task_id
    where a.file_deletion_attempt_id = _file_deletion_attempt_id;
$$;

-- =============================================================================
-- handlers: before / success / error for file deletion channel
-- =============================================================================

-- before handler: build provider payload from file_deletion_attempt_id in payload
create or replace function files.get_file_deletion_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _file_deletion_attempt_id bigint := (_payload->>'file_deletion_attempt_id')::bigint;
    _facts record;
begin
    -- 1. VALIDATION
    if _file_deletion_attempt_id is null then
        return jsonb_build_object('status', 'missing_file_deletion_attempt_id');
    end if;

    -- 2. FACTS
    _facts := files.get_file_deletion_payload_facts(_file_deletion_attempt_id);

    -- 3. LOGIC
    if _facts.file_id is null then
        return jsonb_build_object('status', 'file_not_found');
    end if;

    if _facts.is_deleted then
        return jsonb_build_object('status', 'file_already_deleted');
    end if;

    -- 4. OUTPUT
    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'file_id', _facts.file_id
        )
    );
end;
$$;

-- success handler: record success fact
-- receives: { original_payload: { file_deletion_attempt_id, ... }, worker_payload: { ... } }
create or replace function files.record_file_deletion_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _file_deletion_attempt_id bigint := (_payload->'original_payload'->>'file_deletion_attempt_id')::bigint;
    _file_id bigint;
begin
    if _file_deletion_attempt_id is null then
        return jsonb_build_object('status', 'missing_file_deletion_attempt_id');
    end if;

    select t.file_id
    into _file_id
    from files.file_deletion_attempt a
    join files.file_deletion_task t on t.file_deletion_task_id = a.file_deletion_task_id
    where a.file_deletion_attempt_id = _file_deletion_attempt_id;

    if _file_id is null then
        return jsonb_build_object('status', 'file_deletion_attempt_not_found');
    end if;

    -- logically mark the file as deleted (metadata flag)
    perform files.mark_file_deleted(_file_id);

    -- record attempt success
    insert into files.file_deletion_attempt_succeeded (file_deletion_attempt_id)
    values (_file_deletion_attempt_id)
    on conflict (file_deletion_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- error handler: record failure fact
-- receives: { original_payload: { file_deletion_attempt_id, ... }, error: "..." }
create or replace function files.record_file_deletion_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _file_deletion_attempt_id bigint := (_payload->'original_payload'->>'file_deletion_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _file_deletion_attempt_id is null then
        return jsonb_build_object('status', 'missing_file_deletion_attempt_id');
    end if;

    insert into files.file_deletion_attempt_failed (file_deletion_attempt_id, error_message)
    values (_file_deletion_attempt_id, _error_message)
    on conflict (file_deletion_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- =============================================================================
-- effect functions
-- =============================================================================

-- effect: schedule a file deletion attempt
create or replace function files.schedule_file_deletion_attempt(
    _file_deletion_task_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _file_deletion_attempt_id bigint;
begin
    insert into files.file_deletion_attempt (file_deletion_task_id)
    values (_file_deletion_task_id)
    returning file_deletion_attempt_id into _file_deletion_attempt_id;

    perform queues.enqueue(
        'file_delete',
        jsonb_build_object(
            'task_type', 'file_delete',
            'file_deletion_attempt_id', _file_deletion_attempt_id,
            'before_handler', 'files.get_file_deletion_payload',
            'success_handler', 'files.record_file_deletion_success',
            'error_handler', 'files.record_file_deletion_failure'
        ),
        now()
    );
end;
$$;

-- effect: schedule supervisor recheck with exponential backoff
create or replace function files.schedule_file_deletion_supervisor_recheck(
    _file_deletion_task_id bigint,
    _num_failures integer,
    _run_count integer
)
returns void
language plpgsql
security definer
as $$
declare
    _base_delay_seconds integer := 10;
    _next_check_at timestamptz;
begin
    _next_check_at := now() + (
        _base_delay_seconds * power(2, _num_failures)
    ) * interval '1 second';

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'files.file_deletion_supervisor',
            'file_deletion_task_id', _file_deletion_task_id,
            'run_count', _run_count + 1
        ),
        _next_check_at
    );
end;
$$;

-- =============================================================================
-- supervisor: orchestrates single file deletion via worker
-- =============================================================================

create or replace function files.file_deletion_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _file_deletion_task_id bigint := (_payload->>'file_deletion_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _max_runs integer := 20;
    _max_attempts integer := 3;
    _facts record;
begin
    -- 1. VALIDATION
    if _file_deletion_task_id is null then
        return jsonb_build_object('status', 'missing_file_deletion_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'file_deletion_supervisor exceeded max runs'
            using detail = 'Possible infinite loop detected',
                  hint = format('task_id=%s, run_count=%s', _file_deletion_task_id, _run_count);
    end if;

    -- 2. LOCK (before facts)
    perform 1
    from files.file_deletion_task t
    where t.file_deletion_task_id = _file_deletion_task_id
    for update;

    -- 3. FACTS
    _facts := files.file_deletion_supervisor_facts(_file_deletion_task_id);

    -- 4. LOGIC + EFFECTS
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    -- if file already marked deleted, nothing to do
    if _facts.is_deleted then
        return jsonb_build_object('status', 'already_deleted');
    end if;


    if _facts.num_attempts = _facts.num_failures then
        perform files.schedule_file_deletion_attempt(_file_deletion_task_id);
    end if;

    perform files.schedule_file_deletion_supervisor_recheck(
        _file_deletion_task_id,
        _facts.num_failures,
        _run_count
    );

    return jsonb_build_object('status', 'scheduled');
end;
$$;

-- =============================================================================
-- kickoff: idempotent entry point
-- =============================================================================

-- facts: for kickoff_file_deletion
create or replace function files.kickoff_file_deletion_facts(
    _file_id bigint,
    out file_exists boolean,
    out has_existing_task boolean
)
language sql
stable
as $$
    select
        exists (select 1 from files.file f where f.file_id = _file_id),
        files.has_file_deletion_task(_file_id);
$$;

-- effect: create task and enqueue supervisor
create or replace function files.create_and_enqueue_file_deletion_task(
    _file_id bigint,
    _scheduled_at timestamp with time zone
)
returns void
language plpgsql
security definer
as $$
declare
    _file_deletion_task_id bigint;
begin
    insert into files.file_deletion_task (file_id)
    values (_file_id)
    returning file_deletion_task_id
    into _file_deletion_task_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'files.file_deletion_supervisor',
            'file_deletion_task_id', _file_deletion_task_id
        ),
        _scheduled_at
    );
end;
$$;

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
    _facts record;
begin
    -- 1. VALIDATION
    if _file_id is null then
        validation_failure_message := 'missing_file_id';
        return;
    end if;

    -- 2. FACTS
    _facts := files.kickoff_file_deletion_facts(_file_id);

    -- 3. LOGIC
    if not _facts.file_exists then
        validation_failure_message := 'file_not_found';
        return;
    end if;

    if _facts.has_existing_task then
        return; -- already kicked off, nothing to do
    end if;

    -- 4. EFFECTS
    perform files.create_and_enqueue_file_deletion_task(_file_id, _scheduled_at);

    return;
end;
$$;

-- =============================================================================
-- grants
-- =============================================================================

grant execute on function files.get_file_deletion_payload(jsonb) to worker_service_user;
grant execute on function files.record_file_deletion_success(jsonb) to worker_service_user;
grant execute on function files.record_file_deletion_failure(jsonb) to worker_service_user;
grant execute on function files.schedule_file_deletion_attempt(bigint) to worker_service_user;
grant execute on function files.schedule_file_deletion_supervisor_recheck(bigint, integer, integer) to worker_service_user;
grant execute on function files.file_deletion_supervisor(jsonb) to worker_service_user;
grant execute on function files.kickoff_file_deletion(bigint, timestamp with time zone) to worker_service_user;

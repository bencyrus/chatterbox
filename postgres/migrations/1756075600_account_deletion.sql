-- account deletion process: supervisor-driven cleanup and task tracking
--
-- this migration implements a hierarchical supervisor pattern for account deletion:
-- - account_deletion_supervisor (root): orchestrates phases
-- - file_deletion_supervisor (sub): deletes individual files and marks them deleted
-- - account_anonymization_supervisor (sub): anonymizes account PII

-- =============================================================================
-- foundation: extend task domain
-- =============================================================================

alter domain queues.task_type drop constraint if exists task_type_check;

alter domain queues.task_type
    add constraint task_type_allowed_values
    check (value in ('db_function', 'email', 'sms', 'file_delete'));


-- =============================================================================
-- file deletion domain: generic per-file deletion process
-- =============================================================================

-- tables

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

-- fact helpers

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

-- handlers: before / success / error for file deletion channel

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
            'success', false,
            'validation_failure_message', 'missing_file_id'
        );
    end if;

    select f.*
    into _file_record
    from files.file f
    where f.file_id = _file_id;

    if not found then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'file_not_found_for_deletion'
        );
    end if;

    return jsonb_build_object(
        'success', true,
        'payload', jsonb_build_object(
            'file_id', _file_record.file_id,
            'bucket', _file_record.bucket,
            'object_key', _file_record.object_key
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
            'error', 'missing_file_id'
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
        'success', true
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
            'error', 'missing_file_deletion_task_id'
        );
    end if;

    insert into files.file_deletion_task_failed (file_deletion_task_id, error_message)
    values (_file_deletion_task_id, _error_message);

    return jsonb_build_object(
        'success', true
    );
end;
$$;

grant execute on function files.record_file_delete_failure(jsonb) to worker_service_user;

-- kickoff: idempotent entry point

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

-- supervisor: orchestrates single file deletion via worker

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
    if _file_deletion_task_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_file_deletion_task_id'
        );
    end if;

    if _file_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_file_id'
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
        return jsonb_build_object('success', true);
    end if;

    -- if file already marked deleted, mark supervisor success
    if files.is_file_deleted(_file_id) then
        insert into files.file_deletion_task_succeeded (file_deletion_task_id)
        values (_file_deletion_task_id)
        on conflict (file_deletion_task_id) do nothing;

        return jsonb_build_object('success', true);
    end if;

    select files.count_file_deletion_task_failures(_file_deletion_task_id)
    into _num_failures;

    if _num_failures >= _max_attempts then
        return jsonb_build_object('success', true);
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

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function files.file_deletion_supervisor(jsonb) to worker_service_user;

-- =============================================================================
-- account file helpers: bridge between files and accounts
-- =============================================================================

-- helper: list non-deleted learning-related files for an account
create or replace function files.account_learning_files(
    _account_id bigint
)
returns setof files.file
language sql
stable
as $$
    select distinct f.*
    from files.file f
    join learning.profile_cue_recording pcr
        on pcr.file_id = f.file_id
    join learning.profile p
        on p.profile_id = pcr.profile_id
    where p.account_id = _account_id
      and not files.is_file_deleted(f.file_id);
$$;

-- helper: list non-deleted files associated with an account
create or replace function files.account_files(
    _account_id bigint
)
returns setof files.file
language sql
stable
as $$
    select *
    from files.account_learning_files(_account_id);
    -- future: union other account-owned file sources here
    -- union all
    -- select * from files.account_avatar_files(_account_id);
$$;


-- =============================================================================
-- account anonymization domain: PII removal process
-- =============================================================================

-- helper functions for anonymization

create or replace function accounts.anonymize_account_record(
    _account_id bigint
)
returns void
language plpgsql
security definer
as $$
begin
    update accounts.account
    set email = format('anonymous_%s@deletedemail.non', account_id),
        phone_number = '+' || (1000000000000 + account_id)::text,
        hashed_password = null
    where account_id = _account_id;
end;
$$;

-- anonymize account and mark as anonymized (called by worker)
create or replace function accounts.anonymize_account(
    _account_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
begin
    perform accounts.anonymize_account_record(_account_id);
    -- future: call other domain anonymizers here
    -- perform messages.anonymize_account_messages(_account_id);
    -- perform profiles.anonymize_account_profiles(_account_id);

    insert into accounts.account_flag (account_id, flag)
    values (_account_id, 'anonymized')
    on conflict (account_id, flag) do nothing;

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function accounts.anonymize_account(bigint) to worker_service_user;

-- tables

create table if not exists accounts.account_anonymization_task (
    account_anonymization_task_id bigserial primary key,
    account_id bigint not null unique references accounts.account(account_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists accounts.account_anonymization_task_scheduled (
    account_anonymization_task_scheduled_id bigserial primary key,
    account_anonymization_task_id bigint not null references accounts.account_anonymization_task(account_anonymization_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists accounts.account_anonymization_task_succeeded (
    account_anonymization_task_id bigint primary key references accounts.account_anonymization_task(account_anonymization_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists accounts.account_anonymization_task_failed (
    account_anonymization_task_failed_id bigserial primary key,
    account_anonymization_task_id bigint not null references accounts.account_anonymization_task(account_anonymization_task_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- fact helpers

create or replace function accounts.has_account_anonymization_task(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_anonymization_task aat
        where aat.account_id = _account_id
    );
$$;

create or replace function accounts.has_account_anonymization_task_succeeded(
    _account_anonymization_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_anonymization_task_succeeded s
        where s.account_anonymization_task_id = _account_anonymization_task_id
    );
$$;

create or replace function accounts.count_account_anonymization_task_failures(
    _account_anonymization_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_anonymization_task_failed f
    where f.account_anonymization_task_id = _account_anonymization_task_id;
$$;

create or replace function accounts.count_account_anonymization_task_scheduled(
    _account_anonymization_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_anonymization_task_scheduled s
    where s.account_anonymization_task_id = _account_anonymization_task_id;
$$;

create or replace function accounts.is_account_anonymized(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_flag af
        where af.account_id = _account_id
          and af.flag = 'anonymized'
    );
$$;

create or replace function accounts.is_account_anonymization_stuck(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_anonymization_task aat
        where aat.account_id = _account_id
          and not exists (
              select 1
              from accounts.account_anonymization_task_succeeded aats
              where aats.account_anonymization_task_id = aat.account_anonymization_task_id
          )
          -- unique constraint on account_id prevents more than 1 task so the max retries
          -- is what is set in the supervisor function
          and (
              select count(*)
              from accounts.account_anonymization_task_failed aatf
              where aatf.account_anonymization_task_id = aat.account_anonymization_task_id
          ) >= 3
    );
$$;

-- kickoff: idempotent entry point

create or replace function accounts.kickoff_account_anonymization(
    _account_id bigint,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
declare
    _account_anonymization_task_id bigint;
    _exists boolean;
begin
    if _account_id is null then
        validation_failure_message := 'missing_account_id';
        return;
    end if;

    select exists (
        select 1
        from accounts.account a
        where a.account_id = _account_id
    )
    into _exists;

    if not _exists then
        validation_failure_message := 'account_not_found';
        return;
    end if;

    -- if task already exists, skip (supervisor already running)
    if accounts.has_account_anonymization_task(_account_id) then
        return;
    end if;

    insert into accounts.account_anonymization_task (account_id)
    values (_account_id)
    returning account_anonymization_task_id
    into _account_anonymization_task_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'accounts.account_anonymization_supervisor',
            'account_anonymization_task_id', _account_anonymization_task_id,
            'account_id', _account_id
        ),
        coalesce(_scheduled_at, now())
    );

    return;
end;
$$;

-- supervisor: orchestrates anonymization via worker

create or replace function accounts.account_anonymization_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_anonymization_task_id bigint := (payload->>'account_anonymization_task_id')::bigint;
    _account_id bigint := (payload->>'account_id')::bigint;
    _has_success boolean;
    _num_failures integer;
    _num_scheduled integer;
    _max_attempts integer := 3;
    _base_delay_seconds integer := 10;
    _next_check_at timestamptz;
begin
    if _account_anonymization_task_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_account_anonymization_task_id'
        );
    end if;

    if _account_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_account_id'
        );
    end if;

    -- lock root task
    perform 1
    from accounts.account_anonymization_task t
    where t.account_anonymization_task_id = _account_anonymization_task_id
    for update;

    select accounts.has_account_anonymization_task_succeeded(_account_anonymization_task_id)
    into _has_success;

    if _has_success then
        return jsonb_build_object('success', true);
    end if;

    -- check if account already has the anonymized flag
    if accounts.is_account_anonymized(_account_id) then
        insert into accounts.account_anonymization_task_succeeded (account_anonymization_task_id)
        values (_account_anonymization_task_id)
        on conflict (account_anonymization_task_id) do nothing;

        return jsonb_build_object('success', true);
    end if;

    select accounts.count_account_anonymization_task_failures(_account_anonymization_task_id)
    into _num_failures;

    if _num_failures >= _max_attempts then
        return jsonb_build_object('success', true);
    end if;

    select accounts.count_account_anonymization_task_scheduled(_account_anonymization_task_id)
    into _num_scheduled;

    _next_check_at := (
        now() +
        ((_base_delay_seconds)::double precision * power(2, coalesce(_num_failures, 0))) *
        interval '1 second'
    );

    -- schedule anonymization attempt if none outstanding
    if coalesce(_num_scheduled, 0) <= coalesce(_num_failures, 0) then
        insert into accounts.account_anonymization_task_scheduled (account_anonymization_task_id)
        values (_account_anonymization_task_id);

        perform queues.enqueue(
            'db_function',
            jsonb_build_object(
                'task_type', 'db_function',
                'db_function', 'accounts.anonymize_account',
                'account_id', _account_id
            ),
            now()
        );
    end if;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'accounts.account_anonymization_supervisor',
            'account_anonymization_task_id', _account_anonymization_task_id,
            'account_id', _account_id
        ),
        _next_check_at
    );

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function accounts.account_anonymization_supervisor(jsonb) to worker_service_user;


-- =============================================================================
-- account deletion domain: root orchestrator
-- =============================================================================

-- tables

create table if not exists accounts.account_deletion_task (
    account_deletion_task_id bigserial primary key,
    account_id bigint not null,
    created_at timestamp with time zone not null default now(),
    constraint account_deletion_task_unique_account unique (account_id)
);

create table if not exists accounts.account_deletion_task_scheduled (
    account_deletion_task_scheduled_id bigserial primary key,
    account_deletion_task_id bigint not null references accounts.account_deletion_task(account_deletion_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists accounts.account_deletion_task_succeeded (
    account_deletion_task_id bigint primary key references accounts.account_deletion_task(account_deletion_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create table if not exists accounts.account_deletion_task_failed (
    account_deletion_task_failed_id bigserial primary key,
    account_deletion_task_id bigint not null references accounts.account_deletion_task(account_deletion_task_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- fact helpers

create or replace function accounts.has_account_deletion_task(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_deletion_task adt
        where adt.account_id = _account_id
    );
$$;

create or replace function accounts.has_account_deletion_task_succeeded(
    _account_deletion_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_deletion_task_succeeded s
        where s.account_deletion_task_id = _account_deletion_task_id
    );
$$;

create or replace function accounts.count_account_deletion_task_failures(
    _account_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_deletion_task_failed f
    where f.account_deletion_task_id = _account_deletion_task_id;
$$;

create or replace function accounts.count_account_deletion_task_scheduled(
    _account_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_deletion_task_scheduled s
    where s.account_deletion_task_id = _account_deletion_task_id;
$$;

-- supervisor: orchestrates file deletion and anonymization phases

create or replace function accounts.account_deletion_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_deletion_task_id bigint := (payload->>'account_deletion_task_id')::bigint;
    _account_id bigint := (payload->>'account_id')::bigint;
    _has_success boolean;
    _num_failures integer;
    _num_scheduled integer;
    _max_attempts integer := 3;
    _base_delay_seconds integer := 10;
    _next_check_at timestamptz;
    _files_are_deleted boolean;
    _is_anonymized boolean;
    _file_record record;
begin
    -- validation
    if _account_deletion_task_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_account_deletion_task_id'
        );
    end if;

    if _account_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_account_id'
        );
    end if;

    -- lock root task to serialize concurrent runs
    perform 1
    from accounts.account_deletion_task t
    where t.account_deletion_task_id = _account_deletion_task_id
    for update;

    -- if already succeeded, exit early
    select accounts.has_account_deletion_task_succeeded(_account_deletion_task_id)
    into _has_success;

    if _has_success then
        return jsonb_build_object(
            'success', true
        );
    end if;

    select accounts.count_account_deletion_task_failures(_account_deletion_task_id)
    into _num_failures;

    if _num_failures >= _max_attempts then
        -- give up after bounded attempts
        return jsonb_build_object(
            'success', true
        );
    end if;

    select accounts.count_account_deletion_task_scheduled(_account_deletion_task_id)
    into _num_scheduled;

    -- compute next check with exponential backoff
    _next_check_at := (
        now() +
        ((_base_delay_seconds)::double precision * power(2, coalesce(_num_failures, 0))) *
        interval '1 second'
    );

    -- phase 1: ensure all files are deleted
    _files_are_deleted := not exists (
        select 1
        from files.account_files(_account_id) f
        where not files.is_file_deleted(f.file_id)
    );

    if not _files_are_deleted then
        -- files still pending: check if any are stuck
        if exists (
            select 1
            from files.account_files(_account_id) f
            where files.is_file_deletion_stuck(f.file_id)
        ) then
            -- fail the entire process if any file deletion is permanently stuck
            insert into accounts.account_deletion_task_failed (
                account_deletion_task_id,
                error_message
            )
            values (
                _account_deletion_task_id,
                'one or more file deletions permanently failed'
            );

            return jsonb_build_object('success', true);
        end if;

        -- files pending but not stuck: kick off file deletion supervisors
        for _file_record in select * from files.account_files(_account_id)
        loop
            perform files.kickoff_file_deletion(
                _file_record.file_id,
                now()
            );
        end loop;

        -- schedule next check and return (do not proceed to anonymization yet)
        if coalesce(_num_scheduled, 0) <= coalesce(_num_failures, 0) then
            insert into accounts.account_deletion_task_scheduled (account_deletion_task_id)
            values (_account_deletion_task_id);
        end if;

        perform queues.enqueue(
            'db_function',
            jsonb_build_object(
                'task_type', 'db_function',
                'db_function', 'accounts.account_deletion_supervisor',
                'account_deletion_task_id', _account_deletion_task_id,
                'account_id', _account_id
            ),
            _next_check_at
        );

        return jsonb_build_object('success', true);
    end if;

    -- phase 2: ensure account is anonymized (only after all files are deleted)
    _is_anonymized := accounts.is_account_anonymized(_account_id);

    if not _is_anonymized then
        -- anonymization pending: check if stuck
        if accounts.is_account_anonymization_stuck(_account_id) then
            -- fail entire process if anonymization is permanently stuck
            insert into accounts.account_deletion_task_failed (
                account_deletion_task_id,
                error_message
            )
            values (
                _account_deletion_task_id,
                'account anonymization permanently failed'
            );

            return jsonb_build_object('success', true);
        end if;

        -- anonymization pending but not stuck: kick off account anonymization supervisor
        perform accounts.kickoff_account_anonymization(_account_id, now());

        -- schedule next check and return
        if coalesce(_num_scheduled, 0) <= coalesce(_num_failures, 0) then
            insert into accounts.account_deletion_task_scheduled (account_deletion_task_id)
            values (_account_deletion_task_id);
        end if;

        perform queues.enqueue(
            'db_function',
            jsonb_build_object(
                'task_type', 'db_function',
                'db_function', 'accounts.account_deletion_supervisor',
                'account_deletion_task_id', _account_deletion_task_id,
                'account_id', _account_id
            ),
            _next_check_at
        );

        return jsonb_build_object('success', true);
    end if;

    -- phase 3: all done - mark as succeeded
    insert into accounts.account_deletion_task_succeeded (account_deletion_task_id)
    values (_account_deletion_task_id)
    on conflict (account_deletion_task_id) do nothing;

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function accounts.account_deletion_supervisor(jsonb) to worker_service_user;

-- kickoff: idempotent entry point (marks account as deleted immediately)

create or replace function accounts.kickoff_account_deletion(
    _account_id bigint,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
declare
    _account_deletion_task_id bigint;
    _exists boolean;
begin
    if _account_id is null then
        validation_failure_message := 'missing_account_id';
        return;
    end if;

    select exists (
        select 1
        from accounts.account a
        where a.account_id = _account_id
    )
    into _exists;

    if not _exists then
        validation_failure_message := 'account_not_found';
        return;
    end if;

    -- if task already exists, skip (supervisor already running)
    if accounts.has_account_deletion_task(_account_id) then
        return;
    end if;

    insert into accounts.account_deletion_task (account_id)
    values (_account_id)
    returning account_deletion_task_id
    into _account_deletion_task_id;

    -- mark account as deleted immediately when user requests deletion
    insert into accounts.account_flag (account_id, flag)
    values (_account_id, 'deleted')
    on conflict (account_id, flag) do nothing;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'accounts.account_deletion_supervisor',
            'account_deletion_task_id', _account_deletion_task_id,
            'account_id', _account_id
        ),
        coalesce(_scheduled_at, now())
    );

    return;
end;
$$;

grant execute on function accounts.kickoff_account_deletion(bigint, timestamp with time zone) to worker_service_user;


-- =============================================================================
-- public API: authenticated user-facing endpoint
-- =============================================================================

create or replace function api.request_account_deletion(
    _account_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _kickoff_validation_failure_message text;
begin
    if _account_id is null then
        raise exception 'Request Account Deletion Failed'
            using detail = 'Invalid Request Payload',
                  hint = 'missing_account_id';
    end if;

    if _account_id != _authenticated_account_id then
        raise exception 'Request Account Deletion Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_request_account_deletion';
    end if;

    select accounts.kickoff_account_deletion(
        _account_id,
        now()
    )
    into strict _kickoff_validation_failure_message;

    if _kickoff_validation_failure_message is not null then
        raise exception 'Request Account Deletion Failed'
            using detail = 'Invalid Request Payload',
                  hint = _kickoff_validation_failure_message;
    end if;

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function api.request_account_deletion(bigint) to authenticated;

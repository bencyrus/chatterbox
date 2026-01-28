-- account deletion domain: root orchestrator
--
-- this migration implements the root account deletion supervisor that
-- coordinates file deletion and account anonymization phases

-- =============================================================================
-- account deletion task tables
-- =============================================================================

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

-- =============================================================================
-- fact helpers
-- =============================================================================

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

-- =============================================================================
-- supervisor: orchestrates file deletion and anonymization phases
-- =============================================================================

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
    _max_attempts integer := 1; -- Do not retry
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

-- =============================================================================
-- kickoff: idempotent entry point (marks account as deleted immediately)
-- =============================================================================

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
    account_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _kickoff_validation_failure_message text;
begin
    if account_id is null then
        raise exception 'Request Account Deletion Failed'
            using detail = 'Invalid Request Payload',
                  hint = 'missing_account_id';
    end if;

    if account_id != _authenticated_account_id then
        raise exception 'Request Account Deletion Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_request_account_deletion';
    end if;

    select accounts.kickoff_account_deletion(
        account_id,
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

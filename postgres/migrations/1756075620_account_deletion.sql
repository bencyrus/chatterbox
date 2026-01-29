-- account deletion domain: root orchestrator
--
-- this migration implements the root account deletion supervisor that
-- coordinates file deletion and account anonymization phases

-- =============================================================================
-- account deletion task tables
-- =============================================================================

-- account deletion process: task and attempts (append-only)
create table accounts.account_deletion_task (
    account_deletion_task_id bigserial primary key,
    account_id bigint not null,
    created_at timestamp with time zone not null default now()
);

-- attempts (append-only, one per supervisor scheduling cycle)
create table accounts.account_deletion_attempt (
    account_deletion_attempt_id bigserial primary key,
    account_deletion_task_id bigint not null references accounts.account_deletion_task(account_deletion_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt succeeded (one per attempt at most)
create table accounts.account_deletion_attempt_succeeded (
    account_deletion_attempt_id bigint primary key references accounts.account_deletion_attempt(account_deletion_attempt_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt failed (one per attempt at most)
create table accounts.account_deletion_attempt_failed (
    account_deletion_attempt_id bigint primary key references accounts.account_deletion_attempt(account_deletion_attempt_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- fact helpers
-- =============================================================================

-- facts: has an in-progress account deletion task for this account?
-- "in-progress" means: a task exists for this account AND it has no terminal fact yet
-- (no attempt_succeeded row and no attempt_failed row). This prevents concurrent
-- deletion supervisors while still allowing multiple deletion tasks over time.
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
          and not exists (
              select 1
              from accounts.account_deletion_attempt a
              join accounts.account_deletion_attempt_succeeded s
                on s.account_deletion_attempt_id = a.account_deletion_attempt_id
              where a.account_deletion_task_id = adt.account_deletion_task_id
          )
          and not exists (
              select 1
              from accounts.account_deletion_attempt a
              join accounts.account_deletion_attempt_failed f
                on f.account_deletion_attempt_id = a.account_deletion_attempt_id
              where a.account_deletion_task_id = adt.account_deletion_task_id
          )
    );
$$;

-- facts: for kickoff_account_deletion
create or replace function accounts.kickoff_account_deletion_facts(
    _account_id bigint,
    out account_exists boolean,
    out in_progress_task_id bigint
)
language sql
stable
as $$
    select
        exists (select 1 from accounts.account a where a.account_id = _account_id),
        (
            select t.account_deletion_task_id
            from accounts.account_deletion_task t
            where t.account_id = _account_id
              and not exists (
                  select 1
                  from accounts.account_deletion_attempt a
                  join accounts.account_deletion_attempt_succeeded s
                    on s.account_deletion_attempt_id = a.account_deletion_attempt_id
                  where a.account_deletion_task_id = t.account_deletion_task_id
              )
              and not exists (
                  select 1
                  from accounts.account_deletion_attempt a
                  join accounts.account_deletion_attempt_failed f
                    on f.account_deletion_attempt_id = a.account_deletion_attempt_id
                  where a.account_deletion_task_id = t.account_deletion_task_id
              )
            order by t.created_at desc
            limit 1
        );
$$;

-- facts: has a succeeded attempt for account_deletion_task?
create or replace function accounts.has_account_deletion_succeeded_attempt(
    _account_deletion_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_deletion_attempt a
        join accounts.account_deletion_attempt_succeeded s on s.account_deletion_attempt_id = a.account_deletion_attempt_id
        where a.account_deletion_task_id = _account_deletion_task_id
    );
$$;

-- facts: has a failed attempt for account_deletion_task?
create or replace function accounts.has_account_deletion_failed_attempt(
    _account_deletion_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_deletion_attempt a
        join accounts.account_deletion_attempt_failed f on f.account_deletion_attempt_id = a.account_deletion_attempt_id
        where a.account_deletion_task_id = _account_deletion_task_id
    );
$$;

-- facts: count failed attempts for account_deletion_task
create or replace function accounts.count_account_deletion_failed_attempts(
    _account_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_deletion_attempt a
    join accounts.account_deletion_attempt_failed f on f.account_deletion_attempt_id = a.account_deletion_attempt_id
    where a.account_deletion_task_id = _account_deletion_task_id;
$$;

-- facts: count attempts for account_deletion_task
create or replace function accounts.count_account_deletion_attempts(
    _account_deletion_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_deletion_attempt a
    where a.account_deletion_task_id = _account_deletion_task_id;
$$;

-- facts: is file deletion stuck (max retries exceeded without success)?
-- (used by account deletion to detect permanently failed file deletions)
create or replace function files.is_file_deletion_stuck(
    _file_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.file_deletion_task t
        where t.file_deletion_task_id = (
            select t2.file_deletion_task_id
            from files.file_deletion_task t2
            where t2.file_id = _file_id
            order by t2.created_at desc
            limit 1
        )
          and not exists (
              select 1
              from files.file_deletion_attempt a
              join files.file_deletion_attempt_succeeded s
                on s.file_deletion_attempt_id = a.file_deletion_attempt_id
              where a.file_deletion_task_id = t.file_deletion_task_id
          )
          and (
              select count(*)
              from files.file_deletion_attempt a
              join files.file_deletion_attempt_failed f
                on f.file_deletion_attempt_id = a.file_deletion_attempt_id
              where a.file_deletion_task_id = t.file_deletion_task_id
          ) >= 3
    );
$$;

-- facts: is account anonymization stuck (max retries exceeded without success)?
-- (used by account deletion to detect permanently failed anonymization)
create or replace function accounts.is_account_anonymization_stuck(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_anonymization_task t
        where t.account_anonymization_task_id = (
            select t2.account_anonymization_task_id
            from accounts.account_anonymization_task t2
            where t2.account_id = _account_id
            order by t2.created_at desc
            limit 1
        )
          and not exists (
              select 1
              from accounts.account_anonymization_attempt a
              join accounts.account_anonymization_attempt_succeeded s
                on s.account_anonymization_attempt_id = a.account_anonymization_attempt_id
              where a.account_anonymization_task_id = t.account_anonymization_task_id
          )
          and (
              select count(*)
              from accounts.account_anonymization_attempt a
              join accounts.account_anonymization_attempt_failed f
                on f.account_anonymization_attempt_id = a.account_anonymization_attempt_id
              where a.account_anonymization_task_id = t.account_anonymization_task_id
          ) >= 3
    );
$$;

-- facts: all files deleted for account?
create or replace function accounts.all_account_files_deleted(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select not exists (
        select 1
        from files.account_files(_account_id) f
        where not files.is_file_deleted(f.file_id)
    );
$$;

-- facts: any file deletion stuck for account?
create or replace function accounts.any_account_file_deletion_stuck(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.account_files(_account_id) f
        where files.is_file_deletion_stuck(f.file_id)
    );
$$;

-- facts: aggregated facts for account_deletion_supervisor
create or replace function accounts.account_deletion_supervisor_facts(
    _account_deletion_task_id bigint,
    out account_id bigint,
    out has_success boolean,
    out has_failure boolean,
    out num_failures integer,
    out num_attempts integer,
    out all_files_deleted boolean,
    out any_file_stuck boolean,
    out is_anonymized boolean,
    out anonymization_stuck boolean
)
language sql
stable
as $$
    select
        t.account_id,
        accounts.has_account_deletion_succeeded_attempt(_account_deletion_task_id),
        accounts.has_account_deletion_failed_attempt(_account_deletion_task_id),
        accounts.count_account_deletion_failed_attempts(_account_deletion_task_id),
        accounts.count_account_deletion_attempts(_account_deletion_task_id),
        accounts.all_account_files_deleted(t.account_id),
        accounts.any_account_file_deletion_stuck(t.account_id),
        accounts.is_account_anonymized(t.account_id),
        accounts.is_account_anonymization_stuck(t.account_id)
    from accounts.account_deletion_task t
    where t.account_deletion_task_id = _account_deletion_task_id;
$$;

-- =============================================================================
-- effect functions
-- =============================================================================

-- effect: record account deletion failure
create or replace function accounts.record_account_deletion_failure(
    _account_deletion_task_id bigint,
    _error_message text
)
returns void
language plpgsql
security definer
as $$
declare
    _attempt_id bigint;
begin
    -- create an attempt to record the failure against
    insert into accounts.account_deletion_attempt (account_deletion_task_id)
    values (_account_deletion_task_id)
    returning account_deletion_attempt_id into _attempt_id;

    insert into accounts.account_deletion_attempt_failed (account_deletion_attempt_id, error_message)
    values (_attempt_id, _error_message)
    on conflict (account_deletion_attempt_id) do nothing;
end;
$$;

-- effect: record account deletion success
create or replace function accounts.record_account_deletion_success(
    _account_deletion_task_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _attempt_id bigint;
begin
    -- create an attempt to record the success against
    insert into accounts.account_deletion_attempt (account_deletion_task_id)
    values (_account_deletion_task_id)
    returning account_deletion_attempt_id into _attempt_id;

    insert into accounts.account_deletion_attempt_succeeded (account_deletion_attempt_id)
    values (_attempt_id)
    on conflict (account_deletion_attempt_id) do nothing;
end;
$$;

-- effect: kick off file deletions for account
create or replace function accounts.kickoff_account_file_deletions(
    _account_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _file_id bigint;
begin
    for _file_id in
        select f.file_id
        from files.account_files(_account_id) f
    loop
        perform files.kickoff_file_deletion(_file_id, now());
    end loop;
end;
$$;

-- effect: schedule supervisor recheck with exponential backoff
create or replace function accounts.schedule_account_deletion_supervisor_recheck(
    _account_deletion_task_id bigint,
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
            'db_function', 'accounts.account_deletion_supervisor',
            'account_deletion_task_id', _account_deletion_task_id,
            'run_count', _run_count + 1
        ),
        _next_check_at
    );
end;
$$;

-- =============================================================================
-- supervisor: orchestrates file deletion and anonymization phases
-- =============================================================================

create or replace function accounts.account_deletion_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_deletion_task_id bigint := (_payload->>'account_deletion_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _max_runs integer := 50;
    _max_attempts integer := 1; -- root supervisor does not retry on permanent failures
    _facts record;
begin
    -- 1. VALIDATION
    if _account_deletion_task_id is null then
        return jsonb_build_object('status', 'missing_account_deletion_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'account_deletion_supervisor exceeded max runs'
            using detail = 'Possible infinite loop detected',
                  hint = format('task_id=%s, run_count=%s', _account_deletion_task_id, _run_count);
    end if;

    -- 2. LOCK (before facts)
    perform 1
    from accounts.account_deletion_task t
    where t.account_deletion_task_id = _account_deletion_task_id
    for update;

    -- 3. FACTS
    _facts := accounts.account_deletion_supervisor_facts(_account_deletion_task_id);

    if _facts.account_id is null then
        return jsonb_build_object('status', 'account_deletion_task_not_found');
    end if;

    -- 4. LOGIC + EFFECTS

    -- terminal: already succeeded
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    -- terminal: already failed
    if _facts.has_failure then
        return jsonb_build_object('status', 'failed');
    end if;

    -- phase 1: file deletion
    if not _facts.all_files_deleted then
        -- kick off file deletions for files that don't have in-progress tasks yet
        -- (if previous tasks hit max attempts, this will create a fresh task)
        perform accounts.kickoff_account_file_deletions(_facts.account_id);

        -- schedule recheck and exit
        perform accounts.schedule_account_deletion_supervisor_recheck(
            _account_deletion_task_id,
            _facts.num_failures,
            _run_count
        );

        if _facts.any_file_stuck then
            return jsonb_build_object('status', 'waiting_for_file_deletions_retrying');
        end if;
        return jsonb_build_object('status', 'waiting_for_file_deletions');
    end if;

    -- phase 2: anonymization
    if not _facts.is_anonymized then
        -- kick off anonymization (if previous tasks hit max attempts, this creates a fresh task)
        perform accounts.kickoff_account_anonymization(_facts.account_id, now());

        -- schedule recheck and exit
        perform accounts.schedule_account_deletion_supervisor_recheck(
            _account_deletion_task_id,
            _facts.num_failures,
            _run_count
        );

        if _facts.anonymization_stuck then
            return jsonb_build_object('status', 'waiting_for_anonymization_retrying');
        end if;
        return jsonb_build_object('status', 'waiting_for_anonymization');
    end if;

    -- phase 3: all done - record success
    perform accounts.record_account_deletion_success(_account_deletion_task_id);

    return jsonb_build_object('status', 'succeeded');
end;
$$;

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
    _facts record;
begin
    -- 1. VALIDATION
    if _account_id is null then
        validation_failure_message := 'missing_account_id';
        return;
    end if;

    -- 2. FACTS
    _facts := accounts.kickoff_account_deletion_facts(_account_id);

    -- 3. LOGIC
    if not _facts.account_exists then
        validation_failure_message := 'account_not_found';
        return;
    end if;

    -- if there's already an in-progress task, skip (supervisor already running)
    if _facts.in_progress_task_id is not null then
        return;
    end if;

    -- 4. EFFECTS
    insert into accounts.account_deletion_task (account_id)
    values (_account_id)
    returning account_deletion_task_id
    into _account_deletion_task_id;

    -- mark account as deleted immediately when user requests deletion
    perform accounts.add_account_flag(_account_id, 'deleted');

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'accounts.account_deletion_supervisor',
            'account_deletion_task_id', _account_deletion_task_id
        ),
        coalesce(_scheduled_at, now())
    );

    return;
end;
$$;

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

-- =============================================================================
-- grants
-- =============================================================================

grant execute on function accounts.record_account_deletion_failure(bigint, text) to worker_service_user;
grant execute on function accounts.record_account_deletion_success(bigint) to worker_service_user;
grant execute on function accounts.kickoff_account_file_deletions(bigint) to worker_service_user;
grant execute on function accounts.schedule_account_deletion_supervisor_recheck(bigint, integer, integer) to worker_service_user;
grant execute on function accounts.account_deletion_supervisor(jsonb) to worker_service_user;
grant execute on function accounts.kickoff_account_deletion(bigint, timestamp with time zone) to worker_service_user;
grant execute on function api.request_account_deletion(bigint) to authenticated;

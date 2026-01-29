-- account anonymization domain: PII removal process
--
-- this migration implements account anonymization via a supervisor pattern

-- =============================================================================
-- helper functions for anonymization
-- =============================================================================

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

-- =============================================================================
-- anonymization task tables
-- =============================================================================

-- account anonymization process: task and attempts (append-only)
create table accounts.account_anonymization_task (
    account_anonymization_task_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempts (append-only, one per scheduled attempt)
create table accounts.account_anonymization_attempt (
    account_anonymization_attempt_id bigserial primary key,
    account_anonymization_task_id bigint not null references accounts.account_anonymization_task(account_anonymization_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt succeeded (one per attempt at most)
create table accounts.account_anonymization_attempt_succeeded (
    account_anonymization_attempt_id bigint primary key references accounts.account_anonymization_attempt(account_anonymization_attempt_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt failed (one per attempt at most)
create table accounts.account_anonymization_attempt_failed (
    account_anonymization_attempt_id bigint primary key references accounts.account_anonymization_attempt(account_anonymization_attempt_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- fact helpers
-- =============================================================================

-- facts: has an in-progress anonymization task for this account?
-- "in-progress" means: a task exists for this account with no success yet and
-- it has not yet reached the max failure threshold.
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
          and not exists (
              select 1
              from accounts.account_anonymization_attempt a
              join accounts.account_anonymization_attempt_succeeded s
                on s.account_anonymization_attempt_id = a.account_anonymization_attempt_id
              where a.account_anonymization_task_id = aat.account_anonymization_task_id
          )
          and (
              select count(*)
              from accounts.account_anonymization_attempt a
              join accounts.account_anonymization_attempt_failed f
                on f.account_anonymization_attempt_id = a.account_anonymization_attempt_id
              where a.account_anonymization_task_id = aat.account_anonymization_task_id
          ) < 3
    );
$$;

-- facts: has a succeeded attempt for account_anonymization_task?
create or replace function accounts.has_account_anonymization_succeeded_attempt(
    _account_anonymization_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_anonymization_attempt a
        join accounts.account_anonymization_attempt_succeeded s on s.account_anonymization_attempt_id = a.account_anonymization_attempt_id
        where a.account_anonymization_task_id = _account_anonymization_task_id
    );
$$;

-- facts: count failed attempts for account_anonymization_task
create or replace function accounts.count_account_anonymization_failed_attempts(
    _account_anonymization_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_anonymization_attempt a
    join accounts.account_anonymization_attempt_failed f on f.account_anonymization_attempt_id = a.account_anonymization_attempt_id
    where a.account_anonymization_task_id = _account_anonymization_task_id;
$$;

-- facts: count attempts for account_anonymization_task
create or replace function accounts.count_account_anonymization_attempts(
    _account_anonymization_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from accounts.account_anonymization_attempt a
    where a.account_anonymization_task_id = _account_anonymization_task_id;
$$;

-- facts: is account anonymized (via flag)?
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

-- facts: aggregated facts for account_anonymization_supervisor
create or replace function accounts.account_anonymization_supervisor_facts(
    _account_anonymization_task_id bigint,
    out is_anonymized boolean,
    out has_success boolean,
    out num_failures integer,
    out num_attempts integer
)
language sql
stable
as $$
    select
        (select accounts.is_account_anonymized(t.account_id) from accounts.account_anonymization_task t where t.account_anonymization_task_id = _account_anonymization_task_id),
        accounts.has_account_anonymization_succeeded_attempt(_account_anonymization_task_id),
        accounts.count_account_anonymization_failed_attempts(_account_anonymization_task_id),
        accounts.count_account_anonymization_attempts(_account_anonymization_task_id);
$$;

-- facts: get anonymization payload facts from attempt_id
create or replace function accounts.get_anonymization_payload_facts(
    _account_anonymization_attempt_id bigint,
    out account_id bigint,
    out is_anonymized boolean
)
language sql
stable
as $$
    select
        t.account_id,
        accounts.is_account_anonymized(t.account_id)
    from accounts.account_anonymization_attempt a
    join accounts.account_anonymization_task t on t.account_anonymization_task_id = a.account_anonymization_task_id
    where a.account_anonymization_attempt_id = _account_anonymization_attempt_id;
$$;

-- =============================================================================
-- helpers: reusable operations
-- =============================================================================

-- helper: record attempt succeeded (idempotent)
create or replace function accounts.record_anonymization_attempt_succeeded(
    _account_anonymization_attempt_id bigint
)
returns void
language sql
as $$
    insert into accounts.account_anonymization_attempt_succeeded (account_anonymization_attempt_id)
    values (_account_anonymization_attempt_id)
    on conflict (account_anonymization_attempt_id) do nothing;
$$;

-- =============================================================================
-- handlers: before / success / error for anonymization
-- =============================================================================

-- before handler: build payload from account_anonymization_attempt_id
create or replace function accounts.get_anonymization_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _account_anonymization_attempt_id bigint := (_payload->>'account_anonymization_attempt_id')::bigint;
    _facts record;
begin
    if _account_anonymization_attempt_id is null then
        return jsonb_build_object('status', 'missing_account_anonymization_attempt_id');
    end if;

    _facts := accounts.get_anonymization_payload_facts(_account_anonymization_attempt_id);

    if _facts.account_id is null then
        return jsonb_build_object('status', 'account_anonymization_attempt_not_found');
    end if;

    -- check if already anonymized
    if _facts.is_anonymized then
        return jsonb_build_object('status', 'account_already_anonymized');
    end if;

    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'account_id', _facts.account_id
        )
    );
end;
$$;

-- success handler: record success fact
-- receives: { original_payload: { account_anonymization_attempt_id, ... }, worker_payload: { ... } }
create or replace function accounts.record_anonymization_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_anonymization_attempt_id bigint := (_payload->'original_payload'->>'account_anonymization_attempt_id')::bigint;
begin
    if _account_anonymization_attempt_id is null then
        return jsonb_build_object('status', 'missing_account_anonymization_attempt_id');
    end if;

    perform accounts.record_anonymization_attempt_succeeded(_account_anonymization_attempt_id);

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- error handler: record failure fact
-- receives: { original_payload: { account_anonymization_attempt_id, ... }, error: "..." }
create or replace function accounts.record_anonymization_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_anonymization_attempt_id bigint := (_payload->'original_payload'->>'account_anonymization_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _account_anonymization_attempt_id is null then
        return jsonb_build_object('status', 'missing_account_anonymization_attempt_id');
    end if;

    insert into accounts.account_anonymization_attempt_failed (account_anonymization_attempt_id, error_message)
    values (_account_anonymization_attempt_id, _error_message)
    on conflict (account_anonymization_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- =============================================================================
-- work function: performs the actual anonymization
-- =============================================================================

-- facts: for do_anonymization
create or replace function accounts.do_anonymization_facts(
    _account_anonymization_attempt_id bigint,
    out account_id bigint,
    out is_anonymized boolean
)
language sql
stable
as $$
    select
        t.account_id,
        accounts.is_account_anonymized(t.account_id)
    from accounts.account_anonymization_attempt a
    join accounts.account_anonymization_task t on t.account_anonymization_task_id = a.account_anonymization_task_id
    where a.account_anonymization_attempt_id = _account_anonymization_attempt_id;
$$;

-- the actual anonymization work function (called by worker via db_function)
create or replace function accounts.do_anonymization(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_anonymization_attempt_id bigint := (_payload->>'account_anonymization_attempt_id')::bigint;
    _facts record;
begin
    -- 1. VALIDATION
    if _account_anonymization_attempt_id is null then
        return jsonb_build_object('status', 'missing_account_anonymization_attempt_id');
    end if;

    -- 2. FACTS
    _facts := accounts.do_anonymization_facts(_account_anonymization_attempt_id);

    -- 3. LOGIC
    if _facts.account_id is null then
        return jsonb_build_object('status', 'account_anonymization_attempt_not_found');
    end if;

    if _facts.is_anonymized then
        perform accounts.record_anonymization_attempt_succeeded(_account_anonymization_attempt_id);
        return jsonb_build_object('status', 'already_anonymized');
    end if;

    -- 4. EFFECTS
    perform accounts.anonymize_account_record(_facts.account_id);
    perform accounts.add_account_flag(_facts.account_id, 'anonymized');
    perform accounts.record_anonymization_attempt_succeeded(_account_anonymization_attempt_id);

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- =============================================================================
-- effect functions
-- =============================================================================

-- effect: schedule an anonymization attempt
create or replace function accounts.schedule_anonymization_attempt(
    _account_anonymization_task_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _account_anonymization_attempt_id bigint;
begin
    insert into accounts.account_anonymization_attempt (account_anonymization_task_id)
    values (_account_anonymization_task_id)
    returning account_anonymization_attempt_id into _account_anonymization_attempt_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'accounts.do_anonymization',
            'account_anonymization_attempt_id', _account_anonymization_attempt_id
        ),
        now()
    );
end;
$$;

-- effect: schedule supervisor recheck with exponential backoff
create or replace function accounts.schedule_anonymization_supervisor_recheck(
    _account_anonymization_task_id bigint,
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
            'db_function', 'accounts.account_anonymization_supervisor',
            'account_anonymization_task_id', _account_anonymization_task_id,
            'run_count', _run_count + 1
        ),
        _next_check_at
    );
end;
$$;

-- =============================================================================
-- supervisor: orchestrates anonymization via worker
-- =============================================================================

create or replace function accounts.account_anonymization_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _account_anonymization_task_id bigint := (_payload->>'account_anonymization_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _max_runs integer := 20;
    _max_attempts integer := 3;
    _facts record;
begin
    -- 1. VALIDATION
    if _account_anonymization_task_id is null then
        return jsonb_build_object('status', 'missing_account_anonymization_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'account_anonymization_supervisor exceeded max runs'
            using detail = 'Possible infinite loop detected',
                  hint = format('task_id=%s, run_count=%s', _account_anonymization_task_id, _run_count);
    end if;

    -- 2. LOCK (before facts)
    perform 1
    from accounts.account_anonymization_task t
    where t.account_anonymization_task_id = _account_anonymization_task_id
    for update;

    -- 3. FACTS
    _facts := accounts.account_anonymization_supervisor_facts(_account_anonymization_task_id);

    -- 4. LOGIC + EFFECTS
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    -- if account already anonymized, nothing to do
    if _facts.is_anonymized then
        return jsonb_build_object('status', 'already_anonymized');
    end if;

    if _facts.num_attempts = _facts.num_failures then
        perform accounts.schedule_anonymization_attempt(_account_anonymization_task_id);
    end if;

    perform accounts.schedule_anonymization_supervisor_recheck(
        _account_anonymization_task_id,
        _facts.num_failures,
        _run_count
    );

    return jsonb_build_object('status', 'scheduled');
end;
$$;

-- =============================================================================
-- kickoff: idempotent entry point
-- =============================================================================

-- facts: for kickoff_account_anonymization
create or replace function accounts.kickoff_account_anonymization_facts(
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
            select t.account_anonymization_task_id
            from accounts.account_anonymization_task t
            where t.account_id = _account_id
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
              ) < 3
            order by t.created_at desc
            limit 1
        );
$$;

-- effect: create task and enqueue supervisor
create or replace function accounts.create_and_enqueue_anonymization_task(
    _account_id bigint,
    _scheduled_at timestamp with time zone
)
returns void
language plpgsql
security definer
as $$
declare
    _account_anonymization_task_id bigint;
begin
    insert into accounts.account_anonymization_task (account_id)
    values (_account_id)
    returning account_anonymization_task_id
    into _account_anonymization_task_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'accounts.account_anonymization_supervisor',
            'account_anonymization_task_id', _account_anonymization_task_id
        ),
        _scheduled_at
    );
end;
$$;

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
    _facts record;
begin
    -- 1. VALIDATION
    if _account_id is null then
        validation_failure_message := 'missing_account_id';
        return;
    end if;

    -- 2. FACTS
    _facts := accounts.kickoff_account_anonymization_facts(_account_id);

    -- 3. LOGIC
    if not _facts.account_exists then
        validation_failure_message := 'account_not_found';
        return;
    end if;

    if _facts.in_progress_task_id is not null then
        return; -- already kicked off, nothing to do
    end if;

    -- 4. EFFECTS
    perform accounts.create_and_enqueue_anonymization_task(_account_id, _scheduled_at);

    return;
end;
$$;

-- =============================================================================
-- grants
-- =============================================================================

grant execute on function accounts.get_anonymization_payload(jsonb) to worker_service_user;
grant execute on function accounts.record_anonymization_success(jsonb) to worker_service_user;
grant execute on function accounts.record_anonymization_failure(jsonb) to worker_service_user;
grant execute on function accounts.do_anonymization(jsonb) to worker_service_user;
grant execute on function accounts.schedule_anonymization_attempt(bigint) to worker_service_user;
grant execute on function accounts.schedule_anonymization_supervisor_recheck(bigint, integer, integer) to worker_service_user;
grant execute on function accounts.account_anonymization_supervisor(jsonb) to worker_service_user;
grant execute on function accounts.kickoff_account_anonymization(bigint, timestamp with time zone) to worker_service_user;

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

-- =============================================================================
-- anonymization task tables
-- =============================================================================

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

-- =============================================================================
-- fact helpers
-- =============================================================================

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

-- =============================================================================
-- kickoff: idempotent entry point
-- =============================================================================

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

-- =============================================================================
-- supervisor: orchestrates anonymization via worker
-- =============================================================================

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

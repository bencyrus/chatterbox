begin;

-- internal schemas for queues worker internals
create schema queues;
create schema worker;
-- service-facing schema (public, x-api-key required)
create schema service_api;

-- domain for all supported task types
create domain queues.task_type as text
    check (value in ('email', 'sms'));

-- tasks: immutable descriptor of what needs to be done
create table queues.task (
    task_id bigserial primary key,
    task_type queues.task_type not null,
    resource_id bigint not null,
    max_attempts integer not null default 5 check (max_attempts >= 1),
    created_at timestamp with time zone not null default now()
);

-- jobs: scheduled execution opportunities for a task
create table queues.job (
    job_id bigserial primary key,
    task_id bigint not null references queues.task(task_id) on delete cascade,
    priority integer not null default 1 check (priority >= 1),
    scheduled_at timestamp with time zone not null default now(),
    created_at timestamp with time zone not null default now()
);

-- leases: time-bound claims by workers
create table queues.lease (
    lease_id bigserial primary key,
    job_id bigint not null references queues.job(job_id) on delete cascade,
    worker_id text not null,
    leased_at timestamp with time zone not null default now(),
    expires_at timestamp with time zone not null
);

-- attempts: outcomes for each lease attempt (append-only)
create table queues.attempt (
    attempt_id bigserial primary key,
    job_id bigint not null references queues.job(job_id) on delete cascade,
    lease_id bigint not null references queues.lease(lease_id) on delete cascade,
    attempted_at timestamp with time zone not null default now(),
    success boolean not null,
    error_code text,
    error_message text
);

-- create a task and enqueue its initial job
create or replace function queues.enqueue(
    _task_type queues.task_type,
    _resource_id bigint,
    _job_priority integer default 1,
    _num_max_attempts integer default 5,
    _scheduled_at timestamp with time zone default now()
)
returns queues.job
language plpgsql
security definer
as $$
declare
    _task_id bigint;
    _created_job queues.job;
begin
    insert into queues.task (task_type, resource_id, max_attempts)
    values (_task_type, _resource_id, coalesce(_num_max_attempts, 5))
    returning task_id
    into _task_id;

    insert into queues.job (task_id, priority, scheduled_at)
    values (_task_id, coalesce(_job_priority, 1), coalesce(_scheduled_at, now()))
    returning *
    into _created_job;
    return _created_job;
end;
$$;

-- typed dequeued job returned to internal callers
create type queues.dequeued_job as (
    job_id bigint,
    lease_id bigint,
    task_type queues.task_type,
    resource_id bigint,
    priority integer,
    scheduled_at timestamp with time zone
);

-- result for leasing the next ready job (with validation status)
create type queues.lease_next_ready_job_result as (
    validation_failure_message text,
    job queues.dequeued_job
);

-- select the next ready job and create a lease for the worker
create or replace function queues.lease_next_ready_job(
    _worker_id text,
    _lease_seconds integer default 60,
    _filter_task_type queues.task_type default null
)
returns queues.lease_next_ready_job_result
language plpgsql
security definer
as $$
declare
    _selected_job_id bigint;
    _selected_task_type queues.task_type;
    _selected_resource_id bigint;
    _selected_priority integer;
    _selected_scheduled_at timestamptz;
    _created_lease_id bigint;
    _job_record queues.dequeued_job;
begin
    if _worker_id is null or btrim(_worker_id) = '' then
        return ('worker_id_missing', null)::queues.lease_next_ready_job_result;
    end if;

    select
        j.job_id,
        t.task_type,
        t.resource_id,
        j.priority,
        j.scheduled_at
    into _selected_job_id,
        _selected_task_type,
        _selected_resource_id,
        _selected_priority,
        _selected_scheduled_at
    from queues.job j
    join queues.task t on t.task_id = j.task_id
    where j.scheduled_at <= now()
        and (
            _filter_task_type is null 
            or t.task_type = _filter_task_type
        )
        and not exists (
            select 1
            from queues.attempt a
            where a.job_id = j.job_id
        )
        and not exists (
            select 1
            from queues.lease l
            where l.job_id = j.job_id
                and l.expires_at > now()
                and not exists (
                    select 1
                    from queues.attempt a2
                    where a2.lease_id = l.lease_id
                )
        )
        and not exists (
            select 1
            from queues.attempt a
            join queues.job jj on jj.job_id = a.job_id
            where jj.task_id = j.task_id
                and a.success
        )
        and (
            select count(*)
            from queues.attempt a
            join queues.job jj on jj.job_id = a.job_id
            where jj.task_id = j.task_id
        ) < t.max_attempts
    order by
        j.priority desc,
        j.scheduled_at,
        j.job_id
    limit 1
    for update skip locked;

    if _selected_job_id is null then
        return (null, null)::queues.lease_next_ready_job_result;
    end if;

    insert into queues.lease (
        job_id,
        worker_id,
        expires_at
    )
    values (
        _selected_job_id,
        _worker_id,
        now() + make_interval(secs => greatest(1, coalesce(_lease_seconds, 60)))
    )
    returning lease_id
    into _created_lease_id;

    _job_record := (
        _selected_job_id,
        _created_lease_id,
        _selected_task_type,
        _selected_resource_id,
        _selected_priority,
        _selected_scheduled_at
    );
    return (null, _job_record)::queues.lease_next_ready_job_result;
end;
$$;

-- record success
-- record a successful processing attempt for a leased job
create or replace function queues.record_attempt_success(
    _job_id bigint,
    _lease_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _attempt queues.attempt;
begin
    insert into queues.attempt (job_id, lease_id, success)
    values (_job_id, _lease_id, true)
    returning *
    into _attempt;
    return;
end;
$$;

-- record failure
-- record a failed processing attempt for a leased job
create or replace function queues.record_attempt_failure(
    _job_id bigint,
    _lease_id bigint,
    _error_code text default null,
    _error_message text default null
)
returns void
language plpgsql
security definer
as $$
declare
    _attempt queues.attempt;
begin
    insert into queues.attempt (
        job_id,
        lease_id,
        success,
        error_code,
        error_message
    )
    values (
        _job_id,
        _lease_id,
        false,
        _error_code,
        _error_message
    )
    returning *
    into _attempt;
    return;
end;
$$;

-- result of scheduling a retry for a failed job
-- result of scheduling a retry (next job id and its scheduled time)
create type queues.retry_schedule_result as (
    scheduled boolean,
    next_job_id bigint,
    next_scheduled_at timestamp with time zone
);

-- compute next retry time and enqueue a new job if under max attempts
create or replace function queues.schedule_retry_for_failed_job(
    _job_id bigint,
    _base_delay_seconds integer default 30
)
returns queues.retry_schedule_result
language plpgsql
security definer
as $$
declare
    _task_id bigint;
    _count_attempts_before int;
    _num_max_attempts int;
    _job_priority int;
    _next_scheduled_at timestamptz;
    _new_job_id bigint;
    _result queues.retry_schedule_result;
begin
    select
        j.task_id,
        t.max_attempts,
        j.priority
    into _task_id,
        _num_max_attempts,
        _job_priority
    from queues.job j
    join queues.task t on t.task_id = j.task_id
    where j.job_id = _job_id;

    select count(*)
    into _count_attempts_before
    from queues.attempt a
    join queues.job jj on jj.job_id = a.job_id
    where jj.task_id = _task_id;

    if _count_attempts_before < _num_max_attempts then
        _next_scheduled_at := now() + make_interval(secs => (greatest(1, coalesce(_base_delay_seconds, 30))::double precision * power(2, _count_attempts_before - 1)));
        insert into queues.job (task_id, priority, scheduled_at)
        values (_task_id, coalesce(_job_priority, 1), _next_scheduled_at)
        returning job_id
        into _new_job_id;
        _result := (true, _new_job_id, _next_scheduled_at);
        return _result;
    else
        _result := (false, null, null);
        return _result;
    end if;
end;
$$;

-- api key table
create table auth.api_key (
    api_key_id bigserial primary key,
    key uuid not null,
    name text not null,
    created_at timestamp with time zone not null default now(),
    last_used_at timestamp with time zone
);

-- usage log for api key validations
create table auth.api_key_usage (
    api_key_usage_id bigserial primary key,
    api_key_id bigint not null references auth.api_key(api_key_id) on delete cascade,
    used_at timestamp with time zone not null default now()
);

-- result type for creating an api key with validation status
-- result of creating an API key (returns plaintext once)
create type auth.create_api_key_result as (
    validation_failure_message text,
    api_key auth.api_key
);

-- create an API key with a human-readable name
create or replace function auth.create_api_key(_name text)
returns auth.create_api_key_result
language plpgsql
security definer
as $$
declare
    _raw_key uuid := gen_random_uuid();
    _created_api_key auth.api_key;
begin
    if _name is null or btrim(_name) = '' then
        return ('name_missing', null)::auth.create_api_key_result;
    end if;
    
    insert into auth.api_key (key, name)
    values (_raw_key, _name)
    returning * into _created_api_key;
    return (null, _created_api_key)::auth.create_api_key_result;
end;
$$;

-- validate an API key value and record usage
create or replace function auth.validate_api_key(_key text)
returns boolean
language plpgsql
security definer
as $$
declare
    _api_key_id bigint;
begin
    select k.api_key_id
    into _api_key_id
    from auth.api_key k
    where k.key::text = _key
    limit 1;

    if _api_key_id is null then
        return false;
    end if;

    -- record usage instead of updating last_used_at
    insert into auth.api_key_usage (api_key_id)
    values (_api_key_id);
    return true;
end;
$$;

-- assert presence and validity of x-api-key header for service endpoints
create or replace function auth.assert_api_key()
returns void
language plpgsql
security definer
as $$
declare
    _header_api_key text := current_setting('request.header.x-api-key', true);
begin
    if _header_api_key is null or btrim(_header_api_key) = '' then
        raise exception 'Service API Failed'
            using detail = 'Missing API Key',
                  hint = 'missing_api_key';
    end if;
    
    if not auth.validate_api_key(_header_api_key) then
        raise exception 'Service API Failed'
            using detail = 'Invalid API Key',
                  hint = 'invalid_api_key';
    end if;
end;
$$;

-- pre-request hook (PostgREST) to enforce x-api-key when targeting service_api
create or replace function internal.pre_request()
returns void
language plpgsql
security definer
as $$
declare
    _accept_profile text := current_setting('request.header.accept-profile', true);
    _content_profile text := current_setting('request.header.content-profile', true);
begin
    -- Enforce API key only when the client targets service_api via profile headers
    -- Reference: PostgREST schema selection with Accept-Profile / Content-Profile
    -- https://docs.postgrest.org/en/v12/references/api/schemas.html
    -- Use Accept-Profile for GET/HEAD; Content-Profile for others
    if _accept_profile = 'service_api' or _content_profile = 'service_api' then
        perform auth.assert_api_key();
    end if;
end;
$$;

-- service_api: report result (success/failure), apply retry policy on failure
-- service response for reporting task result
create type service_api.report_task_result_response as (
    completed boolean,
    scheduled_retry boolean,
    next_job_id bigint,
    next_scheduled_at timestamp with time zone
);

-- service endpoint: report success/failure of a leased job and schedule retry on failure
create or replace function service_api.report_task_result(
    worker_id text,
    job_id bigint,
    lease_id bigint,
    succeeded boolean,
    error_code text default null,
    error_message text default null,
    base_delay_seconds integer default 30
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _lease queues.lease;
    _retry_schedule_result queues.retry_schedule_result;
    _report_task_result service_api.report_task_result_response;
begin

    select *
    into _lease
    from queues.lease l
    where l.lease_id = $3
        and l.job_id = $2;

    if _lease.lease_id is null then
        raise exception 'Task Result Failed'
            using detail = 'Invalid Lease',
                  hint = 'invalid_lease';
    end if;
    if _lease.worker_id <> worker_id then
        raise exception 'Task Result Failed'
            using detail = 'Not Lease Owner',
                  hint = 'not_lease_owner';
    end if;
    if _lease.expires_at <= now() then
        raise exception 'Task Result Failed'
            using detail = 'Lease Expired',
                  hint = 'lease_expired';
    end if;
    if exists (
            select 1
            from queues.attempt a
            where a.lease_id = $3
        ) then
            raise exception 'Task Result Failed'
                using detail = 'Already Attempted',
                    hint = 'already_attempted';
    end if;

    if succeeded then
        perform queues.record_attempt_success(job_id, lease_id);
        _report_task_result := (true, false, null, null);
    else
        perform queues.record_attempt_failure(job_id, lease_id, error_code, error_message);
        select queues.schedule_retry_for_failed_job(job_id, base_delay_seconds)
        into _retry_schedule_result;
        _report_task_result := (
            false,
            coalesce(_retry_schedule_result.scheduled, false),
            case when _retry_schedule_result.scheduled then _retry_schedule_result.next_job_id end,
            _retry_schedule_result.next_scheduled_at
        );
    end if;
    return to_jsonb(_report_task_result);
end;
$$;

commit;

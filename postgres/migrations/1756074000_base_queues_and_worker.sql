-- internal schemas for queues and function runner
create schema queues;

-- worker service user with minimal grants
create user worker_service_user with login password '{secrets.worker_service_user_password}';
grant usage on schema queues to worker_service_user;
grant usage on schema internal to worker_service_user;

-- domain for all supported task types
create domain queues.task_type as text
    check (value in ('db_function', 'email', 'sms'));

-- queues.task: unit of work with payload and scheduling (immutable after creation)
create table queues.task (
    task_id bigserial primary key,
    task_type queues.task_type not null,
    payload jsonb not null,
    enqueued_at timestamp with time zone not null default now(),
    scheduled_at timestamp with time zone not null default now()
);

-- queues.task_lease: append-only record of task claim attempts with expiry
create table queues.task_lease (
    task_lease_id bigserial primary key,
    task_id bigint not null references queues.task(task_id) on delete cascade,
    leased_at timestamp with time zone not null default now(),
    expires_at timestamp with time zone not null
);

-- queues.task_completed: terminal state for completed tasks (one per task)
create table queues.task_completed (
    task_id bigint primary key references queues.task(task_id) on delete cascade,
    completed_at timestamp with time zone not null default now()
);

-- queues.error: append-only worker/handler errors for observability
create table queues.error (
    error_id bigserial primary key,
    task_id bigint references queues.task(task_id) on delete set null,
    error_message text not null,
    created_at timestamp with time zone not null default now()
);

-- enqueue a task (used by supervisors/handlers; worker never enqueues)
create or replace function queues.enqueue(
    _task_type queues.task_type,
    _payload jsonb,
    _scheduled_at timestamp with time zone default now()
)
returns void
language plpgsql
security definer
as $$
begin
    insert into queues.task (task_type, payload, scheduled_at)
    values (
        _task_type,
        coalesce(_payload, '{}'::jsonb),
        coalesce(_scheduled_at, now())
    );
end;
$$;

-- dequeue and claim the next available task with a time-limited lease
-- task is available when: not completed AND no active lease (expires_at > now())
-- if worker crashes, lease expires and task becomes available again
create or replace function queues.dequeue_next_available_task()
returns queues.task
language plpgsql
security definer
as $$
declare
    _task queues.task;
    _lease_duration interval := interval '5 minutes';
begin
    -- find and lock an available task
    select t.* into _task
    from queues.task t
    where not exists (
        select 1 from queues.task_completed c
        where c.task_id = t.task_id
    )
    and not exists (
        select 1 from queues.task_lease l
        where l.task_id = t.task_id
        and l.expires_at > now()
    )
    and t.scheduled_at <= now()
    order by t.scheduled_at, t.task_id
    limit 1
    for update skip locked;

    if _task.task_id is null then
        return null;
    end if;

    -- append a lease record
    insert into queues.task_lease (task_id, expires_at)
    values (_task.task_id, now() + _lease_duration);

    return _task;
end;
$$;

-- mark a task as completed (idempotent)
create or replace function queues.complete_task(_task_id bigint)
returns void
language plpgsql
security definer
as $$
begin
    insert into queues.task_completed (task_id)
    values (_task_id)
    on conflict (task_id) do nothing;
end;
$$;

-- record a task failure with error message (for observability; does not mark terminal)
create or replace function queues.fail_task(
    _task_id bigint,
    _error_message text
)
returns void
language plpgsql
security definer
as $$
begin
    insert into queues.error (task_id, error_message)
    values (_task_id, coalesce(_error_message, ''));
end;
$$;

-- function runner: invokes target function (payload jsonb) -> jsonb
create or replace function internal.run_function(
    function_name text,
    payload jsonb
)
returns jsonb
language plpgsql
security invoker
as $$
declare
    _result jsonb;
begin
    execute format('select %s($1)::jsonb', function_name)
    into _result
    using coalesce(payload, '{}'::jsonb);

    return coalesce(_result, '{}'::jsonb);
end;
$$;

-- minimal grants for worker
grant execute on function queues.dequeue_next_available_task() to worker_service_user;
grant execute on function queues.complete_task(bigint) to worker_service_user;
grant execute on function queues.fail_task(bigint, text) to worker_service_user;
grant execute on function internal.run_function(text, jsonb) to worker_service_user;

begin;

-- internal schemas for queues and function runner
create schema queues;

-- worker service user with minimal grants
create user worker_service_user with login password 'worker_service_user';
grant usage on schema queues to worker_service_user;
grant usage on schema internal to worker_service_user;

-- domain for all supported task types
create domain queues.task_type as text
    check (value in ('db_function', 'email', 'sms'));

-- queues.task: unit of work with payload and scheduling
create table queues.task (
    task_id bigserial primary key,
    task_type queues.task_type not null,
    payload jsonb not null,
    enqueued_at timestamp with time zone not null default now(),
    scheduled_at timestamp with time zone not null default now(),
    dequeued_at timestamp with time zone
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

-- dequeue and claim the next available task (sets dequeued_at)
create or replace function queues.dequeue_next_available_task()
returns queues.task
language plpgsql
security definer
as $$
declare
    _claimed_task queues.task;
begin
    with candidate as (
        select t.task_id
        from queues.task t
        where t.dequeued_at is null
          and t.scheduled_at <= now()
        order by t.scheduled_at asc, t.task_id asc
        limit 1
        for update skip locked
    )
    update queues.task t
    set dequeued_at = now()
    from candidate c
    where t.task_id = c.task_id
    returning t.*
    into _claimed_task;

    return _claimed_task;
end;
$$;

-- helper to append an error row
create or replace function queues.append_error(
    task_id bigint,
    error_message text
)
returns jsonb
language plpgsql
security definer
as $$
begin
    insert into queues.error (task_id, error_message)
    values (task_id, coalesce(error_message, ''));

    return jsonb_build_object(
        'success', true
    );
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
grant execute on function internal.run_function(text, jsonb) to worker_service_user;
grant execute on function queues.append_error(bigint, text) to worker_service_user;

commit;

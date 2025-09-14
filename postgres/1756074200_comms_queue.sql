begin;

-- send email process: tasks and facts (append-only)
create table comms.send_email_task (
    send_email_task_id bigserial primary key,
    message_id bigint not null references comms.message(message_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- success facts (one per logical task)
create table comms.send_email_task_succeeded (
    send_email_task_id bigint primary key references comms.send_email_task(send_email_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- failure facts (append-only, one per failed attempt)
create table comms.send_email_task_failed (
    send_email_task_id bigint primary key references comms.send_email_task(send_email_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- send sms process: tasks and facts (append-only)
create table comms.send_sms_task (
    send_sms_task_id bigserial primary key,
    message_id bigint not null references comms.message(message_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- success facts (one per logical task)
create table comms.send_sms_task_succeeded (
    send_sms_task_id bigint primary key references comms.send_sms_task(send_sms_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- failure facts (append-only, one per failed attempt)
create table comms.send_sms_task_failed (
    send_sms_task_id bigint primary key references comms.send_sms_task(send_sms_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- supervisor: orchestrates email sending using append-only facts
create or replace function comms.send_email_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := (_payload->>'send_email_task_id')::bigint;
    _has_success boolean;
    _has_failed boolean;
    _num_enqueued_email_tasks integer;
    _next_check_at timestamptz := null;
begin
    -- terminal if already succeeded
    select exists (
        select 1
        from comms.send_email_task_succeeded s
        where s.send_email_task_id = _send_email_task_id
    ) into _has_success;
    if _has_success then
        return '{}'::jsonb;
    end if;

    select exists (
        select 1 from comms.send_email_task_failed f
        where f.send_email_task_id = _send_email_task_id
    ) into _has_failed;

    select count(*)
    into _num_enqueued_email_tasks
    from queues.task t
    where t.task_type = 'email'
      and (t.payload->>'send_email_task_id')::bigint = _send_email_task_id;

    if _num_enqueued_email_tasks = 0 then
        perform queues.enqueue(
            'email',
            jsonb_build_object(
                'task_type', 'email',
                'send_email_task_id', _send_email_task_id,
                'before_handler', 'comms.get_email_payload',
                'success_handler', 'comms.record_email_success',
                'error_handler', 'comms.record_email_failure'
            ),
            now()
        );
        _next_check_at := now() + interval '5 seconds';
    elsif _has_failed and _num_enqueued_email_tasks = 1 then
        perform queues.enqueue(
            'email',
            jsonb_build_object(
                'task_type', 'email',
                'send_email_task_id', _send_email_task_id,
                'before_handler', 'comms.get_email_payload',
                'success_handler', 'comms.record_email_success',
                'error_handler', 'comms.record_email_failure'
            ),
            now()
        );
        _next_check_at := now() + interval '10 seconds';
    end if;

    if not _has_success and _next_check_at is not null then
        perform queues.enqueue(
            'db_function',
            jsonb_build_object(
                'task_type', 'db_function',
                'db_function', 'comms.send_email_supervisor',
                'send_email_task_id', _send_email_task_id
            ),
            _next_check_at
        );
    end if;

    return '{}'::jsonb;
end;
$$;


-- kickoff: create send_email_task and enqueue supervisor
create or replace function comms.kickoff_send_email_task(
    _message_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint;
    _result jsonb;
begin
    insert into comms.send_email_task (message_id)
    values (_message_id)
    returning send_email_task_id
    into _send_email_task_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'comms.send_email_supervisor',
            'send_email_task_id', _send_email_task_id
        ),
        now()
    );

    _result := jsonb_build_object('send_email_task_id', _send_email_task_id);
    return _result;
end;
$$;

-- before handler: build provider payload from send_email_task_id in payload
create or replace function comms.get_email_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _send_email_task_id bigint := (_payload->>'send_email_task_id')::bigint;
    _message_id bigint;
    _result jsonb;
begin
    select set.message_id
    into _message_id
    from comms.send_email_task set
    where set.send_email_task_id = _send_email_task_id;

    if _message_id is null then
        return '{}'::jsonb;
    end if;

    select comms.get_email_payload(_message_id)
    into _result;
    return coalesce(_result, '{}'::jsonb);
end;
$$;

-- success handler: record success fact
create or replace function comms.record_email_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := coalesce((
        _payload->'original_payload'->>'send_email_task_id'
    )::bigint, (
        _payload->>'send_email_task_id'
    )::bigint);
begin
    insert into comms.send_email_task_succeeded (send_email_task_id)
    values (_send_email_task_id)
    on conflict (send_email_task_id) do nothing;
    return '{}'::jsonb;
end;
$$;

-- error handler: record failure fact
create or replace function comms.record_email_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := coalesce((
        _payload->'original_payload'->>'send_email_task_id'
    )::bigint, (
        _payload->>'send_email_task_id'
    )::bigint);
begin
    insert into comms.send_email_task_failed (send_email_task_id)
    values (_send_email_task_id)
    on conflict (send_email_task_id) do nothing;
    return '{}'::jsonb;
end;
$$;

-- per-function grants to worker_service_user (security definer functions)
grant execute on function comms.kickoff_send_email_task(bigint) to worker_service_user;
grant execute on function comms.get_email_payload(jsonb) to worker_service_user;
grant execute on function comms.record_email_success(jsonb) to worker_service_user;
grant execute on function comms.record_email_failure(jsonb) to worker_service_user;
grant execute on function comms.send_email_supervisor(jsonb) to worker_service_user;

commit;



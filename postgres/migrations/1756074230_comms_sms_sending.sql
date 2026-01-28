-- send sms process: task and attempts (append-only)
create table comms.send_sms_task (
    send_sms_task_id bigserial primary key,
    message_id bigint not null references comms.message(message_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempts (append-only, one per scheduled attempt)
create table comms.send_sms_attempt (
    send_sms_attempt_id bigserial primary key,
    send_sms_task_id bigint not null references comms.send_sms_task(send_sms_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt succeeded (one per attempt at most)
create table comms.send_sms_attempt_succeeded (
    send_sms_attempt_id bigint primary key references comms.send_sms_attempt(send_sms_attempt_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt failed (one per attempt at most)
create table comms.send_sms_attempt_failed (
    send_sms_attempt_id bigint primary key references comms.send_sms_attempt(send_sms_attempt_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- facts: has a succeeded attempt for send_sms_task?
create or replace function comms.has_send_sms_succeeded_attempt(
    _send_sms_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from comms.send_sms_attempt a
        join comms.send_sms_attempt_succeeded s on s.send_sms_attempt_id = a.send_sms_attempt_id
        where a.send_sms_task_id = _send_sms_task_id
    );
$$;

-- facts: count failed attempts for send_sms_task
create or replace function comms.count_send_sms_failed_attempts(
    _send_sms_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_sms_attempt a
    join comms.send_sms_attempt_failed f on f.send_sms_attempt_id = a.send_sms_attempt_id
    where a.send_sms_task_id = _send_sms_task_id;
$$;

-- facts: count attempts for send_sms_task
create or replace function comms.count_send_sms_attempts(
    _send_sms_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_sms_attempt a
    where a.send_sms_task_id = _send_sms_task_id;
$$;

-- facts: aggregated facts for send_sms_supervisor
create or replace function comms.send_sms_supervisor_facts(
    _send_sms_task_id bigint,
    out has_success boolean,
    out num_failures integer,
    out num_attempts integer
)
language sql
stable
as $$
    select
        comms.has_send_sms_succeeded_attempt(_send_sms_task_id),
        comms.count_send_sms_failed_attempts(_send_sms_task_id),
        comms.count_send_sms_attempts(_send_sms_task_id);
$$;

-- facts: get sms payload facts from attempt_id
create or replace function comms.get_sms_payload_facts(
    _send_sms_attempt_id bigint,
    out message_id bigint,
    out to_number text,
    out body text
)
language sql
stable
as $$
    select
        sm.message_id,
        sm.to_number,
        sm.body
    from comms.send_sms_attempt a
    join comms.send_sms_task t on t.send_sms_task_id = a.send_sms_task_id
    join comms.sms_message sm on sm.message_id = t.message_id
    where a.send_sms_attempt_id = _send_sms_attempt_id;
$$;

-- before handler: build provider payload from send_sms_attempt_id in payload
create or replace function comms.get_sms_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _send_sms_attempt_id bigint := (_payload->>'send_sms_attempt_id')::bigint;
    _facts record;
begin
    if _send_sms_attempt_id is null then
        return jsonb_build_object('status', 'missing_send_sms_attempt_id');
    end if;

    _facts := comms.get_sms_payload_facts(_send_sms_attempt_id);

    if _facts.message_id is null then
        return jsonb_build_object('status', 'attempt_not_found');
    end if;

    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'message_id', _facts.message_id,
            'to_number', _facts.to_number,
            'body', _facts.body
        )
    );
end;
$$;

-- success handler: record success fact
-- receives: { original_payload: { send_sms_attempt_id, ... }, worker_payload: { ... } }
create or replace function comms.record_sms_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_sms_attempt_id bigint := (_payload->'original_payload'->>'send_sms_attempt_id')::bigint;
begin
    if _send_sms_attempt_id is null then
        return jsonb_build_object('status', 'missing_send_sms_attempt_id');
    end if;

    insert into comms.send_sms_attempt_succeeded (send_sms_attempt_id)
    values (_send_sms_attempt_id)
    on conflict (send_sms_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- error handler: record failure fact
-- receives: { original_payload: { send_sms_attempt_id, ... }, error: "..." }
create or replace function comms.record_sms_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_sms_attempt_id bigint := (_payload->'original_payload'->>'send_sms_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _send_sms_attempt_id is null then
        return jsonb_build_object('status', 'missing_send_sms_attempt_id');
    end if;

    insert into comms.send_sms_attempt_failed (send_sms_attempt_id, error_message)
    values (_send_sms_attempt_id, _error_message)
    on conflict (send_sms_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- effect: schedule an sms send attempt
create or replace function comms.schedule_sms_attempt(
    _send_sms_task_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _send_sms_attempt_id bigint;
begin
    insert into comms.send_sms_attempt (send_sms_task_id)
    values (_send_sms_task_id)
    returning send_sms_attempt_id into _send_sms_attempt_id;

    perform queues.enqueue(
        'sms',
        jsonb_build_object(
            'task_type', 'sms',
            'send_sms_attempt_id', _send_sms_attempt_id,
            'before_handler', 'comms.get_sms_payload',
            'success_handler', 'comms.record_sms_success',
            'error_handler', 'comms.record_sms_failure'
        ),
        now()
    );
end;
$$;

-- effect: schedule sms supervisor recheck with exponential backoff
create or replace function comms.schedule_sms_supervisor_recheck(
    _send_sms_task_id bigint,
    _num_failures integer,
    _run_count integer
)
returns void
language plpgsql
security definer
as $$
declare
    _base_delay_seconds integer := 5;
    _next_check_at timestamptz;
begin
    _next_check_at := now() + (
        _base_delay_seconds * power(2, _num_failures)
    ) * interval '1 second';

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'comms.send_sms_supervisor',
            'send_sms_task_id', _send_sms_task_id,
            'run_count', _run_count + 1
        ),
        _next_check_at
    );
end;
$$;

-- supervisor: orchestrates sms sending using append-only facts
create or replace function comms.send_sms_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_sms_task_id bigint := (_payload->>'send_sms_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _max_runs integer := 20;
    _max_attempts integer := 2;
    _facts record;
begin
    -- 1. VALIDATION
    if _send_sms_task_id is null then
        return jsonb_build_object('status', 'missing_send_sms_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'send_sms_supervisor exceeded max runs'
            using detail = 'Possible infinite loop detected',
                  hint = format('task_id=%s, run_count=%s', _send_sms_task_id, _run_count);
    end if;

    -- 2. LOCK (before facts)
    perform 1
    from comms.send_sms_task t
    where t.send_sms_task_id = _send_sms_task_id
    for update;

    -- 3. FACTS
    _facts := comms.send_sms_supervisor_facts(_send_sms_task_id);

    -- 4. LOGIC + EFFECTS
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    if _facts.num_attempts = _facts.num_failures then
        perform comms.schedule_sms_attempt(_send_sms_task_id);
    end if;

    perform comms.schedule_sms_supervisor_recheck(
        _send_sms_task_id,
        _facts.num_failures,
        _run_count
    );

    return jsonb_build_object('status', 'scheduled');
end;
$$;

create or replace function comms.kickoff_send_sms_task(
    _message_id bigint,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
declare
    _send_sms_task_id bigint;
begin
    -- validation
    if _message_id is null then
        validation_failure_message := 'missing_message_id';
        return;
    end if;

    if not comms.message_exists(_message_id) then
        validation_failure_message := 'message_not_found';
        return;
    end if;

    -- output
    insert into comms.send_sms_task (message_id)
    values (_message_id)
    returning send_sms_task_id
    into _send_sms_task_id;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'comms.send_sms_supervisor',
            'send_sms_task_id', _send_sms_task_id
        ),
        _scheduled_at
    );

    return;
end;
$$;

create or replace function comms.create_and_kickoff_sms_task(
    _to_number text,
    _body text,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
 declare
    _create_sms_message_result record;
    _kickoff_sms_validation_failure_message text;
begin
    -- validation
    if _to_number is null then
        validation_failure_message := 'to_number_missing';
        return;
    end if;
    if _body is null then
        validation_failure_message := 'body_missing';
        return;
    end if;

    select (comms.create_sms_message(_to_number, _body)).*
    into strict _create_sms_message_result;

    if _create_sms_message_result.validation_failure_message is not null then
        validation_failure_message := _create_sms_message_result.validation_failure_message;
        return;
    end if;

    select comms.kickoff_send_sms_task(_create_sms_message_result.created_message_id, _scheduled_at)
    into strict _kickoff_sms_validation_failure_message;

    if _kickoff_sms_validation_failure_message is not null then
        validation_failure_message := _kickoff_sms_validation_failure_message;
        return;
    end if;

    return;
end;
$$;

-- per-function grants to worker_service_user (sms)
grant execute on function comms.kickoff_send_sms_task(bigint, timestamp with time zone) to worker_service_user;
grant execute on function comms.get_sms_payload(jsonb) to worker_service_user;
grant execute on function comms.record_sms_success(jsonb) to worker_service_user;
grant execute on function comms.record_sms_failure(jsonb) to worker_service_user;
grant execute on function comms.schedule_sms_attempt(bigint) to worker_service_user;
grant execute on function comms.schedule_sms_supervisor_recheck(bigint, integer, integer) to worker_service_user;
grant execute on function comms.send_sms_supervisor(jsonb) to worker_service_user;

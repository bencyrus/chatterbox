-- comms schema
create schema comms;
grant usage on schema comms to worker_service_user;

create or replace function comms.from_email_address(
    _key text
)
returns text
stable
language sql
as $$
    select (internal.get_config('from_emails') ->> _key)::text;
$$;

-- domain for communication channel kinds
create domain comms.channel as text
    check (value in ('email', 'sms'));

-- base message table
create table comms.message (
    message_id bigserial primary key,
    channel comms.channel not null,
    created_at timestamp with time zone not null default now()
);

-- email payload table
create table comms.email_message (
    message_id bigint primary key references comms.message(message_id) on delete cascade,
    from_address text not null,
    to_address text not null,
    subject text not null,
    html text not null
);

-- sms payload table
create table comms.sms_message (
    message_id bigint primary key references comms.message(message_id) on delete cascade,
    to_number text not null,
    body text not null
);

-- email templates
create table comms.email_template (
    email_template_id bigserial primary key,
    template_key text not null,
    subject text not null,
    body text not null,
    body_params text[],
    description text,
    created_at timestamp with time zone not null default now(),
    constraint email_template_unique_key unique (template_key)
);

-- sms templates
create table comms.sms_template (
    sms_template_id bigserial primary key,
    template_key text not null,
    body text not null,
    body_params text[],
    description text,
    created_at timestamp with time zone not null default now(),
    constraint sms_template_unique_key unique (template_key)
);

-- Generate message body from template by applying ${var} substitution using allowed_keys
create or replace function comms.generate_message_body_from_template(
    _template_text text,
    _params jsonb,
    _allowed_keys text[]
)
returns text
language plpgsql
stable
as $$
declare
    _param_key text;
    _replacement_value text;
    _result_text text := coalesce(_template_text, '');
begin
    if _allowed_keys is null or array_length(_allowed_keys, 1) is null then
        return _result_text;
    end if;

    foreach _param_key in array _allowed_keys loop
        if _params ? _param_key then
            _replacement_value := _params->>_param_key;
            _result_text := regexp_replace(
                _result_text,
                '\$\{' || regexp_replace(_param_key, '([\\.^$|?*+()\[\]{}])', '\\1', 'g') || '\}',
                _replacement_value,
                'g'
            );
        end if;
    end loop;
    return _result_text;
end;
$$;

create or replace function comms.create_email_message(
    _from_address text,
    _to_address text,
    _subject text,
    _html text,
    out validation_failure_message text,
    out created_message_id bigint
)
language plpgsql
security definer
as $$
begin
    if _from_address is null then
        validation_failure_message := 'from_address_missing';
        return;
    end if;
    if _to_address is null then
        validation_failure_message := 'to_address_missing';
        return;
    end if;
    if _subject is null then
        validation_failure_message := 'subject_missing';
        return;
    end if;
    if _html is null then
        validation_failure_message := 'html_missing';
        return;
    end if;

    insert into comms.message (channel)
    values ('email')
    returning message_id
    into created_message_id;
    
    insert into comms.email_message (message_id, from_address, to_address, subject, html)
    values (created_message_id, _from_address, _to_address, _subject, _html);
    return;
end;
$$;

create or replace function comms.create_sms_message(
    _to_number text,
    _body text,
    out validation_failure_message text,
    out created_message_id bigint
)
language plpgsql
security definer
as $$
begin
    if _to_number is null then
        validation_failure_message := 'to_number_missing';
        return;
    end if;
    if _body is null then
        validation_failure_message := 'body_missing';
        return;
    end if;

    insert into comms.message (channel)
    values ('sms')
    returning message_id
    into created_message_id;

    insert into comms.sms_message (message_id, to_number, body)
    values (created_message_id, _to_number, _body);
    return;
end;
$$;

create or replace function comms.message_exists(
    _message_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from comms.message m
        where m.message_id = _message_id
    );
$$;


-- comms queue schemas and functions

-- send email process: task and attempts (append-only)
create table comms.send_email_task (
    send_email_task_id bigserial primary key,
    message_id bigint not null references comms.message(message_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempts (append-only, one per scheduled attempt)
create table comms.send_email_attempt (
    send_email_attempt_id bigserial primary key,
    send_email_task_id bigint not null references comms.send_email_task(send_email_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt succeeded (one per attempt at most)
create table comms.send_email_attempt_succeeded (
    send_email_attempt_id bigint primary key references comms.send_email_attempt(send_email_attempt_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- attempt failed (one per attempt at most)
create table comms.send_email_attempt_failed (
    send_email_attempt_id bigint primary key references comms.send_email_attempt(send_email_attempt_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

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

-- facts: has a succeeded attempt for send_email_task?
create or replace function comms.has_send_email_succeeded_attempt(
    _send_email_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from comms.send_email_attempt a
        join comms.send_email_attempt_succeeded s on s.send_email_attempt_id = a.send_email_attempt_id
        where a.send_email_task_id = _send_email_task_id
    );
$$;

-- facts: count failed attempts for send_email_task
create or replace function comms.count_send_email_failed_attempts(
    _send_email_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_email_attempt a
    join comms.send_email_attempt_failed f on f.send_email_attempt_id = a.send_email_attempt_id
    where a.send_email_task_id = _send_email_task_id;
$$;

-- facts: count attempts for send_email_task
create or replace function comms.count_send_email_attempts(
    _send_email_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_email_attempt a
    where a.send_email_task_id = _send_email_task_id;
$$;

-- facts: aggregated facts for send_email_supervisor
create or replace function comms.send_email_supervisor_facts(
    _send_email_task_id bigint,
    out has_success boolean,
    out num_failures integer,
    out num_attempts integer
)
language sql
stable
as $$
    select
        comms.has_send_email_succeeded_attempt(_send_email_task_id),
        comms.count_send_email_failed_attempts(_send_email_task_id),
        comms.count_send_email_attempts(_send_email_task_id);
$$;

-- facts: get email payload facts from attempt_id
create or replace function comms.get_email_payload_facts(
    _send_email_attempt_id bigint,
    out message_id bigint,
    out from_address text,
    out to_address text,
    out subject text,
    out html text
)
language sql
stable
as $$
    select
        em.message_id,
        em.from_address,
        em.to_address,
        em.subject,
        em.html
    from comms.send_email_attempt a
    join comms.send_email_task t on t.send_email_task_id = a.send_email_task_id
    join comms.email_message em on em.message_id = t.message_id
    where a.send_email_attempt_id = _send_email_attempt_id;
$$;

-- before handler: build provider payload from send_email_attempt_id in payload
create or replace function comms.get_email_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _send_email_attempt_id bigint := (_payload->>'send_email_attempt_id')::bigint;
    _facts record;
begin
    if _send_email_attempt_id is null then
        return jsonb_build_object('status', 'missing_send_email_attempt_id');
    end if;

    _facts := comms.get_email_payload_facts(_send_email_attempt_id);

    if _facts.message_id is null then
        return jsonb_build_object('status', 'email_message_not_found');
    end if;

    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'message_id', _facts.message_id,
            'from_address', _facts.from_address,
            'to_address', _facts.to_address,
            'subject', _facts.subject,
            'html', _facts.html
        )
    );
end;
$$;

-- success handler: record success fact
-- receives: { original_payload: { send_email_attempt_id, ... }, worker_payload: { ... } }
create or replace function comms.record_email_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_attempt_id bigint := (_payload->'original_payload'->>'send_email_attempt_id')::bigint;
begin
    if _send_email_attempt_id is null then
        return jsonb_build_object('status', 'missing_send_email_attempt_id');
    end if;

    insert into comms.send_email_attempt_succeeded (send_email_attempt_id)
    values (_send_email_attempt_id)
    on conflict (send_email_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- error handler: record failure fact
-- receives: { original_payload: { send_email_attempt_id, ... }, error: "..." }
create or replace function comms.record_email_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_attempt_id bigint := (_payload->'original_payload'->>'send_email_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _send_email_attempt_id is null then
        return jsonb_build_object('status', 'missing_send_email_attempt_id');
    end if;

    insert into comms.send_email_attempt_failed (send_email_attempt_id, error_message)
    values (_send_email_attempt_id, _error_message)
    on conflict (send_email_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- effect: schedule an email send attempt
create or replace function comms.schedule_email_attempt(
    _send_email_task_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _send_email_attempt_id bigint;
begin
    insert into comms.send_email_attempt (send_email_task_id)
    values (_send_email_task_id)
    returning send_email_attempt_id into _send_email_attempt_id;

    perform queues.enqueue(
        'email',
        jsonb_build_object(
            'task_type', 'email',
            'send_email_attempt_id', _send_email_attempt_id,
            'before_handler', 'comms.get_email_payload',
            'success_handler', 'comms.record_email_success',
            'error_handler', 'comms.record_email_failure'
        ),
        now()
    );
end;
$$;

-- effect: schedule supervisor recheck with exponential backoff
create or replace function comms.schedule_email_supervisor_recheck(
    _send_email_task_id bigint,
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
            'db_function', 'comms.send_email_supervisor',
            'send_email_task_id', _send_email_task_id,
            'run_count', _run_count + 1
        ),
        _next_check_at
    );
end;
$$;

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
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _max_runs integer := 20;
    _max_attempts integer := 2;
    _facts record;
begin
    -- 1. VALIDATION
    if _send_email_task_id is null then
        return jsonb_build_object('status', 'missing_send_email_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'send_email_supervisor exceeded max runs'
            using detail = 'Possible infinite loop detected',
                  hint = format('task_id=%s, run_count=%s', _send_email_task_id, _run_count);
    end if;

    -- 2. LOCK (before facts)
    perform 1
    from comms.send_email_task t
    where t.send_email_task_id = _send_email_task_id
    for update;

    -- 3. FACTS
    _facts := comms.send_email_supervisor_facts(_send_email_task_id);

    -- 4. LOGIC + EFFECTS
    if _facts.has_success then
        return jsonb_build_object('status', 'succeeded');
    end if;

    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    if _facts.num_attempts = _facts.num_failures then
        perform comms.schedule_email_attempt(_send_email_task_id);
    end if;

    perform comms.schedule_email_supervisor_recheck(
        _send_email_task_id,
        _facts.num_failures,
        _run_count
    );

    return jsonb_build_object('status', 'scheduled');
end;
$$;

create or replace function comms.kickoff_send_email_task(
    _message_id bigint,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint;
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
        _scheduled_at
    );

    return;
end;
$$;

create or replace function comms.create_and_kickoff_email_task(
    _from_address text,
    _to_address text,
    _subject text,
    _html text,
    _scheduled_at timestamp with time zone default now(),
    out validation_failure_message text
)
returns text
language plpgsql
security definer
as $$
 declare
    _create_email_message_result record;
    _kickoff_validation_failure_message text;
begin
    -- input validation (no exceptions here)
    if _from_address is null then
        validation_failure_message := 'from_address_missing';
        return;
    end if;
    if _to_address is null then
        validation_failure_message := 'to_address_missing';
        return;
    end if;
    if _subject is null then
        validation_failure_message := 'subject_missing';
        return;
    end if;
    if _html is null then
        validation_failure_message := 'html_missing';
        return;
    end if;

    select (comms.create_email_message(_from_address, _to_address, _subject, _html)).*
    into strict _create_email_message_result;

    if _create_email_message_result.validation_failure_message is not null then
        validation_failure_message := _create_email_message_result.validation_failure_message;
        return;
    end if;

    select comms.kickoff_send_email_task(_create_email_message_result.created_message_id, _scheduled_at)
    into strict _kickoff_validation_failure_message;

    if _kickoff_validation_failure_message is not null then
        validation_failure_message := _kickoff_validation_failure_message;
        return;
    end if;

    return;
end;
$$;

-- per-function grants to worker_service_user (security definer functions)
grant execute on function comms.kickoff_send_email_task(bigint, timestamp with time zone) to worker_service_user;
grant execute on function comms.get_email_payload(jsonb) to worker_service_user;
grant execute on function comms.record_email_success(jsonb) to worker_service_user;
grant execute on function comms.record_email_failure(jsonb) to worker_service_user;
grant execute on function comms.schedule_email_attempt(bigint) to worker_service_user;
grant execute on function comms.schedule_email_supervisor_recheck(bigint, integer, integer) to worker_service_user;
grant execute on function comms.send_email_supervisor(jsonb) to worker_service_user;

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

-- seed hello world templates (idempotent)
insert into comms.email_template (
    template_key,
    subject,
    body,
    body_params,
    description
)
values (
    'hello_world_email',
    'Hello, ${name}!',
    'Hello, ${name}! Welcome to Chatterbox.',
    array['name'],
    'Hello world email template'
)
on conflict (template_key) do nothing;

insert into comms.sms_template (
    template_key,
    body,
    body_params,
    description
)
values (
    'hello_world_sms',
    'Hello, ${name}! This is a test SMS from Chatterbox.',
    array['name'],
    'Hello world sms template'
)
on conflict (template_key) do nothing;

-- api.hello_world_email(to_address): builds from template and schedules send
create or replace function api.hello_world_email(
    to_address text
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _from_address text := comms.from_email_address('hello');
    _params jsonb := jsonb_build_object('name', 'World');
    _subject text;
    _body text;
    _create_and_kickoff_email_task_validation_failure_message text;
begin
    -- validate input
    if to_address is null or btrim(to_address) = '' then
        raise exception 'Hello World Email Failed'
            using detail = 'Invalid Request Payload',
                  hint = 'missing_to_address';
    end if;

    -- subject from template
    select comms.generate_message_body_from_template(
        et.subject,
        _params,
        et.body_params
    )
    into _subject
    from comms.email_template et
    where et.template_key = 'hello_world_email';

    -- body from template
    select comms.generate_message_body_from_template(
        et.body,
        _params,
        et.body_params
    )
    into _body
    from comms.email_template et
    where et.template_key = 'hello_world_email';

    if _subject is null or _body is null then
        raise exception 'Hello World Email Failed'
            using detail = 'Template not found',
                  hint = 'template_not_found';
    end if;

    select comms.create_and_kickoff_email_task(
        _from_address,
        to_address,
        _subject,
        _body,
        now()
    )
    into strict _create_and_kickoff_email_task_validation_failure_message;

    if _create_and_kickoff_email_task_validation_failure_message is not null then
        raise exception 'Hello World Email Failed'
            using detail = 'Invalid Request Payload',
                  hint = _create_and_kickoff_email_task_validation_failure_message;
    end if;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- api.hello_world_sms(to_number): builds from template and schedules send
create or replace function api.hello_world_sms(
    to_number text
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _params jsonb := jsonb_build_object('name', 'World');
    _body text;
    _create_and_kickoff_sms_task_validation_failure_message text;
begin
    -- validate input
    if to_number is null or btrim(to_number) = '' then
        raise exception 'Hello World SMS Failed'
            using detail = 'Invalid Request Payload',
                  hint = 'missing_to_number';
    end if;

    -- body from template
    select comms.generate_message_body_from_template(
        st.body,
        _params,
        st.body_params
    )
    into _body
    from comms.sms_template st
    where st.template_key = 'hello_world_sms';

    if _body is null then
        raise exception 'Hello World SMS Failed'
            using detail = 'Template not found',
                  hint = 'template_not_found';
    end if;

    select comms.create_and_kickoff_sms_task(
        to_number,
        _body,
        now()
    )
    into strict _create_and_kickoff_sms_task_validation_failure_message;

    if _create_and_kickoff_sms_task_validation_failure_message is not null then
        raise exception 'Hello World SMS Failed'
            using detail = 'Invalid Request Payload',
                  hint = _create_and_kickoff_sms_task_validation_failure_message;
    end if;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

grant execute on function api.hello_world_email(text) to anon, authenticated;
grant execute on function api.hello_world_sms(text) to anon, authenticated;

-- comms.render_email_template: renders subject and body for a template key
create or replace function comms.render_email_template(
    _template_key text,
    _params jsonb,
    out subject text,
    out body text
)
stable
language sql
as $$
    select
        comms.generate_message_body_from_template(et.subject, _params, et.body_params),
        comms.generate_message_body_from_template(et.body, _params, et.body_params)
    from comms.email_template et
    where et.template_key = _template_key;
$$;

-- comms.render_sms_template: renders body for a template key
create or replace function comms.render_sms_template(
    _template_key text,
    _params jsonb
)
returns text
stable
language sql
as $$
    select
        comms.generate_message_body_from_template(st.body, _params, st.body_params)
    from comms.sms_template st
    where st.template_key = _template_key;
$$;

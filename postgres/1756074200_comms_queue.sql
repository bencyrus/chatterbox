begin;

-- base comms schema and functions

-- comms schema
create schema comms;

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

-- result of creating an email message
create type comms.create_email_message_result as (
    validation_failure_message text,
    message_id bigint
);

-- create an email message with validation
create or replace function comms.create_email_message(
    _from_address text,
    _to_address text,
    _subject text,
    _html text
)
returns comms.create_email_message_result
language plpgsql
security definer
as $$
declare
    _message_id bigint;
begin
    if _from_address is null then
        return ('from_address_missing', null)::comms.create_email_message_result;
    end if;
    if _to_address is null then
        return ('to_address_missing', null)::comms.create_email_message_result;
    end if;
    if _subject is null then
        return ('subject_missing', null)::comms.create_email_message_result;
    end if;
    if _html is null then
        return ('html_missing', null)::comms.create_email_message_result;
    end if;

    insert into comms.message (channel)
    values ('email')
    returning message_id
    into _message_id;
    
    insert into comms.email_message (message_id, from_address, to_address, subject, html)
    values (_message_id, _from_address, _to_address, _subject, _html);
    return (null, _message_id)::comms.create_email_message_result;
end;
$$;

-- result of creating an sms message
create type comms.create_sms_message_result as (
    validation_failure_message text,
    message_id bigint
);

-- create an sms message with validation
create or replace function comms.create_sms_message(
    _to_number text,
    _body text
)
returns comms.create_sms_message_result
language plpgsql
security definer
as $$
declare
    _message_id bigint;
begin
    if _to_number is null then
        return ('to_number_missing', null)::comms.create_sms_message_result;
    end if;
    if _body is null then
        return ('body_missing', null)::comms.create_sms_message_result;
    end if;

    insert into comms.message (channel)
    values ('sms')
    returning message_id
    into _message_id;

    insert into comms.sms_message (message_id, to_number, body)
    values (_message_id, _to_number, _body);
    return (null, _message_id)::comms.create_sms_message_result;
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

-- send email process: tasks and facts (append-only)
create table comms.send_email_task (
    send_email_task_id bigserial primary key,
    message_id bigint not null references comms.message(message_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- scheduled facts (append-only, one per scheduled attempt)
create table comms.send_email_task_scheduled (
    send_email_task_scheduled_id bigserial primary key,
    send_email_task_id bigint not null references comms.send_email_task(send_email_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- success facts (one per logical task)
create table comms.send_email_task_succeeded (
    send_email_task_id bigint primary key references comms.send_email_task(send_email_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- failure facts (append-only, one per failed attempt)
create table comms.send_email_task_failed (
    send_email_task_failed_id bigserial primary key,
    send_email_task_id bigint not null references comms.send_email_task(send_email_task_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- send sms process: tasks and facts (append-only)
create table comms.send_sms_task (
    send_sms_task_id bigserial primary key,
    message_id bigint not null references comms.message(message_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- scheduled facts (append-only, one per scheduled attempt)
create table comms.send_sms_task_scheduled (
    send_sms_task_scheduled_id bigserial primary key,
    send_sms_task_id bigint not null references comms.send_sms_task(send_sms_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- success facts (one per logical task)
create table comms.send_sms_task_succeeded (
    send_sms_task_id bigint primary key references comms.send_sms_task(send_sms_task_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- failure facts (append-only, one per failed attempt)
create table comms.send_sms_task_failed (
    send_sms_task_failed_id bigserial primary key,
    send_sms_task_id bigint not null references comms.send_sms_task(send_sms_task_id) on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- facts: has the send_email_task succeeded?
create or replace function comms.has_send_email_task_succeeded(
    _send_email_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from comms.send_email_task_succeeded s
        where s.send_email_task_id = _send_email_task_id
    );
$$;

-- facts: count failures for send_email_task
create or replace function comms.count_send_email_task_failures(
    _send_email_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_email_task_failed f
    where f.send_email_task_id = _send_email_task_id;
$$;

-- facts: count scheduled attempts for send_email_task
create or replace function comms.count_send_email_task_scheduled(
    _send_email_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_email_task_scheduled s
    where s.send_email_task_id = _send_email_task_id;
$$;

-- before handler: build provider payload from send_email_task_id in payload
create or replace function comms.get_email_payload(
    payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _send_email_task_id bigint := (payload->>'send_email_task_id')::bigint;
    _message_id bigint;
    _result jsonb;
begin
    -- validation
    if _send_email_task_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_send_email_task_id'
        );
    end if;

    -- facts
    select set.message_id
    into _message_id
    from comms.send_email_task set
    where set.send_email_task_id = _send_email_task_id;

    if _message_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'task_not_found'
        );
    end if;

    -- compute
    select to_jsonb(email_payload)
    into _result
    from (
        select 
            em.message_id,
            em.from_address,
            em.to_address,
            em.subject,
            em.html
        from comms.email_message em
        where em.message_id = _message_id
    ) email_payload;

    -- output
    if _result is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'payload_not_found'
        );
    end if;

    return jsonb_build_object(
        'success', true,
        'payload', _result
    );
end;
$$;

-- success handler: record success fact
create or replace function comms.record_email_success(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := coalesce((
        payload->'original_payload'->>'send_email_task_id'
    )::bigint, (
        payload->>'send_email_task_id'
    )::bigint);
begin
    -- validation
    if _send_email_task_id is null then
        return jsonb_build_object(
            'error', 'missing_send_email_task_id'
        );
    end if;

    -- output
    insert into comms.send_email_task_succeeded (send_email_task_id)
    values (_send_email_task_id)
    on conflict (send_email_task_id) do nothing;

    return jsonb_build_object(
        'success', true
    );
end;
$$;

-- error handler: record failure fact
create or replace function comms.record_email_failure(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := coalesce((
        payload->'original_payload'->>'send_email_task_id'
    )::bigint, (
        payload->>'send_email_task_id'
    )::bigint);
    _error_message text := (payload->>'error')::text;
begin
    -- validation
    if _send_email_task_id is null then
        return jsonb_build_object(
            'error', 'missing_send_email_task_id'
        );
    end if;

    -- output
    insert into comms.send_email_task_failed (send_email_task_id, error_message)
    values (_send_email_task_id, _error_message);

    return jsonb_build_object(
        'success', true
    );
end;
$$;

-- supervisor: orchestrates email sending using append-only facts
-- Supervisor behavior:
-- - Locks the root task to serialize concurrent runs
-- - Terminates early if succeeded or attempts exhausted
-- - If no attempt is outstanding (scheduled <= failures), records a scheduled fact and enqueues the channel task
-- - Always re-enqueues itself once per run at computed backoff
create or replace function comms.send_email_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint := (payload->>'send_email_task_id')::bigint;
    _has_success boolean;
    _num_failures integer;
    _num_scheduled integer;
    _max_attempts integer := 2; -- one retry (1 failure + 1 final attempt)
    _base_delay_seconds integer := 5;
    _next_check_at timestamptz;
begin
    -- validation
    if _send_email_task_id is null then
        return jsonb_build_object(
            'error', 'missing_send_email_task_id'
        );
    end if;

    -- lock root task to avoid duplicate scheduling under concurrency
    perform 1
    from comms.send_email_task t
    where t.send_email_task_id = _send_email_task_id
    for update;

    select comms.has_send_email_task_succeeded(_send_email_task_id)
    into _has_success;
    
    if _has_success then
        return jsonb_build_object(
            'success', true
        );
    end if;

    select comms.count_send_email_task_failures(_send_email_task_id)
    into _num_failures;

    if _num_failures >= _max_attempts then
        return jsonb_build_object(
            'success', true
        );
    end if;

    select comms.count_send_email_task_scheduled(_send_email_task_id)
    into _num_scheduled;

    -- compute
    -- next check at exponential backoff based on failures
    _next_check_at := (
        now() +
        ((_base_delay_seconds)::double precision * power(2, _num_failures)) *
        interval '1 second'
    );

    -- schedule a new attempt only if there is no outstanding scheduled attempt
    if _num_scheduled <= _num_failures then
        insert into comms.send_email_task_scheduled (send_email_task_id)
        values (_send_email_task_id);

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
    end if;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'comms.send_email_supervisor',
            'send_email_task_id', _send_email_task_id
        ),
        _next_check_at
    );

    return jsonb_build_object(
        'success', true
    );
end;
$$;

create type comms.kickoff_send_email_task_result as (
    validation_failure_message text
);

-- kickoff: create send_email_task and enqueue supervisor
create or replace function comms.kickoff_send_email_task(
    _message_id bigint,
    _scheduled_at timestamp with time zone default now()
)
returns comms.kickoff_send_email_task_result
language plpgsql
security definer
as $$
declare
    _send_email_task_id bigint;
begin
    -- validation
    if _message_id is null then
        return ('missing_message_id')::comms.kickoff_send_email_task_result;
    end if;

    if not comms.message_exists(_message_id) then
        return ('message_not_found')::comms.kickoff_send_email_task_result;
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

    return (null)::comms.kickoff_send_email_task_result;
end;
$$;

-- result of creating and kicking off an email task
create type comms.create_and_kickoff_email_task_result as (
    validation_failure_message text
);

-- create email message and kickoff send_email_task
create or replace function comms.create_and_kickoff_email_task(
    _from_address text,
    _to_address text,
    _subject text,
    _html text,
    _scheduled_at timestamp with time zone default now()
)
returns comms.create_and_kickoff_email_task_result
language plpgsql
security definer
as $$
declare
    _create_email_result comms.create_email_message_result;
    _kickoff_result comms.kickoff_send_email_task_result;
begin
    select comms.create_email_message(_from_address, _to_address, _subject, _html)
    into _create_email_result;

    if _create_email_result.validation_failure_message is not null then
        return (_create_email_result.validation_failure_message)::comms.create_and_kickoff_email_task_result;
    end if;

    select comms.kickoff_send_email_task(_create_email_result.message_id, _scheduled_at)
    into _kickoff_result;

    if _kickoff_result.validation_failure_message is not null then
        return (_kickoff_result.validation_failure_message)::comms.create_and_kickoff_email_task_result;
    end if;

    return (null)::comms.create_and_kickoff_email_task_result;
end;
$$;

-- per-function grants to worker_service_user (security definer functions)
grant execute on function comms.kickoff_send_email_task(bigint, timestamp with time zone) to worker_service_user;
grant execute on function comms.get_email_payload(jsonb) to worker_service_user;
grant execute on function comms.record_email_success(jsonb) to worker_service_user;
grant execute on function comms.record_email_failure(jsonb) to worker_service_user;
grant execute on function comms.send_email_supervisor(jsonb) to worker_service_user;

-- facts: has the send_sms_task succeeded?
create or replace function comms.has_send_sms_task_succeeded(
    _send_sms_task_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from comms.send_sms_task_succeeded s
        where s.send_sms_task_id = _send_sms_task_id
    );
$$;

-- facts: count failures for send_sms_task
create or replace function comms.count_send_sms_task_failures(
    _send_sms_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_sms_task_failed f
    where f.send_sms_task_id = _send_sms_task_id;
$$;

-- facts: count scheduled attempts for send_sms_task
create or replace function comms.count_send_sms_task_scheduled(
    _send_sms_task_id bigint
)
returns integer
language sql
stable
as $$
    select count(*)::integer
    from comms.send_sms_task_scheduled s
    where s.send_sms_task_id = _send_sms_task_id;
$$;

-- before handler: build provider payload from send_sms_task_id in payload
create or replace function comms.get_sms_payload(
    payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _send_sms_task_id bigint := (payload->>'send_sms_task_id')::bigint;
    _message_id bigint;
    _result jsonb;
begin
    -- validation
    if _send_sms_task_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'missing_send_sms_task_id'
        );
    end if;

    -- facts
    select sst.message_id
    into _message_id
    from comms.send_sms_task sst
    where sst.send_sms_task_id = _send_sms_task_id;

    if _message_id is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'task_not_found'
        );
    end if;

    -- compute
    select to_jsonb(sms_payload)
    into _result
    from (
        select 
            sm.message_id,
            sm.to_number,
            sm.body
        from comms.sms_message sm
        where sm.message_id = _message_id
    ) sms_payload;

    -- output
    if _result is null then
        return jsonb_build_object(
            'success', false,
            'validation_failure_message', 'payload_not_found'
        );
    end if;

    return jsonb_build_object(
        'success', true,
        'payload', _result
    );
end;
$$;

-- success handler: record success fact
create or replace function comms.record_sms_success(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_sms_task_id bigint := coalesce((
        payload->'original_payload'->>'send_sms_task_id'
    )::bigint, (
        payload->>'send_sms_task_id'
    )::bigint);
begin
    -- validation
    if _send_sms_task_id is null then
        return jsonb_build_object(
            'error', 'missing_send_sms_task_id'
        );
    end if;

    -- output
    insert into comms.send_sms_task_succeeded (send_sms_task_id)
    values (_send_sms_task_id)
    on conflict (send_sms_task_id) do nothing;

    return jsonb_build_object(
        'success', true
    );
end;
$$;

-- error handler: record failure fact
create or replace function comms.record_sms_failure(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_sms_task_id bigint := coalesce((
        payload->'original_payload'->>'send_sms_task_id'
    )::bigint, (
        payload->>'send_sms_task_id'
    )::bigint);
    _error_message text := (payload->>'error')::text;
begin
    -- validation
    if _send_sms_task_id is null then
        return jsonb_build_object(
            'error', 'missing_send_sms_task_id'
        );
    end if;

    -- output
    insert into comms.send_sms_task_failed (send_sms_task_id, error_message)
    values (_send_sms_task_id, _error_message);

    return jsonb_build_object(
        'success', true
    );
end;
$$;

-- supervisor: orchestrates sms sending using append-only facts
-- Supervisor behavior:
-- - Locks the root task to serialize concurrent runs
-- - Terminates early if succeeded or attempts exhausted
-- - If no attempt is outstanding (scheduled <= failures), records a scheduled fact and enqueues the channel task
-- - Always re-enqueues itself once per run at computed backoff
create or replace function comms.send_sms_supervisor(
    payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _send_sms_task_id bigint := (payload->>'send_sms_task_id')::bigint;
    _has_success boolean;
    _num_failures integer;
    _num_scheduled integer;
    _max_attempts integer := 2; -- one retry (1 failure + 1 final attempt)
    _base_delay_seconds integer := 5;
    _next_check_at timestamptz;
begin
    -- validation
    if _send_sms_task_id is null then
        return jsonb_build_object(
            'error', 'missing_send_sms_task_id'
        );
    end if;

    -- lock root task to avoid duplicate scheduling under concurrency
    perform 1
    from comms.send_sms_task t
    where t.send_sms_task_id = _send_sms_task_id
    for update;

    select comms.has_send_sms_task_succeeded(_send_sms_task_id)
    into _has_success;
    
    if _has_success then
        return jsonb_build_object(
            'success', true
        );
    end if;

    select comms.count_send_sms_task_failures(_send_sms_task_id)
    into _num_failures;

    if _num_failures >= _max_attempts then
        return jsonb_build_object(
            'success', true
        );
    end if;

    select comms.count_send_sms_task_scheduled(_send_sms_task_id)
    into _num_scheduled;

    -- compute
    -- next check at exponential backoff based on failures
    _next_check_at := (
        now() +
        ((_base_delay_seconds)::double precision * power(2, _num_failures)) *
        interval '1 second'
    );

    -- schedule a new attempt only if there is no outstanding scheduled attempt
    if _num_scheduled <= _num_failures then
        insert into comms.send_sms_task_scheduled (send_sms_task_id)
        values (_send_sms_task_id);

        perform queues.enqueue(
            'sms',
            jsonb_build_object(
                'task_type', 'sms',
                'send_sms_task_id', _send_sms_task_id,
                'before_handler', 'comms.get_sms_payload',
                'success_handler', 'comms.record_sms_success',
                'error_handler', 'comms.record_sms_failure'
            ),
            now()
        );
    end if;

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'comms.send_sms_supervisor',
            'send_sms_task_id', _send_sms_task_id
        ),
        _next_check_at
    );

    return jsonb_build_object(
        'success', true
    );
end;
$$;

create type comms.kickoff_send_sms_task_result as (
    validation_failure_message text
);

-- kickoff: create send_sms_task and enqueue supervisor
create or replace function comms.kickoff_send_sms_task(
    _message_id bigint,
    _scheduled_at timestamp with time zone default now()
)
returns comms.kickoff_send_sms_task_result
language plpgsql
security definer
as $$
declare
    _send_sms_task_id bigint;
begin
    -- validation
    if _message_id is null then
        return ('missing_message_id')::comms.kickoff_send_sms_task_result;
    end if;

    if not comms.message_exists(_message_id) then
        return ('message_not_found')::comms.kickoff_send_sms_task_result;
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

    return (null)::comms.kickoff_send_sms_task_result;
end;
$$;

-- result of creating and kicking off an sms task
create type comms.create_and_kickoff_sms_task_result as (
    validation_failure_message text
);

-- create sms message and kickoff send_sms_task
create or replace function comms.create_and_kickoff_sms_task(
    _to_number text,
    _body text,
    _scheduled_at timestamp with time zone default now()
)
returns comms.create_and_kickoff_sms_task_result
language plpgsql
security definer
as $$
declare
    _create_sms_result comms.create_sms_message_result;
    _kickoff_result comms.kickoff_send_sms_task_result;
begin
    select comms.create_sms_message(_to_number, _body)
    into _create_sms_result;

    if _create_sms_result.validation_failure_message is not null then
        return (_create_sms_result.validation_failure_message)::comms.create_and_kickoff_sms_task_result;
    end if;

    select comms.kickoff_send_sms_task(_create_sms_result.message_id, _scheduled_at)
    into _kickoff_result;

    if _kickoff_result.validation_failure_message is not null then
        return (_kickoff_result.validation_failure_message)::comms.create_and_kickoff_sms_task_result;
    end if;

    return (null)::comms.create_and_kickoff_sms_task_result;
end;
$$;

-- per-function grants to worker_service_user (sms)
grant execute on function comms.kickoff_send_sms_task(bigint, timestamp with time zone) to worker_service_user;
grant execute on function comms.get_sms_payload(jsonb) to worker_service_user;
grant execute on function comms.record_sms_success(jsonb) to worker_service_user;
grant execute on function comms.record_sms_failure(jsonb) to worker_service_user;
grant execute on function comms.send_sms_supervisor(jsonb) to worker_service_user;

commit;



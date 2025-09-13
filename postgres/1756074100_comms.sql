begin;

-- domain and comms schema
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

-- Apply ${var} substitution using only keys declared by the template (allowed_keys)
create or replace function comms.apply_template_params(
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

-- email payload builder
create or replace function comms.get_email_payload(
    _message_id bigint
)
returns jsonb
language sql
stable
as $$
    select to_jsonb(payload)
    from (
        select 
            em.message_id,
            em.from_address,
            em.to_address,
            em.subject,
            em.html
        from comms.email_message em
        where em.message_id = _message_id
    ) payload;
$$;

-- sms payload builder
create or replace function comms.get_sms_payload(
    _message_id bigint
)
returns jsonb
language sql
stable
as $$
    select to_jsonb(payload)
    from (
        select 
            sm.message_id,
            sm.to_number,
            sm.body
        from comms.sms_message sm
        where sm.message_id = _message_id
    ) payload;
$$;

-- generic result for internal enqueue helpers
create type comms.enqueue_job_result as (
    validation_failure_message text,
    job queues.job
);

-- create email message and enqueue job
create or replace function comms.create_and_enqueue_email(
    _from_address text,
    _to_address text,
    _subject text,
    _html text,
    _priority integer default 1,
    _num_max_attempts integer default 5,
    _scheduled_at timestamp with time zone default now()
)
returns comms.enqueue_job_result
language plpgsql
security definer
as $$
declare
    _message_id bigint;
    _created_job queues.job;
    _create_email_result comms.create_email_message_result;
begin
    select comms.create_email_message(_from_address, _to_address, _subject, _html)
    into _create_email_result;
    if _create_email_result.validation_failure_message is not null then
        return (_create_email_result.validation_failure_message, null)::comms.enqueue_job_result;
    end if;

    _message_id := _create_email_result.message_id;
    select queues.enqueue('email', _message_id, _priority, _num_max_attempts, _scheduled_at)
    into _created_job;
    return (null, _created_job)::comms.enqueue_job_result;
end;
$$;

-- create sms message and enqueue job
create or replace function comms.create_and_enqueue_sms(
    _to_number text,
    _body text,
    _priority integer default 1,
    _num_max_attempts integer default 5,
    _scheduled_at timestamp with time zone default now()
)
returns comms.enqueue_job_result
language plpgsql
security definer
as $$
declare
    _message_id bigint;
    _created_job queues.job;
    _create_sms_result comms.create_sms_message_result;
begin
    select comms.create_sms_message(_to_number, _body)
    into _create_sms_result;
    if _create_sms_result.validation_failure_message is not null then
        return (_create_sms_result.validation_failure_message, null)::comms.enqueue_job_result;
    end if;

    _message_id := _create_sms_result.message_id;
    select queues.enqueue('sms', _message_id, _priority, _num_max_attempts, _scheduled_at)
    into _created_job;
    return (null, _created_job)::comms.enqueue_job_result;
end;
$$;

-- service fetch_next_task response type
create type service_api.fetch_next_task_response as (
    job jsonb
);

-- lease next ready job and return job with payload
create or replace function service_api.fetch_next_task(
    worker_id text,
    lease_seconds integer default 60,
    task_type queues.task_type default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _next_ready_job queues.lease_next_ready_job_result;
    _dequeued_job queues.dequeued_job;
    _payload_json jsonb := '{}'::jsonb;
    _response_json service_api.fetch_next_task_response;
begin
    select queues.lease_next_ready_job(worker_id, lease_seconds, task_type)
    into _next_ready_job;
    if _next_ready_job.validation_failure_message is not null then
        raise exception 'Fetch Next Task Failed'
            using detail = 'Invalid Request',
                  hint = _next_ready_job.validation_failure_message;
    end if;
    
    _dequeued_job := _next_ready_job.job;
    if _dequeued_job.job_id is null then
        _response_json := (null);
        return to_jsonb(_response_json);
    end if;

    if _dequeued_job.task_type = 'email' then
        _payload_json := jsonb_build_object('payload', comms.get_email_payload(_dequeued_job.resource_id));
    elsif _dequeued_job.task_type = 'sms' then
        _payload_json := jsonb_build_object('payload', comms.get_sms_payload(_dequeued_job.resource_id));
    end if;

    _response_json := (
        to_jsonb(_dequeued_job) || _payload_json
    );
    return to_jsonb(_response_json);
end;
$$;

commit;

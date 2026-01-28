-- hello world email and sms API endpoints
-- demonstrates the comms system with simple test templates

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

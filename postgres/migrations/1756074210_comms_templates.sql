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

begin;

-- internal: get or create a otp code for an account
-- returns the existing code if it is unused and has at least 30 seconds remaining; otherwise creates a new one
create or replace function auth.get_or_create_otp_code(
    _account_id bigint,
    out validation_failure_message text,
    out otp_code_id bigint,
    out code text,
    out expires_at timestamp with time zone,
    out seconds_remaining integer
)
returns record
language plpgsql
security definer
as $$
declare
    _latest_unused_otp auth.otp_code;
    _code_ttl_seconds integer := 120; -- 2 minutes
    _reuse_threshold_seconds integer := 30; -- reuse if >= 30s remain
    _seconds_remaining_until_expiry integer;
    _latest_expires_at timestamp with time zone;
begin
    if _account_id is null then
        validation_failure_message := 'missing_account_id';
        return;
    end if;

    _latest_unused_otp := auth.get_latest_unused_otp_for_account(_account_id);

    if _latest_unused_otp.otp_code_id is not null then
        _latest_expires_at := _latest_unused_otp.created_at + make_interval(secs => _code_ttl_seconds);
        _seconds_remaining_until_expiry := ceil(extract(epoch from (_latest_expires_at - now())))::int;

        if _seconds_remaining_until_expiry >= _reuse_threshold_seconds then
            otp_code_id := _latest_unused_otp.otp_code_id;
            code := _latest_unused_otp.code;
            expires_at := _latest_expires_at;
            seconds_remaining := greatest(_seconds_remaining_until_expiry, 0);
            return;
        end if;
    end if;

    -- create new code
    insert into auth.otp_code (account_id, code)
    values (_account_id, auth.generate_otp_code())
    returning
        otp_code_id,
        code,
        created_at + make_interval(secs => _code_ttl_seconds) as expires_at
    into otp_code_id, code, expires_at;

    seconds_remaining := _code_ttl_seconds;
    return;
end;
$$;

-- internal: get or create account by email
create or replace function accounts.get_or_create_account_by_email(
    _email text
)
returns accounts.account
language plpgsql
as $$
declare
    _existing_account accounts.account;
    _new_account accounts.account;
begin
    _existing_account := accounts.get_account_by_email(_email);
    if _existing_account.account_id is not null then
        return _existing_account;
    end if;

    insert into accounts.account (email)
    values (_email)
    returning * into _new_account;
    return _new_account;
end;
$$;

-- internal: get or create account by phone number
create or replace function accounts.get_or_create_account_by_phone_number(
    _phone text
)
returns accounts.account
language plpgsql
as $$
declare
    _existing_account accounts.account;
    _new_account accounts.account;
begin
    _existing_account := accounts.get_account_by_phone_number(_phone);
    if _existing_account.account_id is not null then
        return _existing_account;
    end if;

    insert into accounts.account (phone_number)
    values (_phone)
    returning * into _new_account;
    return _new_account;
end;
$$;

-- seed otp email template
insert into comms.email_template (
    template_key,
    subject,
    body,
    body_params,
    description
)
values (
    'otp_login',
    'Your Chatterbox sign-in code: ${code}',
    'Your Chatterbox sign-in code is ${code}. Expires in ${minutes} min.',
    array['code', 'minutes'],
    'OTP login template'
)
on conflict (template_key) do nothing;

-- seed otp sms template
insert into comms.sms_template (
    template_key,
    body,
    body_params,
    description
)
values (
    'otp_login',
    'Your Chatterbox sign-in code is ${code}. Expires in ${minutes} min.',
    array['code', 'minutes'],
    'OTP login template'
)
on conflict (template_key) do nothing;

-- API: request login code
create or replace function api.request_login_code(
    identifier text
)
returns jsonb
language plpgsql
as $$
declare
    _identifier_type auth.account_identifier_type := auth.get_account_identifier_type(identifier);
    _account accounts.account;
begin
    if _identifier_type.validation_failure_message is not null then
        raise exception 'OTP Request Failed'
            using detail = 'Invalid Request Payload',
                  hint = _identifier_type.validation_failure_message;
    end if;

    if _identifier_type = 'email' then
        _account := accounts.get_or_create_account_by_email(identifier);
    elsif _identifier_type = 'phone' then
        _account := accounts.get_or_create_account_by_phone_number(identifier);
    end if;
end;
$$;

commit;
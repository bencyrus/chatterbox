begin;

-- add phone-based login and OTP support without altering existing basic auth behaviors

-- add helper to allow nullable passwords to support passwordless accounts
create or replace function accounts.is_password_valid_or_null(_password text)
returns boolean
immutable
language sql
as $$
    select case when $1 is null then true else accounts.is_password_valid($1) end;
$$;

-- phone validation and normalization helpers
create or replace function accounts.is_phone_valid(_phone text)
returns boolean
immutable
language sql
as $$
    -- very light E.164 check: optional +, 8-15 digits, cannot start with 0
    select $1 ~ '^\+?[1-9][0-9]{7,14}$';
$$;

create or replace function accounts.is_phone_valid_or_null(_phone text)
returns boolean
immutable
language sql
as $$
    select case when $1 is null then true else accounts.is_phone_valid($1) end;
$$;

create or replace function accounts.normalize_phone(_phone text)
returns text
immutable
language sql
as $$
with cleaned as (
    select regexp_replace(coalesce(_phone, ''), '[^0-9+]', '', 'g') as raw
),
formatted as (
    select case
        when raw = '' then null
        when raw like '+%' then raw
        else '+' || raw
    end as normalized
    from cleaned
)
select normalized from formatted;
$$;

-- alter account table: support phone_number, nullable password, and email-or-phone presence
alter table accounts.account
    add column if not exists phone_number text;

alter table accounts.account
    alter column email drop not null;

alter table accounts.account
    alter column hashed_password drop not null;

-- replace password constraint to allow nulls
alter table accounts.account
    drop constraint if exists hashed_password_nonempty;

alter table auth.account
    add constraint hashed_password_valid_or_null
    check (accounts.is_password_valid_or_null(hashed_password));

-- phone validity check (email validity already enforced by existing constraint when present)
alter table accounts.account
    drop constraint if exists phone_number_valid;

alter table accounts.account
    add constraint phone_number_valid
    check (accounts.is_phone_valid_or_null(phone_number));

-- require at least one of email or phone_number
alter table accounts.account
    add constraint email_or_phone_present
    check (email is not null or phone_number is not null);

-- otp tables

-- stores issued login codes per account (append-only)
create table if not exists auth.otp_code (
    otp_code_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    code text not null,
    created_at timestamp with time zone not null default now()
);

-- records successful consumptions of codes (append-only, one per otp_code_id)
create table if not exists auth.otp_code_used (
    otp_code_used_id bigserial primary key,
    otp_code_id bigint not null references auth.otp_code(otp_code_id) on delete cascade,
    used_at timestamp with time zone not null default now(),
    constraint otp_code_used_once unique (otp_code_id)
);

-- records failed verification attempts (append-only) for observability
create table if not exists auth.otp_code_failed_attempt (
    otp_code_failed_attempt_id bigserial primary key,
    account_id bigint references accounts.account(account_id) on delete cascade,
    code_attempted text not null,
    created_at timestamp with time zone not null default now()
);


-- helpers

-- generate a 6-digit numeric code (leading zeros allowed)
create or replace function auth.generate_otp_code()
returns text
immutable
language sql
as $$
    select lpad((trunc(random() * 1000000))::int::text, 6, '0');
$$;

-- internal helper: get latest unused code for account
create or replace function auth.get_latest_unused_otp_for_account(_account_id bigint)
returns auth.otp_code
stable
language sql
as $$
    select oc.*
    from auth.otp_code oc
    left join auth.otp_code_used u on u.otp_code_id = oc.otp_code_id
    where oc.account_id = _account_id
      and u.otp_code_id is null
    order by oc.created_at desc
    limit 1;
$$;

-- domain for account identifier types


-- helper: determine account identifier type (email or phone) with validation
create or replace function auth.get_account_identifier_type(
    _identifier text,
    out validation_failure_message text,
    out identifier_type auth.account_identifier_type
)
returns record
language plpgsql
immutable
as $$
declare
    _cleaned_identifier text := lower(btrim(_identifier));
    _normalized_phone text;
begin
    if _cleaned_identifier is null or _cleaned_identifier = '' then
        validation_failure_message := 'missing_identifier';
        return;
    end if;

    if accounts.is_email_valid(_cleaned_identifier) then
        identifier_type := 'email';
        return;
    end if;

    _normalized_phone := accounts.normalize_phone(_cleaned_identifier);
    if accounts.is_phone_valid(_normalized_phone) then
        identifier_type := 'phone';
        return;
    end if;

    validation_failure_message := 'invalid_identifier';
    return;
end;
$$;

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

-- internal: get account by email
create or replace function accounts.get_account_by_email(
    _email text
)
returns accounts.account
language sql
as $$
    select * from accounts.account where email = lower(btrim(_email));
$$;

-- internal: get account by phone number
create or replace function accounts.get_account_by_phone_number(
    _phone text
)
returns accounts.account
language sql
as $$
    select * from accounts.account where phone_number = accounts.normalize_phone(btrim(_phone));
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
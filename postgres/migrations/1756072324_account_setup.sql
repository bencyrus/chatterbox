-- Extension to support password hashing
create extension if not exists pgcrypto;

-- Schema to store account related information
create schema accounts;

-- Password validity check functions
-- To be used as the account table constraints
create or replace function accounts.is_password_valid(_password text)
returns boolean
immutable
language sql
as $$
    select length(_password) >= 8;
$$;

create or replace function accounts.is_password_valid_or_null(_password text)
returns boolean
immutable
language sql
as $$
    select case when $1 is null then true else accounts.is_password_valid($1) end;
$$;

-- Email validity check and normalization functions
-- To be used as the account table constraints
create or replace function accounts.normalize_email(_email text)
returns text
language sql
immutable
as $$
    select nullif(
        lower(regexp_replace(coalesce(_email, ''), '\\s', '', 'g')),
        ''
    );
$$;

create or replace function accounts.is_email_valid(_email text)
returns boolean
immutable
language sql
as $$
    select position('@' in accounts.normalize_email($1)) > 1;
$$;

create or replace function accounts.is_email_valid_or_null(_email text)
returns boolean
immutable
language sql
as $$
    select case when $1 is null then true else accounts.is_email_valid($1) end;
$$;

-- Phone validity check and normalization functions
-- To be used as the account table constraints
create or replace function accounts.normalize_phone(_phone text)
returns text
language sql
immutable
as $$
    select case
        when regexp_replace(coalesce(_phone, ''), '[^0-9+]', '', 'g') = '' then null
        when regexp_replace(coalesce(_phone, ''), '[^0-9+]', '', 'g') like '+%' then regexp_replace(coalesce(_phone, ''), '[^0-9+]', '', 'g')
        else '+' || regexp_replace(coalesce(_phone, ''), '[^0-9+]', '', 'g')
    end;
$$;

create or replace function accounts.is_phone_valid(_phone text)
returns boolean
immutable
language sql
as $$
    -- very light E.164 check: optional +, 8-15 digits, cannot start with 0
    select accounts.normalize_phone($1) ~ '^\+?[1-9][0-9]{7,14}$';
$$;

create or replace function accounts.is_phone_valid_or_null(_phone text)
returns boolean
immutable
language sql
as $$
    select case when $1 is null then true else accounts.is_phone_valid($1) end;
$$;


-- Account table: stores account information
create table accounts.account (
    account_id bigserial primary key,
    email text,
    phone_number text,
    hashed_password text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint email_valid_or_null check (accounts.is_email_valid_or_null(email)),
    constraint phone_valid_or_null check (accounts.is_phone_valid_or_null(phone_number)),
    constraint password_valid_or_null check (accounts.is_password_valid_or_null(hashed_password)),
    constraint email_or_phone_required check (email is not null or phone_number is not null),
    constraint email_unique unique (email),
    constraint phone_unique unique (phone_number)
);

-- Trigger to normalize email and phone number before write
create or replace function accounts.account_normalize_before_write()
returns trigger
language plpgsql
as $$
begin
    new.email := accounts.normalize_email(new.email);
    new.phone_number := accounts.normalize_phone(new.phone_number);
    return new;
end;
$$;

create trigger account_normalize_before_write
before insert or update on accounts.account
for each row
execute function accounts.account_normalize_before_write();

-- Trigger to set updated_at timestamp before write
create or replace function accounts.account_set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger account_set_updated_at
before update on accounts.account
for each row
execute function accounts.account_set_updated_at();

-- Account login table: records successful logins
create table accounts.account_login (
    account_login_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    logged_in_at timestamp with time zone not null default now()
);

-- Identifier in use function: checks if an identifier is in use
create or replace function accounts.identifier_in_use(
    _email text,
    _phone_number text
)
returns boolean
immutable
language plpgsql
as $$
declare
    _normalized_email text := accounts.normalize_email(_email);
    _normalized_phone_number text := accounts.normalize_phone(_phone_number);
begin
    return exists (
        select 1
        from accounts.account
        where email = _normalized_email
        or phone_number = _normalized_phone_number
    );
end;
$$;

-- Create account function: creates a new account
create or replace function accounts.create_account(
    _email text,
    _phone_number text,
    _password text,
    out validation_failure_message text,
    out created_account accounts.account
)
returns record
language plpgsql
security definer
as $$
declare
    _normalized_email text := accounts.normalize_email(_email);
    _normalized_phone_number text := accounts.normalize_phone(_phone_number);
begin
    if _normalized_email is null and _normalized_phone_number is null then
        validation_failure_message := 'email_or_phone_number_required';
        return;
    end if;

    if _normalized_email is not null and not accounts.is_email_valid(_normalized_email) then
        validation_failure_message := 'invalid_email';
        return;
    end if;
    
    
    if _normalized_phone_number is not null and not accounts.is_phone_valid(_normalized_phone_number) then
        validation_failure_message := 'invalid_phone_number';
        return;
    end if;

    if not accounts.is_password_valid_or_null(_password) then
        validation_failure_message := 'invalid_password';
        return;
    end if;

    if accounts.identifier_in_use(_normalized_email, _normalized_phone_number) then
        validation_failure_message := 'account_already_exists';
        return;
    end if;

    insert into accounts.account (email, phone_number, hashed_password)
    values (_normalized_email, _normalized_phone_number, crypt(_password, gen_salt('bf')))
    returning * into created_account;
    return;
end;
$$;

create domain accounts.account_identifier_type as text
    check (value in ('email', 'phone'));

create or replace function accounts.get_account_identifier_type(
    _identifier text,
    out validation_failure_message text,
    out identifier_type accounts.account_identifier_type
)
returns record
language plpgsql
immutable
as $$
declare
    _normalized_identifier text := nullif(lower(btrim(_identifier)), '');
begin
    if _normalized_identifier is null then
        validation_failure_message := 'missing_identifier';
        return;
    end if;

    if accounts.is_email_valid(_normalized_identifier) then
        identifier_type := 'email';
        return;
    end if;

    if accounts.is_phone_valid(_normalized_identifier) then
        identifier_type := 'phone';
        return;
    end if;

    validation_failure_message := 'invalid_identifier';
    return;
end;
$$;

-- Retrieve account by email: returns normalized email match
create or replace function accounts.get_account_by_email(
    _email text
)
returns accounts.account
stable
language sql
as $$
    select *
    from accounts.account
    where email = accounts.normalize_email(_email);
$$;

-- Retrieve account by phone: returns normalized phone match
create or replace function accounts.get_account_by_phone_number(
    _phone_number text
)
returns accounts.account
stable
language sql
as $$
    select *
    from accounts.account
    where phone_number = accounts.normalize_phone(_phone_number);
$$;

-- Retrieve account by identifier (email or phone)
create or replace function accounts.get_account_by_identifier(
    _identifier text,
    out validation_failure_message text,
    out account accounts.account
)
returns record
stable
language plpgsql
as $$
declare
    _identifier_type_result record := accounts.get_account_identifier_type(_identifier);
begin
    if _identifier_type_result.validation_failure_message is not null then
        validation_failure_message := _identifier_type_result.validation_failure_message;
        return;
    end if;

    if _identifier_type_result.identifier_type = 'email' then
        account := accounts.get_account_by_email(_identifier);
    else
        account := accounts.get_account_by_phone_number(_identifier);
    end if;
    return;
end;
$$;

-- Get or create account by identifier (email or phone)
create or replace function accounts.get_or_create_account_by_identifier(
    _identifier text,
    out validation_failure_message text,
    out account accounts.account
)
returns record
language plpgsql
security definer
as $$
declare
    _get_account_result record := accounts.get_account_by_identifier(_identifier);
    _identifier_type_result record := accounts.get_account_identifier_type(_identifier);
    _create_result record;
begin
    if _get_account_result.validation_failure_message is not null then
        validation_failure_message := _get_account_result.validation_failure_message;
        return;
    end if;

    if (_get_account_result.account).account_id is not null then
        account := _get_account_result.account;
        return;
    end if;

    if _identifier_type_result.validation_failure_message is not null then
        validation_failure_message := _identifier_type_result.validation_failure_message;
        return;
    end if;

    if _identifier_type_result.identifier_type = 'email' then
        _create_result := accounts.create_account(_identifier, null, null);
    else
        _create_result := accounts.create_account(null, _identifier, null);
    end if;

    if _create_result.validation_failure_message is not null then
        validation_failure_message := _create_result.validation_failure_message;
        return;
    end if;

    account := (_create_result.created_account);
    return;
end;
$$;

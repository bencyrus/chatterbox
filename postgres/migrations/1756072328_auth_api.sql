-- Signup function: creates an account and returns tokens
create or replace function api.signup(
    password text,
    email text default null,
    phone_number text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _create_result record;
    _access_token text;
    _refresh_token text;
begin
    _create_result := accounts.create_account(email, phone_number, password);
    if _create_result.validation_failure_message is not null then
        raise exception 'Signup Failed'
            using detail = 'Invalid Input',
                  hint = _create_result.validation_failure_message;
    end if;

    if (_create_result.created_account).account_id is null then
        raise exception 'Signup Failed'
            using detail = 'Account Not Created',
                  hint = 'account_creation_failed';
    end if;

    _access_token := auth.create_access_token((_create_result.created_account).account_id);
    _refresh_token := auth.create_refresh_token((_create_result.created_account).account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.signup(text, text, text) to anon;

-- Login function: logs in an account
create or replace function api.login(identifier text, password text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _identifier_type_result record := accounts.get_account_identifier_type($1);
    _account accounts.account;
    _access_token text;
    _refresh_token text;
begin    
    if _identifier_type_result.validation_failure_message is not null then
        raise exception 'Login Failed'
            using detail = 'Invalid Identifier',
                  hint = _identifier_type_result.validation_failure_message;
    end if;

    if _identifier_type_result.identifier_type = 'email' then
        _account := accounts.get_account_by_email($1);
    else
        _account := accounts.get_account_by_phone_number($1);
    end if;

    if _account.account_id is null then
        raise exception 'Login Failed'
            using detail = 'Invalid Credentials',
                  hint = 'account_not_found';
    end if;

    if crypt(password, _account.hashed_password) <> _account.hashed_password then
        raise exception 'Login Failed'
            using detail = 'Invalid Credentials',
                  hint = 'bad_password';
    end if;

    -- record successful login
    insert into accounts.account_login (account_id)
    values (_account.account_id);

    _access_token := auth.create_access_token(_account.account_id);
    _refresh_token := auth.create_refresh_token(_account.account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.login(text, text) to anon;

-- Refresh tokens function: refreshes access and refresh tokens
create or replace function api.refresh_tokens(refresh_token text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _access_token text;
    _new_refresh_token text;
    _validate_result record;
begin
    if refresh_token is null then
        raise exception 'Refresh Failed'
            using detail = 'Missing Refresh Token',
                  hint = 'missing_refresh_token';
    end if;

    _validate_result := auth.validate_token(refresh_token, 'refresh'::auth.token_use);

    if _validate_result.validation_failure_message is not null then
        raise exception 'Refresh Failed'
            using detail = 'Invalid Refresh Token',
                  hint = _validate_result.validation_failure_message;
    end if;

    _access_token := auth.create_access_token(_validate_result.account_id);
    _new_refresh_token := auth.create_refresh_token(_validate_result.account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _new_refresh_token
    );
end;
$$;

grant execute on function api.refresh_tokens(text) to anon;

-- create a simple authenticated-only test view
create view api.hello_secure as
select 'Hello, Authenticated!' as message;

-- grant select permission only to authenticated role
grant select on api.hello_secure to authenticated;

begin;

-- Extension to support UUIDs
create extension if not exists "uuid-ossp";

-- Auth schema: stores auth-related information
create schema auth;

-- Login code table: stores login codes generated for accounts
create table auth.login_code (
    login_code_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    code text not null,
    created_at timestamp with time zone not null default now()
);

-- Login code usage table: stores usage of login codes
create table auth.login_code_usage (
    login_code_usage_id bigserial primary key,
    login_code_id bigint not null references auth.login_code(login_code_id) on delete cascade,
    used_at timestamp with time zone not null default now()
);

-- Login code failed attempt table: stores failed login code attempts
create table auth.login_code_failed_attempt (
    login_code_failed_attempt_id bigserial primary key,
    account_id bigint references accounts.account(account_id) on delete cascade,
    code_attempted text not null,
    created_at timestamp with time zone not null default now()
);

-- Generate login code function: generates a 6-digit login code
create or replace function auth.generate_login_code()
returns text
immutable
language sql
as $$
    select lpad((trunc(random() * 1000000))::int::text, 6, '0');
$$;

-- Get latest unused login code for account function: retrieves the latest unused login code for an account
create or replace function auth.get_latest_unused_login_code_for_account(_account_id bigint)
returns auth.login_code
stable
language sql
as $$
    select lc.*
    from auth.login_code lc
    left join auth.login_code_usage lc_usage on lc_usage.login_code_id = lc.login_code_id
    where lc.account_id = _account_id
    and lc_usage.login_code_id is null
    order by lc.created_at desc
    limit 1;
$$;

-- Token use domain: defines the types of tokens that can be used
create domain auth.token_use as text
    check (value in ('access', 'refresh'));

-- JWT config function: retrieves the JWT config from the configuration table
create or replace function auth.jwt_config(
    out secret text,
    out access_token_expiry_seconds integer,
    out refresh_token_expiry_seconds integer
)
returns record
stable
language sql
security definer
as $$
    select
        (cfg->>'secret')::text,
        (cfg->>'access_token_expiry_seconds')::int,
        (cfg->>'refresh_token_expiry_seconds')::int
    from (select internal.get_config('jwt') as cfg) s;
$$;

-- JWT Generation Functions

-- URL encode function: encodes a bytea value to a base64 string
create or replace function auth.url_encode(data bytea) returns text
immutable
language sql
as $$
    select translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;

-- URL decode function: decodes a base64 string to a bytea value
create or replace function auth.url_decode(data text) returns bytea
immutable
language sql
as $$
with t as (select translate(data, '-_', '+/') as trans),
     rem as (select length(t.trans) % 4 as remainder from t)
    select decode(
        t.trans ||
        case when rem.remainder > 0
           then repeat('=', (4 - rem.remainder))
           else '' end,
    'base64') from t, rem;
$$;

-- Algorithm sign function: signs a text value with a secret and algorithm
create or replace function auth.algorithm_sign(signables text, secret text, algorithm text default 'HS256')
returns text
immutable
language sql
as $$
with alg as (
    select case
        when algorithm = 'HS256' then 'sha256'
        when algorithm = 'HS384' then 'sha384'
        when algorithm = 'HS512' then 'sha512'
        else '' end as id
)
select auth.url_encode(hmac(signables, secret, alg.id)) from alg;
$$;

-- Sign function: signs a JSON payload with a secret and algorithm
create or replace function auth.sign(payload jsonb, secret text, algorithm text default 'HS256')
returns text
immutable
language sql
as $$
    with header as (
        select auth.url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8')) as data
    ),
    payload_b64 as (
        select auth.url_encode(convert_to(payload::text, 'utf8')) as data
    ),
    signables as (
        select header.data || '.' || payload_b64.data as data from header, payload_b64
    )
    select signables.data || '.' || auth.algorithm_sign(signables.data, secret, algorithm) from signables;
$$;

-- Try cast double function: tries to cast a text value to a double precision value
create or replace function auth.try_cast_double(inp text) returns double precision
immutable
language plpgsql
as $$
begin
    begin
        return inp::double precision;
    exception
        when others then return null;
    end;
end;
$$;

-- Verify function: verifies a token with a secret and algorithm
create or replace function auth.verify(
    token text,
    secret text,
    algorithm text default 'HS256',
    out header jsonb,
    out payload jsonb,
    out valid boolean
)
returns record
immutable
language sql
as $$
    select
        jwt.header,
        jwt.payload,
        jwt.signature_ok and tstzrange(
          to_timestamp(auth.try_cast_double(jwt.payload->>'nbf')),
          to_timestamp(auth.try_cast_double(jwt.payload->>'exp'))
        ) @> current_timestamp
    from (
        select
            convert_from(auth.url_decode(r[1]), 'utf8')::jsonb as header,
            convert_from(auth.url_decode(r[2]), 'utf8')::jsonb as payload,
            r[3] = auth.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) as signature_ok
        from regexp_split_to_array(token, E'\\.') r
    ) jwt;
$$;

-- Create access token function: creates an access token for an account
create or replace function auth.create_access_token(
    _account_id bigint,
    out access_token text
)
returns text
stable
language plpgsql
security definer
as
$$
declare
    _jwt_config record := auth.jwt_config();
begin
    access_token := auth.sign(
        jsonb_build_object(
            'sub', _account_id,
            'role', 'authenticated',
            'token_use', 'access'::auth.token_use,
            'iat', extract(epoch from now())::int,
            'nbf', extract(epoch from now())::int,
            'exp', extract(
                epoch from now() + make_interval(
                    secs => (_jwt_config.access_token_expiry_seconds)
                )
            )::int
        ),
        (_jwt_config.secret),
        'HS256'
    );

    return;
end;
$$;

-- Create refresh token function: creates a refresh token for an account
create or replace function auth.create_refresh_token(
    _account_id bigint,
    out refresh_token text
)
returns text
stable
language plpgsql
security definer
as $$
declare
    _jwt_config record := auth.jwt_config();
begin
    refresh_token := auth.sign(
        jsonb_build_object(
            'sub', _account_id,
            'role', 'authenticated',
            'token_use', 'refresh'::auth.token_use,
            'iat', extract(epoch from now())::int,
            'nbf', extract(epoch from now())::int,
            'exp', extract(
                epoch from now() + make_interval(
                    secs => (_jwt_config.refresh_token_expiry_seconds)
                )
            )::int
        ),
        (_jwt_config.secret),
        'HS256'
    );

    return;
end;
$$;

-- Signup function: creates an account and returns tokens
create or replace function api.signup(
    email text,
    phone_number text,
    password text
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

create or replace function auth.validate_token(
    _token text,
    _required_use auth.token_use,
    out validation_failure_message text,
    out account_id bigint
)
returns record
language plpgsql
security definer
as $$
declare
    _payload jsonb;
    _sub bigint;
    _token_use text;
    _jwt_config record := auth.jwt_config();
    _verify_result record;
begin
    _verify_result := auth.verify(_token, _jwt_config.secret, 'HS256');
    if not _verify_result.valid then
        validation_failure_message := 'token_invalid';
        return;
    end if;

    _payload := _verify_result.payload;

    _sub := (_payload->>'sub')::bigint;
    _token_use := _payload->>'token_use';
    if _required_use is not null and _token_use is distinct from _required_use then
        validation_failure_message := 'wrong_token_use';
        return;
    end if;

    account_id := _sub;
    return;
end;
$$;

create or replace function api.refresh_tokens(refresh_token text)
returns jsonb
stable
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

commit;

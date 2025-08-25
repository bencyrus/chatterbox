begin;

create schema auth;

create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

create schema internal;

create table internal.config (
    key text primary key,
    value jsonb not null
);


create or replace function internal.get_config(_key text)
returns jsonb
language sql
as
$$
    select value from internal.config where key = _key;
$$;

create or replace function auth.is_email_valid(_email text)
returns boolean
language sql
as
$$
    select position('@' in _email) > 1;
$$;

create or replace function auth.is_password_valid(_password text)
returns boolean
language sql
as
$$
    select length(_password) >= 8;
$$;

create table if not exists auth.account (
    account_id bigserial primary key,
    email text not null,
    hashed_password text not null,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone not null default now(),
    constraint email_has_at check (auth.is_email_valid(email)),
    constraint hashed_password_nonempty check (auth.is_password_valid(hashed_password))
);

create domain auth.token_use as text
    check (value in ('access', 'refresh'));

create or replace function auth.jwt_secret() returns text
stable
language sql
security definer
as $$
    select internal.get_config('jwt_secret')->>'text';
$$;

create or replace function auth.url_encode(data bytea) returns text
immutable
language sql
as $$
    select translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;

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

create or replace function auth.verify(token text, secret text, algorithm text default 'HS256')
returns table(header jsonb, payload jsonb, valid boolean)
immutable
language sql
as $$
  select
    jwt.header as header,
    jwt.payload as payload,
    jwt.signature_ok and tstzrange(
      to_timestamp(auth.try_cast_double(jwt.payload->>'nbf')),
      to_timestamp(auth.try_cast_double(jwt.payload->>'exp'))
    ) @> current_timestamp as valid
  from (
    select
      convert_from(auth.url_decode(r[1]), 'utf8')::jsonb as header,
      convert_from(auth.url_decode(r[2]), 'utf8')::jsonb as payload,
      r[3] = auth.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) as signature_ok
    from regexp_split_to_array(token, '\\.') r
  ) jwt;
$$;

create or replace function auth.create_access_token(_account_id bigint, _ttl_seconds integer default 60*60*24*7 /* 7 days */)
returns text
stable
language sql
as $$
    select auth.sign(
        jsonb_build_object(
            'sub', _account_id,
            'role', 'authenticated',
            'token_use', 'access'::auth.token_use,
            'iat', extract(epoch from now())::int,
            'nbf', extract(epoch from now())::int,
            'exp', extract(epoch from now() + make_interval(secs => _ttl_seconds))::int
        ),
        auth.jwt_secret(),
        'HS256'
    );
$$;

create or replace function auth.create_refresh_token(_account_id bigint, _ttl_seconds integer default 60*60*24*30 /* 30 days */)
returns text
stable
language sql
as $$
    select auth.sign(
        jsonb_build_object(
            'sub', _account_id,
            'role', 'authenticated',
            'token_use', 'refresh'::auth.token_use,
            'iat', extract(epoch from now())::int,
            'nbf', extract(epoch from now())::int,
            'exp', extract(epoch from now() + make_interval(secs => _ttl_seconds))::int
        ),
        auth.jwt_secret(),
        'HS256'
    );
$$;

create type auth.create_account_result as (
    validation_failure_message text,
    created_account auth.account
);

create or replace function auth.create_account(
    _email text,
    _password text
)
returns auth.create_account_result
language plpgsql
security definer
as $$
declare
    _lower_email text := lower(_email);
    _created_account auth.account;
begin
    -- validate input
    if _lower_email is null or _password is null then
        return ('missing_email_or_password', null)::auth.create_account_result;
    end if;

    if not auth.is_email_valid(_lower_email) then
        return ('invalid_email', null)::auth.create_account_result;
    end if;

    if not auth.is_password_valid(_password) then
        return ('weak_password', null)::auth.create_account_result;
    end if;

    if exists (select 1 from auth.account where lower(email) = _lower_email) then
        return ('email_already_exists', null)::auth.create_account_result;
    end if;

    -- create account
    insert into auth.account (email, hashed_password)
    values (_lower_email, crypt(_password, gen_salt('bf')))
    returning * into _created_account;

    return (null, _created_account)::auth.create_account_result;
end;
$$;

create or replace function api.signup(email text, password text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _create_result auth.create_account_result;
    _access_token text;
    _refresh_token text;
    _account_id bigint;
begin
    _create_result := auth.create_account(email, password);

    if _create_result.validation_failure_message is not null then
        raise exception 'Signup Failed'
            using detail = 'Invalid Request Payload',
                  hint = _create_result.validation_failure_message;
    end if;

    _account_id := (_create_result.created_account).account_id;
    _access_token := auth.create_access_token(_account_id);
    _refresh_token := auth.create_refresh_token(_account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.signup(text, text) to anon;

create or replace function api.login(email text, password text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _email text := lower(email);
    _account auth.account;
    _access_token text;
    _refresh_token text;
begin
    select *
    into _account
    from auth.account
    where lower(auth.account.email) = _email;

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

    _access_token := auth.create_access_token(_account.account_id);
    _refresh_token := auth.create_refresh_token(_account.account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.login(text, text) to anon;

create type auth.validate_token_result as (
    validation_failure_message text,
    account_id bigint
);

create or replace function auth.validate_token(_token text, _required_use auth.token_use)
returns auth.validate_token_result
language plpgsql
security definer
as $$
declare
    _payload jsonb;
    _sub bigint;
    _token_use text;
begin
    select v.payload
    into _payload
    from auth.verify(_token, auth.jwt_secret(), 'HS256') v
    where v.valid;

    if _payload is null then
        return ('token_invalid', null)::auth.validate_token_result;
    end if;

    _sub := (_payload->>'sub')::bigint;
    _token_use := _payload->>'token_use';
    if _required_use is not null and _token_use is distinct from _required_use then
        return ('wrong_token_use', null)::auth.validate_token_result;
    end if;

    return (null, _sub)::auth.validate_token_result;
end;
$$;

create or replace function api.refresh_tokens()
returns jsonb
stable
language plpgsql
security definer
as $$
declare
    _headers jsonb := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
    _refresh_token text := _headers->>'x-refresh-token';
    _validate_result auth.validate_token_result;
    _access_token text;
    _new_refresh_token text;
begin
    if _refresh_token is null then
        raise exception 'Refresh Failed'
            using detail = 'Missing Refresh Token',
                  hint = 'missing_refresh_token_header';
    end if;

    _validate_result := auth.validate_token(_refresh_token, 'refresh'::auth.token_use);
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

grant execute on function api.refresh_tokens() to anon;

-- create a simple authenticated-only test view
create view api.hello_secure as
select 'Hello, Authenticated!' as message;

-- grant select permission only to authenticated role
grant select on api.hello_secure to authenticated;

commit;

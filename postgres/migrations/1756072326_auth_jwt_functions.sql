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

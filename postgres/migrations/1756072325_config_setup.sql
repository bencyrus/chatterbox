-- Internal schema: used for internal logic such as configuration
create schema internal;

-- Configuration table: stores configuration
-- It's a simple key-value store with JSONB values that can be used to store arbitrary data
create table internal.config (
    key text primary key,
    value jsonb not null
);

-- Get configuration function: retrieves a configuration value by key
create or replace function internal.get_config(_key text)
returns jsonb
language sql
as
$$
    select value from internal.config where key = _key;
$$;

-- seed the jwt config
insert into internal.config (
    key,
    value
)
values (
    'jwt',
    '{
        "secret": "{secrets.jwt_secret}",
        "access_token_expiry_seconds": 3600,
        "refresh_token_expiry_seconds": 86400,
        "refresh_threshold_seconds": 3600
    }'
)
on conflict (key) do nothing;

-- seed internal config
insert into internal.config (
    key,
    value
)
values (
    'login_with_code',
    '{"code_expiry_minutes": 5}'
)
on conflict (key) do nothing;

-- seed emails config with purpose keys
insert into internal.config (
    key,
    value
)
values (
    'from_emails',
    '{
        "hello": "{secrets.hello_email}",
        "noreply": "{secrets.noreply_email}"
    }'
)
on conflict (key) do nothing;

begin;

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

commit;
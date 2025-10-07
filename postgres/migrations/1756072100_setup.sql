-- create a role for unauthenticated users (no login)
create role anon nologin;

-- create a role for authenticated users (no login)
create role authenticated nologin;

-- create the role that postgrest connects as (secure and minimal permissions)
create role authenticator
  login
  noinherit
  nocreatedb
  nocreaterole
  nosuperuser
  password '{secrets.authenticator_password}';

-- allow the authenticator to switch into either the anon or authenticated role
grant anon to authenticator;
grant authenticated to authenticator;

-- create a schema for our API endpoints
create schema api;

-- grant usage on the api schema to both roles
grant usage on schema api to anon;
grant usage on schema api to authenticated;

-- create a simple test view
create view api.hello_world as
select 'Hello, World!' as message;

-- grant select permission on the view to both roles
grant select on api.hello_world to anon, authenticated;

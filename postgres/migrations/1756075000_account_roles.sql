-- domain: account role for access control
create domain accounts.account_role_type as text
    check (value in ('creator', 'user'));

create table if not exists accounts.account_role (
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    role accounts.account_role_type not null,
    created_at timestamp with time zone not null default now(),
    constraint account_roles_unique unique (account_id, role)
);

-- backfill account roles
insert into accounts.account_role (account_id, role)
select account_id, 'user'
from accounts.account;

-- function: resolve account_id from JWT "sub" claim provided by PostgREST
create or replace function auth.jwt_account_id()
returns bigint
stable
language sql
security definer
as $$
    select nullif(
        (current_setting('request.jwt.claims', true)::jsonb ->> 'sub'),
        ''
    )::bigint;
$$;

-- function: check if the given account has the 'creator' role
create or replace function auth.is_creator_account(_account_id bigint)
returns boolean
stable
language sql
security definer
as $$
    select exists (
        select 1
        from accounts.account_role
        where account_id = _account_id
        and role = 'creator'
    );
$$;

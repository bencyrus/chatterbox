-- domain: account flag for feature flags and account metadata
create domain accounts.account_flag_type as text
    check (value in ('developer'));

-- table: account flags (many-to-many relationship between accounts and flags)
create table if not exists accounts.account_flag (
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    flag accounts.account_flag_type not null,
    created_at timestamp with time zone not null default now(),
    constraint account_flags_unique unique (account_id, flag)
);

-- function: get account flags as a jsonb array of strings
create or replace function accounts.account_flags(_account_id bigint)
returns jsonb
language sql
stable
as $$
    select coalesce(
        jsonb_agg(af.flag order by af.flag),
        '[]'::jsonb
    )
    from accounts.account_flag af
    where af.account_id = _account_id;
$$;

-- function: update account_summary to include flags array
create or replace function accounts.account_summary(
    _account_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'account_id', a.account_id,
        'email', a.email,
        'phone_number', a.phone_number,
        'account_role', ar.role,
        'flags', accounts.account_flags(a.account_id),
        'last_login_at', (
            select max(logged_in_at)
            from accounts.account_login
            where account_id = a.account_id
        )
    )
    from accounts.account a
    join accounts.account_role ar
        on ar.account_id = a.account_id
    where a.account_id = _account_id;
$$;


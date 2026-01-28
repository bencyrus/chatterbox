-- account summary and app configuration API
-- provides api.me endpoint and app-wide configuration

create or replace function accounts.account_summary(
    _account_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'account', jsonb_build_object(
            'account_id', a.account_id,
            'email', a.email,
            'phone_number', a.phone_number
        ),
        'account_role', ar.role,
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

create or replace function api.me()
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _account_summary jsonb := accounts.account_summary(_authenticated_account_id);
    _active_profile_summary jsonb := learning.active_profile_summary_by_account_id(_authenticated_account_id);
begin
    if _authenticated_account_id is null then
        raise exception 'Get Me Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_me';
    end if;

    return jsonb_build_object(
        'account', _account_summary,
        'active_profile', _active_profile_summary
    );
end;
$$;

grant execute on function api.me() to authenticated;

-- seed app configuration values
insert into internal.config (
    key,
    value
)
values (
    'default_profile_language_code',
    '"en"'
)
on conflict (key) do nothing;

insert into internal.config (
    key,
    value
)
values (
    'available_language_codes',
    '["en","fr","de"]'
)
on conflict (key) do nothing;

insert into internal.config (
    key,
    value
)
values (
    'flags',
    '[]'
)
on conflict (key) do nothing;

-- config helpers
create or replace function internal.default_profile_language_code()
returns jsonb
stable
language sql
as $$
    select internal.get_config('default_profile_language_code');
$$;

create or replace function internal.available_language_codes()
returns jsonb
stable
language sql
as $$
    select internal.get_config('available_language_codes');
$$;

create or replace function internal.flags()
returns jsonb
stable
language sql
as $$
    select internal.get_config('flags');
$$;

create or replace function api.app_config()
returns jsonb
language plpgsql
security definer
as $$
begin
    return jsonb_build_object(
        'default_profile_language_code', internal.default_profile_language_code(),
        'available_language_codes', internal.available_language_codes(),
        'flags', internal.flags()
    );
end;
$$;

grant execute on function api.app_config() to anon, authenticated;

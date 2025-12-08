-- reviewer login (bypass email for app review)

-- seed reviewer_login config (idempotent)
insert into internal.config (
    key,
    value
)
values (
    'reviewer_login',
    '{
        "email": "{secrets.reviewer_email}"
    }'
)
on conflict (key) do nothing;

-- helper to get reviewer email
create or replace function auth.reviewer_email()
returns text
stable
language sql
as $$
    select (internal.get_config('reviewer_login')->>'email')::text;
$$;

-- api: reviewer login (no email sent, instant tokens)
create or replace function api.reviewer_login(identifier text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _reviewer_email text := auth.reviewer_email();
    _account_result record;
    _access_token text;
    _refresh_token text;
begin
    -- verify this is the reviewer email first
    if lower(btrim(identifier)) != lower(btrim(_reviewer_email)) then
        raise exception 'Reviewer Login Failed'
            using detail = 'Not Reviewer Account',
                  hint = 'not_reviewer_account';
    end if;

    -- get or create the reviewer account
    _account_result := accounts.get_or_create_account_by_identifier(identifier);
    if _account_result.validation_failure_message is not null then
        raise exception 'Reviewer Login Failed'
            using detail = 'Account Error',
                  hint = _account_result.validation_failure_message;
    end if;

    -- record login
    perform auth.record_account_login((_account_result.account).account_id);

    -- create tokens
    _access_token := auth.create_access_token((_account_result.account).account_id);
    _refresh_token := auth.create_refresh_token((_account_result.account).account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.reviewer_login(text) to anon;


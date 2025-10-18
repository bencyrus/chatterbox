-- magic-link login (email + sms)

-- seed magic_login config (idempotent)
insert into internal.config (
    key,
    value
)
values (
    'magic_login',
    '{
        "token_expiry_seconds": 900,
        "link_https_base_url": "{secrets.magic_login_link_https_base_url}"
    }'
)
on conflict (key) do nothing;

-- tables
create table auth.magic_login_token (
    magic_login_token_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    token_hash bytea not null unique,
    created_at timestamp with time zone not null default now()
);

create table auth.magic_login_token_usage (
    magic_login_token_usage_id bigserial primary key,
    magic_login_token_id bigint not null references auth.magic_login_token(magic_login_token_id) on delete cascade,
    used_at timestamp with time zone not null default now(),
    constraint magic_login_token_usage_unique unique (magic_login_token_id)
);

-- helpers
create or replace function auth.magic_token_expiry_seconds()
returns integer
stable
language sql
as $$
    select coalesce((internal.get_config('magic_login')->>'token_expiry_seconds')::int, 900);
$$;

create or replace function auth.hash_magic_token(_token text)
returns bytea
immutable
language sql
as $$
    select digest(coalesce(_token, ''), 'sha256');
$$;

create or replace function auth.get_latest_unused_magic_login_token_for_account(
    _account_id bigint
)
returns auth.magic_login_token
stable
language sql
as $$
    select t.*
    from auth.magic_login_token t
    left join auth.magic_login_token_usage u on u.magic_login_token_id = t.magic_login_token_id
    where t.account_id = _account_id
      and u.magic_login_token_id is null
      and t.created_at >= now() - make_interval(secs => auth.magic_token_expiry_seconds())
    order by t.created_at desc
    limit 1;
$$;

create or replace function auth.create_magic_login_token(
    _account_id bigint,
    out token text,
    out row_data auth.magic_login_token
)
returns record
language plpgsql
security definer
as $$
declare
    _token_plain text := auth.url_encode(gen_random_bytes(32));
    _token_hash bytea := auth.hash_magic_token(_token_plain);
begin
    insert into auth.magic_login_token (account_id, token_hash)
    values (_account_id, _token_hash)
    returning * into row_data;

    token := _token_plain;
    return;
end;
$$;

create or replace function auth.record_magic_login_token_usage(
    _magic_login_token_id bigint
)
returns void
language sql
as $$
    insert into auth.magic_login_token_usage (magic_login_token_id)
    values (_magic_login_token_id);
$$;

-- api: request link
create or replace function api.request_magic_link(identifier text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _identifier_type_result record := accounts.get_account_identifier_type($1);
    _account_result record;
    _magic_token_result record;
    _token_expiry_seconds integer := auth.magic_token_expiry_seconds();
    _token_expiry_minutes integer := greatest(1, (_token_expiry_seconds / 60));
    _magic_link_base_url text := internal.get_config('magic_login')->>'link_https_base_url';
    _magic_link_url text;
    _rendered_email record;
    _rendered_sms_body text;
    _kickoff_validation_failure_message text;
begin
    if _identifier_type_result.validation_failure_message is not null then
        raise exception 'Request Magic Link Failed'
            using detail = 'Invalid Identifier',
                  hint = _identifier_type_result.validation_failure_message;
    end if;

    _account_result := accounts.get_or_create_account_by_identifier($1);
    if _account_result.validation_failure_message is not null then
        raise exception 'Request Magic Link Failed'
            using detail = 'Account Error',
                  hint = _account_result.validation_failure_message;
    end if;

    _magic_token_result := auth.create_magic_login_token((_account_result.account).account_id);

    _magic_link_url := _magic_link_base_url || case when position('?' in _magic_link_base_url) > 0 then '&' else '?' end || 'token=' || (_magic_token_result.token);

    if _identifier_type_result.identifier_type = 'email' then
        _rendered_email := comms.render_email_template(
            'magic_login_link_email',
            jsonb_build_object('url', _magic_link_url, 'token_expiry_minutes', _token_expiry_minutes)
        );

        if _rendered_email.subject is null or _rendered_email.body is null then
            raise exception 'Request Magic Link Failed'
                using detail = 'Email template not found',
                      hint = 'email_template_not_found';
        end if;

        _kickoff_validation_failure_message := comms.create_and_kickoff_email_task(
            comms.from_email_address('noreply'),
            (_account_result.account).email,
            _rendered_email.subject,
            _rendered_email.body,
            now()
        );

        if _kickoff_validation_failure_message is not null then
            raise exception 'Request Magic Link Failed'
                using detail = 'Unable to schedule email',
                      hint = _kickoff_validation_failure_message;
        end if;
    else
        _rendered_sms_body := comms.render_sms_template(
            'magic_login_link_sms',
            jsonb_build_object('url', _magic_link_url, 'token_expiry_minutes', _token_expiry_minutes)
        );

        if _rendered_sms_body is null then
            raise exception 'Request Magic Link Failed'
                using detail = 'SMS template not found',
                      hint = 'sms_template_not_found';
        end if;

        _kickoff_validation_failure_message := comms.create_and_kickoff_sms_task(
            (_account_result.account).phone_number,
            _rendered_sms_body,
            now()
        );

        if _kickoff_validation_failure_message is not null then
            raise exception 'Request Magic Link Failed'
                using detail = 'Unable to schedule sms',
                      hint = _kickoff_validation_failure_message;
        end if;
    end if;

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function api.request_magic_link(text) to anon;

-- api: login with magic token
create or replace function api.login_with_magic_token(token text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _token_hash bytea := auth.hash_magic_token(token);
    _t auth.magic_login_token;
    _access_token text;
    _refresh_token text;
begin
    if token is null or btrim(token) = '' then
        raise exception 'Login Failed'
            using detail = 'Invalid Magic Link',
                  hint = 'missing_magic_link_token';
    end if;

    select t.*
    into _t
    from auth.magic_login_token t
    left join auth.magic_login_token_usage u on u.magic_login_token_id = t.magic_login_token_id
    where t.token_hash = _token_hash
      and u.magic_login_token_id is null
      and t.created_at >= now() - make_interval(secs => auth.magic_token_expiry_seconds())
    order by t.created_at desc
    limit 1;

    if _t.magic_login_token_id is null then
        raise exception 'Login Failed'
            using detail = 'Invalid Magic Link',
                  hint = 'invalid_magic_link';
    end if;

    perform auth.record_magic_login_token_usage(_t.magic_login_token_id);
    perform auth.record_account_login(_t.account_id);

    _access_token := auth.create_access_token(_t.account_id);
    _refresh_token := auth.create_refresh_token(_t.account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.login_with_magic_token(text) to anon;

-- templates (idempotent)
insert into comms.email_template (
    template_key,
    subject,
    body,
    body_params,
    description
)
values (
    'magic_login_link_email',
    'Sign in to Chatterbox',
    'Click to sign in: ${url}. Link expires in ${minutes} min.',
    array['url','minutes'],
    'Magic login link email template'
)
on conflict (template_key) do nothing;

insert into comms.sms_template (
    template_key,
    body,
    body_params,
    description
)
values (
    'magic_login_link_sms',
    'Sign in: ${url} (expires in ${minutes} min)',
    array['url','minutes'],
    'Magic login link sms template'
)
on conflict (template_key) do nothing;



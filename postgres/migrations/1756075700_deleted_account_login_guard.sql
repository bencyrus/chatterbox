-- Guard magic-link login flows for deleted accounts
-- - Adds helper to detect deleted accounts
-- - Seeds config for deleted-account support URL (from secrets)
-- - Exposes a helper to render a user-facing error message
-- - Updates api.request_magic_link and api.login_with_magic_token to block deleted accounts

-- =============================================================================
-- helpers: account deleted flag
-- =============================================================================

create or replace function accounts.is_account_deleted(
    _account_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from accounts.account_flag af
        where af.account_id = _account_id
          and af.flag = 'deleted'
    );
$$;


-- =============================================================================
-- config: base app URL (for public website)
-- =============================================================================

insert into internal.config (
    key,
    value
)
values (
    'app',
    '{
        "base_url": "{secrets.app_base_url}"
    }'
)
on conflict (key) do nothing;


-- =============================================================================
-- helper: render deleted-account login message
-- =============================================================================

create or replace function auth.deleted_account_login_message()
returns text
language sql
stable
as $$
    select coalesce(
        case
            when internal.get_config('app') ? 'base_url' then
                format(
                    'Your account was deleted. Visit %s/request-account-restore to contact support to reactivate your account.',
                    rtrim(internal.get_config('app')->>'base_url', '/')
                )
            else null
        end,
        'Your account was deleted. Visit https://chatterboxtalk.com/request-account-restore to contact support to reactivate your account.'
    );
$$;


-- =============================================================================
-- api: request magic link – block deleted accounts
-- =============================================================================

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
    _magic_link_base_url text := auth.magic_link_base_url();
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

    -- Block magic-link requests for deleted accounts
    if accounts.is_account_deleted((_account_result.account).account_id) then
        raise exception 'Request Magic Link Failed'
            using detail = auth.deleted_account_login_message(),
                  hint = 'account_deleted';
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


-- =============================================================================
-- api: login with magic token – block deleted accounts
-- =============================================================================

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

    -- Block magic-link logins for deleted accounts
    if accounts.is_account_deleted(_t.account_id) then
        raise exception 'Login Failed'
            using detail = auth.deleted_account_login_message(),
                  hint = 'account_deleted';
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


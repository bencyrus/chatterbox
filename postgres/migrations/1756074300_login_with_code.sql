-- seed login with code email template
insert into comms.email_template (
    template_key,
    subject,
    body,
    body_params,
    description
)
values (
    'login_with_code',
    'Your Chatterbox sign-in code: ${code}',
    'Your Chatterbox sign-in code is ${code}. Expires in ${minutes} min.',
    array['code', 'minutes'],
    'Login with code template'
)
on conflict (template_key) do nothing;

-- seed login with code sms template
insert into comms.sms_template (
    template_key,
    body,
    body_params,
    description
)
values (
    'login_with_code',
    'Your Chatterbox sign-in code is ${code}. Expires in ${minutes} min.',
    array['code', 'minutes'],
    'Login with code template'
)
on conflict (template_key) do nothing;

-- auth.code_expiry_minutes(): minutes a login code remains valid (defaults to 5 if config missing)
create or replace function auth.code_expiry_minutes()
returns integer
stable
language sql
as $$
    select coalesce((internal.get_config('login_with_code')->>'code_expiry_minutes')::int, 5);
$$;

-- auth.get_latest_unused_login_code_for_account: latest unused, unexpired code if exists
create or replace function auth.get_latest_unused_login_code_for_account(
    _account_id bigint
)
returns auth.login_code
stable
language sql
as $$
    select lc.*
    from auth.login_code lc
    left join auth.login_code_usage lcu on lcu.login_code_id = lc.login_code_id
    where lc.account_id = _account_id
      and lcu.login_code_id is null
      and lc.created_at >= now() - make_interval(mins => auth.code_expiry_minutes())
    order by lc.created_at desc
    limit 1;
$$;

-- auth.get_or_create_active_login_code_for_account: returns existing active code or creates a new one
create or replace function auth.get_or_create_active_login_code_for_account(
    _account_id bigint
)
returns auth.login_code
language plpgsql
security definer
as $$
declare
    _latest_unused_login_code auth.login_code;
    _code text;
begin
    _latest_unused_login_code := auth.get_latest_unused_login_code_for_account(_account_id);

    if _latest_unused_login_code.login_code_id is not null then
        return _latest_unused_login_code;
    end if;

    _code := auth.generate_login_code();

    insert into auth.login_code (account_id, code)
    values (_account_id, _code)
    returning *
    into _latest_unused_login_code;

    return _latest_unused_login_code;
end;
$$;

-- auth.record_login_code_usage: mark code as used
create or replace function auth.record_login_code_usage(
    _login_code_id bigint
)
returns void
language sql
as $$
    insert into auth.login_code_usage (login_code_id)
    values (_login_code_id);
$$;

-- auth.record_account_login: record account login
create or replace function auth.record_account_login(
    _account_id bigint
)
returns void
language sql
as $$
    insert into accounts.account_login (account_id)
    values (_account_id);
$$;

-- api.request_login_code: ensures account exists, creates or reuses code, and sends via channel
create or replace function api.request_login_code(identifier text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _identifier_type_result record := accounts.get_account_identifier_type($1);
    _get_or_create_account_result record;
    _login_code auth.login_code;
    _code_expiry_minutes integer := auth.code_expiry_minutes();
    _render_email record;
    _sms_body text;
    _kickoff_validation_failure_message text;
begin
    if _identifier_type_result.validation_failure_message is not null then
        raise exception 'Request Login Code Failed'
            using detail = 'Invalid Identifier',
                  hint = _identifier_type_result.validation_failure_message;
    end if;

    _get_or_create_account_result := accounts.get_or_create_account_by_identifier($1);
    if _get_or_create_account_result.validation_failure_message is not null then
        raise exception 'Request Login Code Failed'
            using detail = 'Account Error',
                  hint = _get_or_create_account_result.validation_failure_message;
    end if;

    _login_code := auth.get_or_create_active_login_code_for_account((_get_or_create_account_result.account).account_id);

    if _identifier_type_result.identifier_type = 'email' then
        _render_email := comms.render_email_template(
            'login_with_code',
            jsonb_build_object('code', _login_code.code, 'minutes', _code_expiry_minutes)
        );

        if _render_email.subject is null or _render_email.body is null then
            raise exception 'Request Login Code Failed'
                using detail = 'Email template not found',
                      hint = 'email_template_not_found';
        end if;

        _kickoff_validation_failure_message := comms.create_and_kickoff_email_task(
            comms.from_email_address('noreply'),
            (_get_or_create_account_result.account).email,
            _render_email.subject,
            _render_email.body,
            now()
        );

        if _kickoff_validation_failure_message is not null then
            raise exception 'Request Login Code Failed'
                using detail = 'Unable to schedule email',
                      hint = _kickoff_validation_failure_message;
        end if;
    else
        _sms_body := comms.render_sms_template(
            'login_with_code',
            jsonb_build_object('code', _login_code.code, 'minutes', _code_expiry_minutes)
        );

        if _sms_body is null then
            raise exception 'Request Login Code Failed'
                using detail = 'SMS template not found',
                      hint = 'sms_template_not_found';
        end if;

        _kickoff_validation_failure_message := comms.create_and_kickoff_sms_task(
            (_get_or_create_account_result.account).phone_number,
            _sms_body,
            now()
        );

        if _kickoff_validation_failure_message is not null then
            raise exception 'Request Login Code Failed'
                using detail = 'Unable to schedule sms',
                      hint = _kickoff_validation_failure_message;
        end if;
    end if;

    return jsonb_build_object('success', true);
end;
$$;

grant execute on function api.request_login_code(text) to anon;

-- api.login_with_code: verifies code for account, records usage/failures, returns tokens
create or replace function api.login_with_code(identifier text, code text)
returns jsonb
language plpgsql
security definer
as $$
declare
    _identifier_type_result record := accounts.get_account_identifier_type($1);
    _account accounts.account;
    _latest_unused_login_code auth.login_code;
    _access_token text;
    _refresh_token text;
begin
    if _identifier_type_result.validation_failure_message is not null then
        raise exception 'Login Failed'
            using detail = 'Invalid Identifier',
                  hint = _identifier_type_result.validation_failure_message;
    end if;

    if _identifier_type_result.identifier_type = 'email' then
        _account := accounts.get_account_by_email($1);
    else
        _account := accounts.get_account_by_phone_number($1);
    end if;

    if _account.account_id is null then
        raise exception 'Login Failed'
            using detail = 'Invalid Credentials',
                  hint = 'account_not_found';
    end if;

    _latest_unused_login_code := auth.get_latest_unused_login_code_for_account(_account.account_id);

    if _latest_unused_login_code.login_code_id is null
        or _latest_unused_login_code.code is distinct from $2 then
        raise exception 'Login Failed'
            using detail = 'Invalid Login Code',
                  hint = 'invalid_login_code';
    end if;

    perform auth.record_login_code_usage(_latest_unused_login_code.login_code_id);

    perform auth.record_account_login(_account.account_id);

    _access_token := auth.create_access_token(_account.account_id);
    _refresh_token := auth.create_refresh_token(_account.account_id);

    return jsonb_build_object(
        'access_token', _access_token,
        'refresh_token', _refresh_token
    );
end;
$$;

grant execute on function api.login_with_code(text, text) to anon;

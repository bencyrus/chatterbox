-- schema: learning profiles and cue exposure facts
create schema if not exists learning;

-- table: per-account, per-language learning profile
create table if not exists learning.profile (
    profile_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    language_code languages.language_code not null,
    created_at timestamp with time zone not null default now(),
    constraint profile_unique_account_language unique (account_id, language_code)
);

-- table: fact table recording when a profile sees a specific cue content
create table if not exists learning.cue_seen (
    cue_seen_id bigserial primary key,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    cue_content_id bigint not null references cues.cue_content(cue_content_id) on delete cascade,
    seen_at timestamp with time zone not null default now()
);

-- table: fact table recording when an account switches its active learning profile
create table if not exists learning.active_profile (
    account_active_profile_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

create or replace function learning.get_or_create_account_profile(
    _account_id bigint,
    _language_code languages.language_code,
    out validation_failure_message text,
    out profile learning.profile
)
returns record
language plpgsql
security definer
as $$
begin
    if _account_id is null then
        validation_failure_message := 'account_id_missing';
        return;
    end if;

    if _language_code is null then
        validation_failure_message := 'language_code_missing';
        return;
    end if;

    insert into learning.profile (account_id, language_code)
    values (_account_id, _language_code)
    on conflict (account_id, language_code) do update
    set account_id = excluded.account_id
    returning *
    into profile;

    return;
end;
$$;

create or replace function api.get_or_create_account_profile(
    account_id bigint,
    language_code languages.language_code
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _get_or_create_account_profile_result record;
begin
    if _authenticated_account_id is null or _authenticated_account_id <> account_id then
        raise exception 'Get or Create Account Profile Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_or_create_account_profile';
    end if;

    _get_or_create_account_profile_result := learning.get_or_create_account_profile(account_id, language_code);
    if _get_or_create_account_profile_result.validation_failure_message is not null then
        raise exception 'Get or Create Account Profile Failed'
            using detail = 'Invalid Input',
                  hint = _get_or_create_account_profile_result.validation_failure_message;
    end if;

    return to_jsonb(_get_or_create_account_profile_result.profile);
end;
$$;   

grant execute on function api.get_or_create_account_profile(bigint, languages.language_code) to authenticated;

create or replace function learning.profile_by_id(
    _profile_id bigint
)
returns learning.profile
language sql
stable
as $$
    select *
    from learning.profile
    where profile_id = _profile_id
$$;

create or replace function learning.set_active_profile(
    _account_id bigint,
    _profile_id bigint,
    out validation_failure_message text,
    out active_profile learning.active_profile
)
returns record
language plpgsql
security definer
as $$
begin
    if _account_id is null then
        validation_failure_message := 'account_id_missing';
        return;
    end if;

    if _profile_id is null then
        validation_failure_message := 'profile_id_missing';
        return;
    end if;

    insert into learning.active_profile (account_id, profile_id)
    values (_account_id, _profile_id)
    returning *
    into active_profile;

    if not found then
        validation_failure_message := 'profile_not_found';
        return;
    end if;

    return;
end;
$$;

create or replace function learning.active_profile_summary_by_account_id(
    _account_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'account_id', ap.account_id,
        'profile_id', ap.profile_id,
        'language_code', p.language_code
    )
    from learning.active_profile ap
    join learning.profile p
        on p.profile_id = ap.profile_id
    where ap.account_id = _account_id
    order by ap.created_at desc
    limit 1;
$$;

create or replace function api.set_active_profile(
    account_id bigint,
    language_code languages.language_code
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _get_or_create_account_profile_result record; -- OUT: validation_failure_message text, profile learning.profile
    _set_active_profile_result record; -- OUT: validation_failure_message text, active_profile learning.active_profile
begin
    if _authenticated_account_id is null or _authenticated_account_id <> account_id then
        raise exception 'Set Active Profile Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_set_active_profile';
    end if;

    _get_or_create_account_profile_result := learning.get_or_create_account_profile(account_id, language_code);
    if _get_or_create_account_profile_result.validation_failure_message is not null then
        raise exception 'Set Active Profile Failed'
            using detail = 'Invalid Profile',
                  hint = _get_or_create_account_profile_result.validation_failure_message;
    end if;

    _set_active_profile_result := learning.set_active_profile(
        account_id,
        (_get_or_create_account_profile_result.profile).profile_id
    );

    if _set_active_profile_result.validation_failure_message is not null then
        raise exception 'Set Active Profile Failed'
            using detail = 'Invalid Input',
                  hint = _set_active_profile_result.validation_failure_message;
    end if;

    return to_jsonb(_set_active_profile_result.active_profile);
end;
$$;

grant execute on function api.set_active_profile(bigint, languages.language_code) to authenticated;

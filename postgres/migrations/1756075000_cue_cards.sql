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

-- schema: language codes used for cue content and learning profiles
create schema if not exists languages;
grant usage on schema languages to authenticated;

create domain languages.language_code as text
    check (value in ('en','de','fr'));

-- schema: cue cards and their localized content
create schema if not exists cues;
grant usage on schema cues to authenticated;

create domain cues.cue_stage as text
    check (value in ('draft', 'published', 'archived'));

-- table: root cue card (language-independent metadata)
create table if not exists cues.cue (
    cue_id bigserial primary key,
    stage cues.cue_stage not null default 'draft',
    created_at timestamp with time zone not null default now(),
    created_by bigint not null references accounts.account(account_id) on delete cascade
);

-- table: localized cue content for a cue (one row per language)
create table if not exists cues.cue_content (
    cue_content_id bigserial primary key,
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    title text not null,
    details text not null,
    language_code languages.language_code not null,
    created_at timestamp with time zone not null default now(),
    constraint cue_content_unique unique (cue_id, language_code)
);

-- function: normalize cue + content into a consistent jsonb representation
create or replace function cues.build_cue_with_content(
    _cue cues.cue,
    _content cues.cue_content
)
returns jsonb
language sql
stable
as $$
    select to_jsonb(_cue)
           || jsonb_build_object('content', to_jsonb(_content));
$$;

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

-- function: create a cue and its localized content with validation
create or replace function cues.create_cue(
    _created_by bigint,
    _title text,
    _details text,
    _language_code languages.language_code,
    _stage cues.cue_stage,
    out validation_failure_message text,
    out result jsonb
)
returns record
language plpgsql
security definer
as $$
declare
    _created_cue cues.cue;
    _created_cue_content cues.cue_content;
    _normalized_title text := btrim(_title);
    _normalized_details text := btrim(_details);
    _normalized_language_code languages.language_code := btrim(_language_code);
    _normalized_stage cues.cue_stage := btrim(_stage);
begin
    if _created_by is null then
        validation_failure_message := 'created_by_missing';
        return;
    end if;

    if _normalized_title is null or _normalized_title = '' then
        validation_failure_message := 'title_missing';
        return;
    end if;

    if _normalized_details is null or _normalized_details = '' then
        validation_failure_message := 'details_missing';
        return;
    end if;

    if _normalized_language_code is null or _normalized_language_code = '' then
        validation_failure_message := 'language_code_missing';
        return;
    end if;

    if _normalized_stage is null or _normalized_stage = '' then
        validation_failure_message := 'stage_missing';
        return;
    end if;

    insert into cues.cue (stage, created_by)
    values (_normalized_stage, _created_by)
    returning *
    into _created_cue;

    insert into cues.cue_content (cue_id, title, details, language_code)
    values (_created_cue.cue_id, _normalized_title, _normalized_details, _normalized_language_code)
    returning *
    into _created_cue_content;

    result := cues.build_cue_with_content(_created_cue, _created_cue_content);

    return;
end;
$$;

-- api: create a cue for the current creator account
create or replace function api.create_cue(
    title text,
    details text,
    language_code languages.language_code
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _current_account_id bigint := auth.jwt_account_id();
    _is_creator boolean := auth.is_creator_account(_current_account_id);
    _create_cue_result record; -- OUT: validation_failure_message text, result jsonb
begin
    if not _is_creator then
        raise exception 'Create Cue Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_create_cue';
    end if;

    _create_cue_result := cues.create_cue(_current_account_id, title, details, language_code, 'draft');

    if _create_cue_result.validation_failure_message is not null then
        raise exception 'Create Cue Failed'
            using detail = 'Invalid Input',
                  hint = _create_cue_result.validation_failure_message;
    end if;

    return _create_cue_result.result;
end;
$$;

grant execute on function api.create_cue(text, text, languages.language_code) to authenticated;

create or replace function cues.update_cue_stage(
    _cue_id bigint,
    _stage cues.cue_stage,
    out validation_failure_message text,
    out cue cues.cue
)
returns record
language plpgsql
security invoker
as $$
begin
    if _cue_id is null then
        validation_failure_message := 'cue_id_missing';
        return;
    end if;

    if _stage is null or _stage = '' then
        validation_failure_message := 'stage_missing';
        return;
    end if;

    update cues.cue c
    set stage = _stage
    where c.cue_id = _cue_id
    returning *
    into cue;

    if not found then
        validation_failure_message := 'cue_not_found';
        return;
    end if;

    return;
end;
$$;

create or replace function api.update_cue_stage(
    cue_id bigint,
    stage cues.cue_stage
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _update_cue_stage_result record; -- OUT: validation_failure_message text, cue cues.cue
begin
    if not auth.is_creator_account(auth.jwt_account_id()) then
        raise exception 'Update Cue Stage Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_update_cue_stage';
    end if;

    _update_cue_stage_result := cues.update_cue_stage(cue_id, stage);
    if _update_cue_stage_result.validation_failure_message is not null then
        raise exception 'Update Cue Stage Failed'
            using detail = 'Invalid Input',
                  hint = _update_cue_stage_result.validation_failure_message;
    end if;

    return to_jsonb(_update_cue_stage_result.cue);
end;
$$;

grant execute on function api.update_cue_stage(bigint, cues.cue_stage) to authenticated;

-- function: select and record a weighted-random batch of cues for a profile
create or replace function cues.shuffle_cues(
    _profile_id bigint,
    _language_code languages.language_code,
    _count integer,
    out validation_failure_message text,
    out result jsonb
)
returns record
language plpgsql
security definer
as $$
declare
    -- normalize count to [1, 100], defaulting to 10 when null
    _normalized_count integer := least(greatest(1, coalesce(_count, 10)), 100);
begin
    if _profile_id is null then
        validation_failure_message := 'profile_id_missing';
        return;
    end if;

    if _language_code is null then
        validation_failure_message := 'language_code_missing';
        return;
    end if;

    with candidate_cues as (
        select
            cc.cue_id,
            cc.cue_content_id,
            coalesce(count(cs.cue_seen_id), 0) as times_seen,
            -- cues seen more often get a larger weight and are less likely, but still possible
            random() * (1 + coalesce(count(cs.cue_seen_id), 0)) as weight
        from cues.cue c
        join cues.cue_content cc
            on cc.cue_id = c.cue_id
            and cc.language_code = _language_code
        left join learning.cue_seen cs
            on cs.cue_content_id = cc.cue_content_id
           and cs.profile_id = _profile_id
        where c.stage = 'published'
        group by cc.cue_id, cc.cue_content_id
        order by weight
        limit _normalized_count
    ),
    inserted as (
        insert into learning.cue_seen (profile_id, cue_id, cue_content_id)
        select _profile_id, cue_id, cue_content_id
        from candidate_cues
        returning cue_id, cue_content_id
    )
    select coalesce(
        jsonb_agg(
            cues.build_cue_with_content(c, cc)
        ),
        '[]'::jsonb
    )
    into result
    from inserted
    join cues.cue_content cc
        on cc.cue_content_id = inserted.cue_content_id
    join cues.cue c
        on c.cue_id = inserted.cue_id;

    return;
end;
$$;

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

-- api: shuffle cues for a given profile and return the batch
create or replace function api.shuffle_cues(
    profile_id bigint,
    count integer
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _shuffle_cues_result record; -- OUT: validation_failure_message text, result jsonb
    _profile learning.profile := learning.profile_by_id(profile_id);
    _authenticated_account_id bigint := auth.jwt_account_id();
    _normalized_count integer := least(greatest(1, coalesce(count, 10)), 100);
begin
    if _authenticated_account_id is null then
        raise exception 'Shuffle Cues Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_shuffle_cues';
    end if;

    if _profile.profile_id is null then
        raise exception 'Shuffle Cues Failed'
            using detail = 'Invalid Profile',
                  hint = 'profile_not_found';
    end if;

    if _profile.account_id is not null and _profile.account_id <> _authenticated_account_id then
        raise exception 'Shuffle Cues Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_shuffle_cues';
    end if;

    _shuffle_cues_result := cues.shuffle_cues(_profile.profile_id, _profile.language_code, _normalized_count);
    if _shuffle_cues_result.validation_failure_message is not null then
        raise exception 'Shuffle Cues Failed'
            using detail = 'Invalid Profile',
                  hint = _shuffle_cues_result.validation_failure_message;
    end if;

    return _shuffle_cues_result.result;
end;
$$;

grant execute on function api.shuffle_cues(bigint, integer) to authenticated;

-- function: get recent cues for a profile and top up with shuffled ones if needed
create or replace function cues.get_cues(
    _profile_id bigint,
    _language_code languages.language_code,
    _count integer,
    out validation_failure_message text,
    out result jsonb
)
returns record
language plpgsql
security definer
as $$
declare
    -- normalize count to [1, 100], defaulting to 10 when null
    _normalized_count integer := least(greatest(1, coalesce(_count, 10)), 100);
    _existing_items jsonb := '[]'::jsonb;
    _existing_count integer := 0;
    _remaining integer;
    _shuffle_result record;
begin
    if _profile_id is null then
        validation_failure_message := 'profile_id_missing';
        return;
    end if;

    if _language_code is null then
        validation_failure_message := 'profile_not_found';
        return;
    end if;

    -- fetch up to _normalized_count most recently seen published cues for this profile
    with recent_seen as (
        select
            cs.seen_at,
            c as cue,
            cc as cue_content
        from learning.cue_seen cs
        join cues.cue_content cc
            on cc.cue_content_id = cs.cue_content_id
        join cues.cue c
            on c.cue_id = cc.cue_id
        where cs.profile_id = _profile_id
          and c.stage = 'published'
        order by cs.seen_at desc
        limit _normalized_count
    )
    select
        coalesce(
            jsonb_agg(
                cues.build_cue_with_content(recent_seen.cue, recent_seen.cue_content)
                order by recent_seen.seen_at desc
            ),
            '[]'::jsonb
        ),
        count(*)
    into _existing_items, _existing_count
    from recent_seen;

    if _existing_count = _normalized_count then
        result := _existing_items;
        return;
    end if;

    _remaining := _normalized_count - _existing_count;

    -- top up with shuffled cues for this profile
    _shuffle_result := cues.shuffle_cues(_profile_id, _language_code, _remaining);

    if _shuffle_result.validation_failure_message is not null then
        validation_failure_message := _shuffle_result.validation_failure_message;
        return;
    end if;

    result := _existing_items || coalesce(_shuffle_result.result, '[]'::jsonb);
    return;
end;
$$;

-- api: get cues for a given profile, including recent and shuffled
create or replace function api.get_cues(
    profile_id bigint,
    count integer
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _get_cues_result record; -- OUT: validation_failure_message text, result jsonb
    _profile learning.profile := learning.profile_by_id(profile_id);
    _authenticated_account_id bigint := auth.jwt_account_id();
    _normalized_count integer := least(greatest(1, coalesce(count, 10)), 100);
begin
    if _authenticated_account_id is null then
        raise exception 'Get Cues Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_cues';
    end if;

    if _profile.profile_id is null then
        raise exception 'Get Cues Failed'
            using detail = 'Invalid Profile',
                  hint = 'profile_not_found';
    end if;

    if _profile.account_id is not null and _profile.account_id <> _authenticated_account_id then
        raise exception 'Get Cues Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_cues';
    end if;

    _get_cues_result := cues.get_cues(_profile.profile_id, _profile.language_code, _normalized_count);
    if _get_cues_result.validation_failure_message is not null then
        raise exception 'Get Cues Failed'
            using detail = 'Invalid Profile',
                  hint = _get_cues_result.validation_failure_message;
    end if;

    return _get_cues_result.result;
end;
$$;

grant execute on function api.get_cues(bigint, integer) to authenticated;

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

create or replace function api.app_config()
returns jsonb
language plpgsql
security definer
as $$
begin
    return jsonb_build_object(
        'default_profile_language_code', internal.get_config('default_profile_language_code'),
        'available_language_codes', internal.get_config('available_language_codes')
    );
end;
$$;

grant execute on function api.app_config() to anon, authenticated;
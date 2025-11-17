-- account role: to check if the account is allowed to create cue cards
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

-- auth helper: resolve account_id from JWT claim (PostgREST)
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

-- auth helper: see if the user is a creator
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

-- languages schema and domain
create schema if not exists languages;
grant usage on schema languages to authenticated;

create domain languages.language_code as text
    check (value in ('en','de','fr'));

-- learning schema: profiles, cycles, batches, facts
create schema if not exists learning;

create table if not exists learning.profile (
    profile_id bigserial primary key,
    account_id bigint not null references accounts.account(account_id) on delete cascade,
    language_code languages.language_code not null,
    created_at timestamp with time zone not null default now(),
    constraint profile_unique_account_language unique (account_id, language_code)
);

-- cues schema: cue cards and translations
create schema if not exists cues;

create domain cues.cue_stage as text
    check (value in ('draft', 'published', 'archived'));

create table if not exists cues.cue (
    cue_id bigserial primary key,
    stage cues.cue_stage not null default 'draft',
    created_at timestamp with time zone not null default now(),
    created_by bigint not null references accounts.account(account_id) on delete cascade
);

create table if not exists cues.cue_content (
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    title text not null,
    details text not null,
    language_code languages.language_code not null,
    created_at timestamp with time zone not null default now(),
    constraint cue_content_unique unique (cue_id, language_code)
);

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
    _created_cue record;
    _created_cue_content record;
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
    returning * into _created_cue;

    insert into cues.cue_content (cue_id, title, details, language_code)
    values (_created_cue.cue_id, _normalized_title, _normalized_details, _normalized_language_code)
    returning * into _created_cue_content;

    result := to_jsonb(_created_cue) || jsonb_build_object(
        'content', to_jsonb(_created_cue_content)
    );

    return;
end;
$$;

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
    _create_cue_result record;
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
-- function: create a cue and its localized content with validation
create or replace function cues.create_cue(
    _created_by bigint,
    _title text,
    _details text,
    _language_code languages.language_code,
    _stage cues.stage,
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
    _normalized_stage cues.stage := btrim(_stage);
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

    insert into cues.cue (created_by)
    values (_created_by)
    returning *
    into _created_cue;

    -- record initial stage
    insert into cues.cue_stage (cue_id, stage, created_by)
    values (_created_cue.cue_id, _normalized_stage, _created_by);

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
    _stage cues.stage,
    _created_by bigint,
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

    if _created_by is null then
        validation_failure_message := 'created_by_missing';
        return;
    end if;

    -- verify cue exists
    select *
    into cue
    from cues.cue c
    where c.cue_id = _cue_id;

    if not found then
        validation_failure_message := 'cue_not_found';
        return;
    end if;

    -- insert new stage record
    insert into cues.cue_stage (cue_id, stage, created_by)
    values (_cue_id, _stage, _created_by);

    return;
end;
$$;

create or replace function api.update_cue_stage(
    cue_id bigint,
    stage cues.stage
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _update_cue_stage_result record; -- OUT: validation_failure_message text, cue cues.cue
begin
    if not auth.is_creator_account(_authenticated_account_id) then
        raise exception 'Update Cue Stage Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_update_cue_stage';
    end if;

    _update_cue_stage_result := cues.update_cue_stage(cue_id, stage, _authenticated_account_id);
    if _update_cue_stage_result.validation_failure_message is not null then
        raise exception 'Update Cue Stage Failed'
            using detail = 'Invalid Input',
                  hint = _update_cue_stage_result.validation_failure_message;
    end if;

    return to_jsonb(_update_cue_stage_result.cue);
end;
$$;

grant execute on function api.update_cue_stage(bigint, cues.stage) to authenticated;

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
        where cues.current_stage(c.cue_id) = 'published'
        group by cc.cue_id, cc.cue_content_id
        order by weight
        limit _normalized_count
    ),
    inserted as (
        insert into learning.cue_seen (profile_id, cue_id, cue_content_id)
        select _profile_id, cue_id, cue_content_id
        from candidate_cues
        returning cue_seen_id, cue_id, cue_content_id, seen_at
    )
    select coalesce(
        jsonb_agg(
            cues.build_cue_with_content(c, cc)
            order by inserted.seen_at desc, inserted.cue_id
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

-- function: get recent cues for a profile or shuffle if none exist
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

    -- fetch up to _normalized_count distinct recently seen published cues for this profile
    with recent_seen as (
        select
            cs.seen_at,
            c as cue,
            cc as cue_content,
            c.cue_id,
            -- rank multiple viewings of the same cue for this profile, most recent first
            row_number() over (
                partition by c.cue_id
                order by cs.seen_at desc
            ) as occurrence_rank,
            -- rank distinct cues by most recent seen_at (and cue_id as a stable tie-breaker)
            row_number() over (
                order by cs.seen_at desc, c.cue_id
            ) as recency_rank
        from learning.cue_seen cs
        join cues.cue_content cc
            on cc.cue_content_id = cs.cue_content_id
        join cues.cue c
            on c.cue_id = cc.cue_id
        where cs.profile_id = _profile_id
          and cues.current_stage(c.cue_id) = 'published'
    )
    select
        coalesce(
            jsonb_agg(
                cues.build_cue_with_content(recent_seen.cue, recent_seen.cue_content)
                order by recent_seen.seen_at desc, recent_seen.cue_id
            ),
            '[]'::jsonb
        )
    into result
    from recent_seen
    where occurrence_rank = 1
      and recency_rank <= _normalized_count;

    -- if we found any recent cues, return them
    if jsonb_array_length(result) > 0 then
        return;
    end if;

    -- no recent cues exist, shuffle to get fresh ones
    _shuffle_result := cues.shuffle_cues(_profile_id, _language_code, _normalized_count);

    if _shuffle_result.validation_failure_message is not null then
        validation_failure_message := _shuffle_result.validation_failure_message;
        return;
    end if;

    result := coalesce(_shuffle_result.result, '[]'::jsonb);
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

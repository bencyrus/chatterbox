-- schema: recording upload intents and associations
grant usage on schema files to authenticated;

-- table: upload intent for user recordings
create table if not exists files.upload_intent (
    upload_intent_id bigserial primary key,
    object_key text not null unique,
    bucket text not null,
    mime_type files.mime_type not null,
    created_at timestamp with time zone not null default now(),
    created_by bigint not null references accounts.account(account_id) on delete cascade
);

-- table: user recording upload intent metadata
create table if not exists learning.user_recording_upload_intent (
    user_recording_upload_intent_id bigserial primary key,
    upload_intent_id bigint not null unique references files.upload_intent(upload_intent_id) on delete cascade,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- table: link recordings to learning profiles and cue cards
create table if not exists learning.profile_cue_recording (
    profile_cue_recording_id bigserial primary key,
    profile_id bigint not null references learning.profile(profile_id) on delete cascade,
    cue_id bigint not null references cues.cue(cue_id) on delete cascade,
    file_id bigint not null references files.file(file_id) on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- function: convert mime type to file extension
create or replace function files.mime_type_to_extension(
    _mime_type files.mime_type
)
returns text
language sql
immutable
as $$
    select case _mime_type
        when 'audio/mp4' then 'm4a'
        when 'image/jpeg' then 'jpg'
        when 'image/png' then 'png'
        else 'bin'
    end;
$$;

-- function: generate object key for user recordings
create or replace function files.generate_user_recording_object_key(
    _profile_id bigint,
    _cue_id bigint,
    _mime_type files.mime_type
)
returns text
language sql
stable
as $$
    select 'user-recordings/'
        || 'p-'
        || _profile_id::text
        || '-c-'
        || _cue_id::text
        || '-t-'
        || extract(epoch from now())::bigint::text
        || '.'
        || files.mime_type_to_extension(_mime_type);
$$;

-- function: lookup upload intent details for file service
create or replace function files.lookup_upload_intent(
    _upload_intent_id bigint
)
returns jsonb
language sql
stable
security definer
as $$
    select jsonb_build_object(
        'upload_intent_id', ui.upload_intent_id,
        'bucket', ui.bucket,
        'object_key', ui.object_key,
        'mime_type', ui.mime_type
    )
    from files.upload_intent ui
    where ui.upload_intent_id = _upload_intent_id;
$$;

grant execute on function files.lookup_upload_intent(bigint) to file_service_user;

-- function: get cue info by id with optional content
create or replace function cues.cue_info_by_id(
    _cue_id bigint,
    _include_content boolean default false,
    _language_code languages.language_code default null
)
returns jsonb
language plpgsql
stable
as $$
declare
    _cue cues.cue;
    _cue_content cues.cue_content;
begin
    select *
    into _cue
    from cues.cue
    where cue_id = _cue_id;

    if not found then
        return null;
    end if;

    if _include_content and _language_code is not null then
        select *
        into _cue_content
        from cues.cue_content
        where cue_id = _cue_id
          and language_code = _language_code;
    end if;

    return to_jsonb(_cue) || jsonb_build_object('content', coalesce(to_jsonb(_cue_content), 'null'::jsonb));
end;
$$;

-- function: create recording upload intent
create or replace function learning.create_recording_upload_intent(
    _profile_id bigint,
    _cue_id bigint,
    _mime_type files.mime_type,
    _created_by bigint,
    out validation_failure_message text,
    out upload_intent_id bigint
)
returns record
language plpgsql
security definer
as $$
declare
    _object_key text;
    _bucket text := files.gcs_bucket();
    _profile learning.profile;
    _cue_info jsonb;
    _upload_intent_id bigint;
begin
    if _profile_id is null then
        validation_failure_message := 'profile_id_missing';
        return;
    end if;

    if _cue_id is null then
        validation_failure_message := 'cue_id_missing';
        return;
    end if;

    if _mime_type is null then
        validation_failure_message := 'mime_type_missing';
        return;
    end if;

    if _mime_type <> 'audio/mp4' then
        validation_failure_message := 'invalid_mime_type_for_recording';
        return;
    end if;

    if _created_by is null then
        validation_failure_message := 'created_by_missing';
        return;
    end if;

    -- verify profile exists
    _profile := learning.profile_by_id(_profile_id);
    if _profile.profile_id is null then
        validation_failure_message := 'profile_not_found';
        return;
    end if;

    -- verify cue exists and is published
    _cue_info := cues.cue_info_by_id(_cue_id);
    if _cue_info is null or (_cue_info->>'stage') <> 'published' then
        validation_failure_message := 'cue_not_found_or_not_published';
        return;
    end if;

    _object_key := files.generate_user_recording_object_key(_profile_id, _cue_id, _mime_type);

    insert into files.upload_intent (
        object_key,
        bucket,
        mime_type,
        created_by
    )
    values (
        _object_key,
        _bucket,
        _mime_type,
        _created_by
    )
    returning files.upload_intent.upload_intent_id
    into _upload_intent_id;

    -- store recording-specific metadata
    insert into learning.user_recording_upload_intent (
        upload_intent_id,
        profile_id,
        cue_id
    )
    values (
        _upload_intent_id,
        _profile_id,
        _cue_id
    );

    upload_intent_id := _upload_intent_id;
    return;
end;
$$;

-- api: create recording upload intent
create or replace function api.create_recording_upload_intent(
    profile_id bigint,
    cue_id bigint,
    mime_type files.mime_type
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _profile learning.profile := learning.profile_by_id(profile_id);
    _create_intent_result record;
begin
    if _authenticated_account_id is null then
        raise exception 'Create Recording Upload Intent Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_create_recording_upload_intent';
    end if;

    if _profile.profile_id is null then
        raise exception 'Create Recording Upload Intent Failed'
            using detail = 'Invalid Profile',
                  hint = 'profile_not_found';
    end if;

    if _profile.account_id <> _authenticated_account_id then
        raise exception 'Create Recording Upload Intent Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_create_recording_upload_intent';
    end if;

    _create_intent_result := learning.create_recording_upload_intent(
        profile_id,
        cue_id,
        mime_type,
        _authenticated_account_id
    );

    if _create_intent_result.validation_failure_message is not null then
        raise exception 'Create Recording Upload Intent Failed'
            using detail = 'Invalid Input',
                  hint = _create_intent_result.validation_failure_message;
    end if;

    return jsonb_build_object(
        'upload_intent_id', _create_intent_result.upload_intent_id
    );
end;
$$;

grant execute on function api.create_recording_upload_intent(bigint, bigint, files.mime_type) to authenticated;

-- function: find existing profile_cue_recording for an upload intent (for idempotency)
create or replace function learning.profile_cue_recording_by_upload_intent(
    _object_key text,
    _profile_id bigint,
    _cue_id bigint
)
returns learning.profile_cue_recording
language sql
stable
as $$
    select pcr.*
    from learning.profile_cue_recording pcr
    join files.file f
        on f.file_id = pcr.file_id
    where f.object_key = _object_key
      and pcr.profile_id = _profile_id
      and pcr.cue_id = _cue_id;
$$;

-- function: get file details for UI display
create or replace function files.file_details(
    _file_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'file_id', f.file_id,
        'created_at', f.created_at,
        'mime_type', f.mime_type,
        'metadata', coalesce(
            (
                select jsonb_object_agg(fm.key, fm.value)
                from files.file_metadata fm
                where fm.file_id = f.file_id
            ),
            '{}'::jsonb
        )
    )
    from files.file f
    where f.file_id = _file_id;
$$;

-- function: create file metadata from json (only valid keys)
create or replace function files.create_file_metadata(
    _file_id bigint,
    _metadata jsonb
)
returns void
language plpgsql
as $$
declare
    _key text;
    _value jsonb;
begin
    if _metadata is null or _metadata = 'null'::jsonb then
        return;
    end if;

    -- iterate through all keys in the metadata json
    for _key, _value in select * from jsonb_each(_metadata)
    loop
        -- only insert if the key is a valid metadata_key
        begin
            insert into files.file_metadata (
                file_id,
                key,
                value
            )
            values (
                _file_id,
                _key::files.metadata_key,
                _value
            )
            on conflict (file_id, key) do update
                set value = excluded.value;
        exception
            when check_violation then
                -- silently skip invalid keys
                continue;
        end;
    end loop;
end;
$$;

-- function: complete recording upload
create or replace function learning.complete_recording_upload(
    _upload_intent_id bigint,
    _account_id bigint,
    _metadata jsonb default null,
    out validation_failure_message text,
    out profile_cue_recording learning.profile_cue_recording
)
returns record
language plpgsql
security definer
as $$
declare
    _upload_intent files.upload_intent;
    _recording_upload_intent learning.user_recording_upload_intent;
    _file_id bigint;
begin
    if _upload_intent_id is null then
        validation_failure_message := 'upload_intent_id_missing';
        return;
    end if;

    if _account_id is null then
        validation_failure_message := 'account_id_missing';
        return;
    end if;

    -- fetch the upload intent
    select *
    into _upload_intent
    from files.upload_intent
    where upload_intent_id = _upload_intent_id;

    if not found then
        validation_failure_message := 'upload_intent_not_found';
        return;
    end if;

    -- verify ownership
    if _upload_intent.created_by <> _account_id then
        validation_failure_message := 'unauthorized_to_complete_upload';
        return;
    end if;

    -- fetch recording-specific metadata
    select *
    into _recording_upload_intent
    from learning.user_recording_upload_intent
    where upload_intent_id = _upload_intent_id;

    if not found then
        validation_failure_message := 'recording_upload_intent_not_found';
        return;
    end if;

    -- check if already completed (idempotent)
    profile_cue_recording := learning.profile_cue_recording_by_upload_intent(
        _upload_intent.object_key,
        _recording_upload_intent.profile_id,
        _recording_upload_intent.cue_id
    );
    if profile_cue_recording.profile_cue_recording_id is not null then
        return;
    end if;

    -- create file record
    insert into files.file (
        bucket,
        object_key,
        mime_type
    )
    values (
        _upload_intent.bucket,
        _upload_intent.object_key,
        _upload_intent.mime_type
    )
    returning file_id
    into _file_id;

    -- create file metadata (only valid keys)
    if _metadata is not null then
        perform files.create_file_metadata(_file_id, _metadata);
    end if;

    -- create profile_cue_recording link
    insert into learning.profile_cue_recording (
        profile_id,
        cue_id,
        file_id
    )
    values (
        _recording_upload_intent.profile_id,
        _recording_upload_intent.cue_id,
        _file_id
    )
    returning *
    into profile_cue_recording;

    return;
end;
$$;

-- api: complete recording upload
create or replace function api.complete_recording_upload(
    upload_intent_id bigint,
    metadata jsonb default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _complete_result record;
    _file_id bigint;
begin
    if _authenticated_account_id is null then
        raise exception 'Complete Recording Upload Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_complete_recording_upload';
    end if;

    _complete_result := learning.complete_recording_upload(
        upload_intent_id,
        _authenticated_account_id,
        metadata
    );

    if _complete_result.validation_failure_message is not null then
        raise exception 'Complete Recording Upload Failed'
            using detail = 'Invalid Input',
                  hint = _complete_result.validation_failure_message;
    end if;

    _file_id := (_complete_result.profile_cue_recording).file_id;

    return jsonb_build_object(
        'success', true,
        'file', files.file_details(_file_id),
        'files', jsonb_build_array(_file_id)
    );
end;
$$;

grant execute on function api.complete_recording_upload(bigint, jsonb) to authenticated;

-- function: get cue recording history for a profile
create or replace function learning.cue_recording_history_for_profile(
    _profile_id bigint,
    _cue_id bigint
)
returns jsonb
language sql
stable
as $$
    select coalesce(
        (
            select jsonb_agg(
                to_jsonb(pcr) || jsonb_build_object(
                    'file', files.file_details(pcr.file_id)
                )
                order by pcr.created_at desc
            )
            from learning.profile_cue_recording pcr
            where pcr.profile_id = _profile_id
              and pcr.cue_id = _cue_id
        ),
        '[]'::jsonb
    );
$$;

-- function: get cue details scoped to a profile with recording history
create or replace function learning.cue_with_recordings_for_profile(
    _profile_id bigint,
    _cue_id bigint
)
returns jsonb
language sql
stable
as $$
    select cues.cue_info_by_id(
        _cue_id,
        true,
        p.language_code
    ) || jsonb_build_object(
        'recordings', learning.cue_recording_history_for_profile(_profile_id, _cue_id)
    )
    from learning.profile p
    where p.profile_id = _profile_id;
$$;

-- api: get cue for profile with recording history
create or replace function api.get_cue_for_profile(
    profile_id bigint,
    cue_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _profile learning.profile := learning.profile_by_id(profile_id);
    _cue_with_recordings jsonb;
    _file_ids bigint[];
begin
    if _authenticated_account_id is null then
        raise exception 'Get Cue For Profile Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_cue_for_profile';
    end if;

    if _profile.profile_id is null then
        raise exception 'Get Cue For Profile Failed'
            using detail = 'Invalid Profile',
                  hint = 'profile_not_found';
    end if;

    if _profile.account_id <> _authenticated_account_id then
        raise exception 'Get Cue For Profile Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_cue_for_profile';
    end if;

    _cue_with_recordings := learning.cue_with_recordings_for_profile(profile_id, cue_id);

    -- extract file IDs from recordings for gateway download URL injection
    select array_agg((rec->>'file_id')::bigint)
    into _file_ids
    from jsonb_array_elements(_cue_with_recordings->'recordings') as rec;

    return jsonb_build_object(
        'cue', _cue_with_recordings,
        'files', coalesce(to_jsonb(_file_ids), '[]'::jsonb)
    );
end;
$$;

grant execute on function api.get_cue_for_profile(bigint, bigint) to authenticated;

-- function: get all recording history for a profile
create or replace function learning.profile_recording_history(
    _profile_id bigint
)
returns jsonb
language sql
stable
as $$
    select coalesce(
        (
            select jsonb_agg(
                to_jsonb(pcr) || jsonb_build_object(
                    'file', files.file_details(pcr.file_id),
                    'cue', cues.cue_info_by_id(
                        pcr.cue_id,
                        true,
                        p.language_code
                    )
                )
                order by pcr.created_at desc
            )
            from learning.profile_cue_recording pcr
            cross join learning.profile p
            where pcr.profile_id = _profile_id
              and p.profile_id = _profile_id
        ),
        '[]'::jsonb
    );
$$;

-- api: get all recording history for a profile
create or replace function api.get_profile_recording_history(
    profile_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _profile learning.profile := learning.profile_by_id(profile_id);
    _recordings jsonb;
    _file_ids bigint[];
begin
    if _authenticated_account_id is null then
        raise exception 'Get Profile Recording History Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_profile_recording_history';
    end if;

    if _profile.profile_id is null then
        raise exception 'Get Profile Recording History Failed'
            using detail = 'Invalid Profile',
                  hint = 'profile_not_found';
    end if;

    if _profile.account_id <> _authenticated_account_id then
        raise exception 'Get Profile Recording History Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_get_profile_recording_history';
    end if;

    _recordings := learning.profile_recording_history(profile_id);

    -- extract file IDs from recordings for gateway download URL injection
    select array_agg((rec->>'file_id')::bigint)
    into _file_ids
    from jsonb_array_elements(_recordings) as rec;

    return jsonb_build_object(
        'recordings', _recordings,
        'files', coalesce(to_jsonb(_file_ids), '[]'::jsonb)
    );
end;
$$;

grant execute on function api.get_profile_recording_history(bigint) to authenticated;


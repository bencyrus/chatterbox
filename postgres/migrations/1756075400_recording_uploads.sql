-- schema: recording upload intents and associations
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
    returning upload_intent_id
    into upload_intent_id;

    -- store recording-specific metadata
    insert into learning.user_recording_upload_intent (
        upload_intent_id,
        profile_id,
        cue_id
    )
    values (
        upload_intent_id,
        _profile_id,
        _cue_id
    );

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

-- function: complete recording upload
create or replace function learning.complete_recording_upload(
    _upload_intent_id bigint,
    _account_id bigint,
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

    -- create profile_cue_recording link
    insert into learning.profile_cue_recording (
        profile_id,
        cue_id,
        file_id
    )
    values (
        _profile_id,
        _cue_id,
        _file_id
    )
    returning *
    into profile_cue_recording;

    return;
end;
$$;

-- api: complete recording upload
create or replace function api.complete_recording_upload(
    upload_intent_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _complete_result record;
begin
    if _authenticated_account_id is null then
        raise exception 'Complete Recording Upload Failed'
            using detail = 'Unauthorized',
                  hint = 'unauthorized_to_complete_recording_upload';
    end if;

    _complete_result := learning.complete_recording_upload(
        upload_intent_id,
        _authenticated_account_id
    );

    if _complete_result.validation_failure_message is not null then
        raise exception 'Complete Recording Upload Failed'
            using detail = 'Invalid Input',
                  hint = _complete_result.validation_failure_message;
    end if;

    return jsonb_build_object(
        'success', true,
        'files', jsonb_build_array((_complete_result.profile_cue_recording).file_id)
    );
end;
$$;

grant execute on function api.complete_recording_upload(bigint) to authenticated;


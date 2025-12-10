-- introduce deleted flags for accounts and files, plus helpers

-- extend accounts.account_flag_type domain to include deleted and anonymized flags
alter domain accounts.account_flag_type drop constraint if exists account_flag_type_check;

alter domain accounts.account_flag_type
    add constraint account_flag_type_allowed_values
    check (value in ('developer', 'deleted', 'anonymized'));

-- extend files.metadata_key domain to include deleted flag
alter domain files.metadata_key drop constraint if exists metadata_key_check;

alter domain files.metadata_key
    add constraint metadata_key_allowed_values
    check (value in ('name', 'duration', 'deleted'));

-- helper: check if a file is marked as deleted via metadata
create or replace function files.is_file_deleted(
    _file_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from files.file_metadata fm
        where fm.file_id = _file_id
          and fm.key = 'deleted'
          and fm.value = 'true'::jsonb
    );
$$;

-- helper: mark a file as logically deleted via metadata
create or replace function files.mark_file_deleted(
    _file_id bigint
)
returns void
language plpgsql
as $$
begin
    insert into files.file_metadata (
        file_id,
        key,
        value
    )
    values (
        _file_id,
        'deleted',
        'true'::jsonb
    )
    on conflict (file_id, key) do update
        set value = 'true'::jsonb;
end;
$$;

-- update files.lookup_files to ignore deleted files
create or replace function files.lookup_files(
    _file_ids bigint[]
)
returns jsonb
language sql
stable
security definer
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'file_id', f.file_id,
                'bucket', f.bucket,
                'object_key', f.object_key,
                'mime_type', f.mime_type
            )
            order by f.file_id
        ),
        '[]'::jsonb
    )
    from files.file f
    where _file_ids is not null
      and f.file_id = any(_file_ids)
      and not files.is_file_deleted(f.file_id);
$$;

-- update api.app_icon to ignore deleted icon files
create or replace function api.app_icon()
returns jsonb
language sql
stable
security definer
as $$
    select jsonb_build_object(
        'files',
        coalesce(jsonb_agg(f.file_id), '[]'::jsonb)
    )
    from files.file f
    where f.object_key = 'internal-assets/chatterbox-logo-color-bg.png'
      and not files.is_file_deleted(f.file_id);
$$;

-- update files.file_details to ignore deleted files
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
    where f.file_id = _file_id
      and not files.is_file_deleted(f.file_id);
$$;

-- update cue recording history to ignore deleted files
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
              and not files.is_file_deleted(pcr.file_id)
        ),
        '[]'::jsonb
    );
$$;

-- update profile recording history to ignore deleted files
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
              and not files.is_file_deleted(pcr.file_id)
        ),
        '[]'::jsonb
    );
$$;



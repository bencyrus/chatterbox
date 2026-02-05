-- recording report: adds transcript status to recording history responses
--
-- this migration adds a helper function to get recording report info (status + transcript)
-- and updates the recording history functions to include this info in their responses.

-- =============================================================================
-- domain: recording report status type
-- =============================================================================

create domain learning.recording_report_status_type as text
    check (value in ('none', 'processing', 'ready'));

-- =============================================================================
-- helper functions: recording report status and transcript
-- =============================================================================

-- function: get recording report status
-- returns: recording_report_status_type ('none' | 'processing' | 'ready')
create or replace function learning.recording_report_status(
    _profile_cue_recording_id bigint
)
returns learning.recording_report_status_type
language sql
stable
as $$
    select case
        when exists (
            select 1 from learning.recording_transcript
            where profile_cue_recording_id = _profile_cue_recording_id
        ) then 'ready'
        when elevenlabs.has_in_progress_transcription_task(_profile_cue_recording_id) then 'processing'
        else 'none'
    end;
$$;

-- function: get recording transcript text by recording
-- returns: transcript text or null if not available
create or replace function learning.recording_transcript_by_recording(
    _profile_cue_recording_id bigint
)
returns text
language sql
stable
as $$
    select rt.text
    from learning.recording_transcript rt
    where rt.profile_cue_recording_id = _profile_cue_recording_id;
$$;

-- function: get recording report info (combines status and transcript)
-- similar to files.file_details, provides a standardized way to get report data
create or replace function learning.recording_report_info(
    _profile_cue_recording_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'status', learning.recording_report_status(_profile_cue_recording_id),
        'transcript', learning.recording_transcript_by_recording(_profile_cue_recording_id)
    );
$$;

-- =============================================================================
-- updated functions: include report info in recording history
-- =============================================================================

-- function: get cue recording history for a profile (with report info)
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
                    'file', files.file_details(pcr.file_id),
                    'report', learning.recording_report_info(pcr.profile_cue_recording_id)
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

-- function: get all recording history for a profile (with report info)
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
                    ),
                    'report', learning.recording_report_info(pcr.profile_cue_recording_id)
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

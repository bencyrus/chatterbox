-- recording evaluation: CEFR speaking feedback via generic OpenAI Responses
--
-- this migration adds a recording-specific layer on top of the generic
-- openai_response supervisor. Given a profile_cue_recording_id with an existing
-- transcript, it creates an OpenAI background response and stores a structured
-- A1-C2 speaking evaluation when the canonical response has been retrieved.

-- =============================================================================
-- domains
-- =============================================================================

create domain learning.cefr_level as text
    check (value in ('A1', 'A2', 'B1', 'B2', 'C1', 'C2'));

create domain learning.recording_evaluation_status_type as text
    check (value in ('none', 'processing', 'ready'));

-- =============================================================================
-- tables
-- =============================================================================

-- task table: one per requested recording evaluation
create table learning.recording_evaluation_task (
    recording_evaluation_task_id bigserial primary key,
    profile_cue_recording_id bigint not null
        references learning.profile_cue_recording(profile_cue_recording_id)
        on delete cascade,
    openai_response_task_id bigint not null unique
        references openai.openai_response_task(openai_response_task_id)
        on delete cascade,
    created_at timestamp with time zone not null default now(),
    created_by bigint not null
        references accounts.account(account_id)
        on delete cascade
);

-- final evaluation result (actual learning outcome)
create table learning.recording_evaluation (
    recording_evaluation_id bigserial primary key,
    recording_evaluation_task_id bigint not null unique
        references learning.recording_evaluation_task(recording_evaluation_task_id)
        on delete cascade,
    profile_cue_recording_id bigint not null unique
        references learning.profile_cue_recording(profile_cue_recording_id)
        on delete cascade,
    cefr_level learning.cefr_level not null,
    summary text not null,
    strengths jsonb not null default '[]'::jsonb,
    improvement_areas jsonb not null default '[]'::jsonb,
    recommended_next_steps jsonb not null default '[]'::jsonb,
    raw_evaluation jsonb not null,
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- facts
-- =============================================================================

create or replace function learning.has_recording_evaluation(
    _profile_cue_recording_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from learning.recording_evaluation e
        where e.profile_cue_recording_id = _profile_cue_recording_id
    );
$$;

create or replace function learning.has_in_progress_recording_evaluation_task(
    _profile_cue_recording_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from learning.recording_evaluation_task t
        where t.profile_cue_recording_id = _profile_cue_recording_id
          and not learning.has_recording_evaluation(_profile_cue_recording_id)
          and (
              select count(*)::integer
              from openai.openai_response_attempt a
              join openai.openai_response_attempt_failed f
                  on f.openai_response_attempt_id = a.openai_response_attempt_id
              where a.openai_response_task_id = t.openai_response_task_id
          ) < 2
    );
$$;

create or replace function learning.recording_evaluation_status(
    _profile_cue_recording_id bigint
)
returns learning.recording_evaluation_status_type
language sql
stable
as $$
    select case
        when learning.has_recording_evaluation(_profile_cue_recording_id) then 'ready'
        when learning.has_in_progress_recording_evaluation_task(_profile_cue_recording_id) then 'processing'
        else 'none'
    end;
$$;

create or replace function learning.recording_evaluation_by_recording(
    _profile_cue_recording_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'cefr_level', e.cefr_level,
        'summary', e.summary,
        'strengths', e.strengths,
        'improvement_areas', e.improvement_areas,
        'recommended_next_steps', e.recommended_next_steps,
        'created_at', e.created_at
    )
    from learning.recording_evaluation e
    where e.profile_cue_recording_id = _profile_cue_recording_id;
$$;

create or replace function learning.recording_evaluation_request_facts(
    _profile_cue_recording_id bigint,
    out profile_cue_recording_id bigint,
    out profile_id bigint,
    out account_id bigint,
    out cue_id bigint,
    out language_code languages.language_code,
    out transcript_text text,
    out cue_info jsonb,
    out has_evaluation boolean,
    out has_in_progress_task boolean
)
language sql
stable
as $$
    select
        pcr.profile_cue_recording_id,
        pcr.profile_id,
        p.account_id,
        pcr.cue_id,
        p.language_code,
        rt.text,
        cues.cue_info_by_id(pcr.cue_id, true, p.language_code),
        learning.has_recording_evaluation(pcr.profile_cue_recording_id),
        learning.has_in_progress_recording_evaluation_task(pcr.profile_cue_recording_id)
    from learning.profile_cue_recording pcr
    join learning.profile p
        on p.profile_id = pcr.profile_id
    left join learning.recording_transcript rt
        on rt.profile_cue_recording_id = pcr.profile_cue_recording_id
    where pcr.profile_cue_recording_id = _profile_cue_recording_id;
$$;

create or replace function learning.recording_evaluation_openai_task_facts(
    _recording_evaluation_task_id bigint,
    out profile_cue_recording_id bigint,
    out openai_response_task_id bigint,
    out openai_response_attempt_id bigint,
    out has_openai_retrieval boolean,
    out has_evaluation boolean,
    out response_body jsonb
)
language sql
stable
as $$
    select
        t.profile_cue_recording_id,
        t.openai_response_task_id,
        a.openai_response_attempt_id,
        r.openai_response_retrieval_id is not null,
        learning.has_recording_evaluation(t.profile_cue_recording_id),
        r.response_body
    from learning.recording_evaluation_task t
    left join openai.openai_response_attempt a
        on a.openai_response_task_id = t.openai_response_task_id
    left join openai.openai_response_retrieval r
        on r.openai_response_attempt_id = a.openai_response_attempt_id
    where t.recording_evaluation_task_id = _recording_evaluation_task_id
    order by a.created_at desc, a.openai_response_attempt_id desc
    limit 1;
$$;

-- =============================================================================
-- prompt / response extraction helpers
-- =============================================================================

create or replace function learning.recording_evaluation_openai_request_body(
    _profile_cue_recording_id bigint,
    _recording_evaluation_task_id bigint,
    _transcript_text text,
    _cue_info jsonb,
    _language_code languages.language_code
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'model', coalesce(internal.get_config('openai')->>'default_model', 'gpt-5.5'),
        'background', true,
        'metadata', jsonb_build_object(
            'purpose', 'recording_evaluation',
            'profile_cue_recording_id', _profile_cue_recording_id,
            'recording_evaluation_task_id', _recording_evaluation_task_id
        ),
        'instructions',
            'You are a CEFR speaking evaluator for Chatterbox. Evaluate the learner speaking performance using only the transcript and cue context. Rate the performance on the CEFR A1-C2 scale. Do not infer audio-only qualities such as pronunciation, fluency pauses, intonation, or accent unless they are directly evident in the transcript. Return concise, actionable feedback.',
        'input', jsonb_build_array(
            jsonb_build_object(
                'role', 'user',
                'content', jsonb_build_array(
                    jsonb_build_object(
                        'type', 'input_text',
                        'text',
                            'Target language: ' || coalesce(_language_code::text, 'unknown') || E'\n\n'
                            || 'Cue title: ' || coalesce(_cue_info->'content'->>'title', '') || E'\n\n'
                            || 'Cue details: ' || coalesce(_cue_info->'content'->>'details', '') || E'\n\n'
                            || 'Transcript: ' || coalesce(_transcript_text, '')
                    )
                )
            )
        ),
        'text', jsonb_build_object(
            'format', jsonb_build_object(
                'type', 'json_schema',
                'name', 'recording_speaking_evaluation',
                'strict', true,
                'schema', jsonb_build_object(
                    'type', 'object',
                    'additionalProperties', false,
                    'required', jsonb_build_array(
                        'cefr_level',
                        'summary',
                        'strengths',
                        'improvement_areas',
                        'recommended_next_steps'
                    ),
                    'properties', jsonb_build_object(
                        'cefr_level', jsonb_build_object(
                            'type', 'string',
                            'enum', jsonb_build_array('A1', 'A2', 'B1', 'B2', 'C1', 'C2')
                        ),
                        'summary', jsonb_build_object(
                            'type', 'string',
                            'description', 'A concise overall assessment of the speaking performance.'
                        ),
                        'strengths', jsonb_build_object(
                            'type', 'array',
                            'items', jsonb_build_object('type', 'string'),
                            'description', 'Concrete strengths visible in the transcript.'
                        ),
                        'improvement_areas', jsonb_build_object(
                            'type', 'array',
                            'items', jsonb_build_object('type', 'string'),
                            'description', 'Concrete areas to improve, phrased actionably.'
                        ),
                        'recommended_next_steps', jsonb_build_object(
                            'type', 'array',
                            'items', jsonb_build_object('type', 'string'),
                            'description', 'Practice suggestions appropriate to the evaluated level.'
                        )
                    )
                )
            )
        )
    );
$$;

create or replace function openai.openai_response_output_text(
    _response_body jsonb
)
returns text
language sql
stable
as $$
    select string_agg(content_item.value->>'text', '' order by output_item.ordinality, content_item.ordinality)
    from jsonb_array_elements(coalesce(_response_body->'output', '[]'::jsonb))
        with ordinality as output_item(value, ordinality)
    cross join lateral jsonb_array_elements(coalesce(output_item.value->'content', '[]'::jsonb))
        with ordinality as content_item(value, ordinality)
    where output_item.value->>'type' = 'message'
      and content_item.value->>'type' = 'output_text';
$$;

create or replace function learning.parse_recording_evaluation_response(
    _response_body jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
    _output_text text;
    _evaluation jsonb;
begin
    _output_text := openai.openai_response_output_text(_response_body);

    if _output_text is null or btrim(_output_text) = '' then
        return null;
    end if;

    begin
        _evaluation := _output_text::jsonb;
    exception when others then
        return null;
    end;

    if not (_evaluation ? 'cefr_level')
        or not (_evaluation->>'cefr_level' in ('A1', 'A2', 'B1', 'B2', 'C1', 'C2'))
        or not (_evaluation ? 'summary')
    then
        return null;
    end if;

    return _evaluation;
end;
$$;

-- =============================================================================
-- effects
-- =============================================================================

create or replace function learning.create_recording_evaluation_task(
    _profile_cue_recording_id bigint,
    _created_by bigint,
    out recording_evaluation_task_id bigint,
    out openai_response_task_id bigint
)
returns record
language plpgsql
security definer
as $$
declare
    _facts record;
    _recording_evaluation_task_id bigint;
    _openai_response_task_id bigint;
    _request_body jsonb;
begin
    -- 1. FACTS
    _facts := learning.recording_evaluation_request_facts(_profile_cue_recording_id);

    -- 2. EFFECT: create generic OpenAI task with a temporary request body
    insert into openai.openai_response_task (
        purpose,
        request_body,
        metadata,
        created_by
    ) values (
        'recording_evaluation',
        '{}'::jsonb,
        jsonb_build_object('profile_cue_recording_id', _profile_cue_recording_id),
        _created_by
    )
    returning openai.openai_response_task.openai_response_task_id
    into _openai_response_task_id;

    insert into learning.recording_evaluation_task (
        profile_cue_recording_id,
        openai_response_task_id,
        created_by
    ) values (
        _profile_cue_recording_id,
        _openai_response_task_id,
        _created_by
    )
    returning learning.recording_evaluation_task.recording_evaluation_task_id
    into _recording_evaluation_task_id;

    _request_body := learning.recording_evaluation_openai_request_body(
        _profile_cue_recording_id,
        _recording_evaluation_task_id,
        _facts.transcript_text,
        _facts.cue_info,
        _facts.language_code
    );

    update openai.openai_response_task t
    set request_body = _request_body,
        metadata = t.metadata || jsonb_build_object(
            'recording_evaluation_task_id', _recording_evaluation_task_id
        )
    where t.openai_response_task_id = _openai_response_task_id;

    recording_evaluation_task_id := _recording_evaluation_task_id;
    openai_response_task_id := _openai_response_task_id;
end;
$$;

create or replace function learning.record_recording_evaluation(
    _recording_evaluation_task_id bigint,
    _evaluation jsonb
)
returns void
language sql
as $$
    insert into learning.recording_evaluation (
        recording_evaluation_task_id,
        profile_cue_recording_id,
        cefr_level,
        summary,
        strengths,
        improvement_areas,
        recommended_next_steps,
        raw_evaluation
    )
    select
        t.recording_evaluation_task_id,
        t.profile_cue_recording_id,
        (_evaluation->>'cefr_level')::learning.cefr_level,
        _evaluation->>'summary',
        coalesce(_evaluation->'strengths', '[]'::jsonb),
        coalesce(_evaluation->'improvement_areas', '[]'::jsonb),
        coalesce(_evaluation->'recommended_next_steps', '[]'::jsonb),
        _evaluation
    from learning.recording_evaluation_task t
    where t.recording_evaluation_task_id = _recording_evaluation_task_id
    on conflict (recording_evaluation_task_id) do nothing;
$$;

create or replace function learning.recording_evaluation_supervisor_recheck(
    _recording_evaluation_task_id bigint,
    _run_count integer
)
returns void
language plpgsql
security definer
as $$
declare
    _recheck_interval_seconds integer := 3;
begin
    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'learning.recording_evaluation_supervisor',
            'recording_evaluation_task_id', _recording_evaluation_task_id,
            'run_count', _run_count + 1
        ),
        now() + (_recheck_interval_seconds * interval '1 second')
    );
end;
$$;

-- =============================================================================
-- supervisors
-- =============================================================================

create or replace function learning.recording_evaluation_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _recording_evaluation_task_id bigint := (_payload->>'recording_evaluation_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _max_runs integer := 250;
    _facts record;
    _openai_supervisor_result jsonb;
    _evaluation jsonb;
begin
    -- 1. VALIDATION
    if _recording_evaluation_task_id is null then
        return jsonb_build_object('status', 'missing_recording_evaluation_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'learning.recording_evaluation_supervisor.exceeded_max_runs'
            using detail = format('task_id=%s, run_count=%s', _recording_evaluation_task_id, _run_count);
    end if;

    -- 2. LOCK
    perform 1
    from learning.recording_evaluation_task t
    where t.recording_evaluation_task_id = _recording_evaluation_task_id
    for update;

    -- 3. FACTS
    _facts := learning.recording_evaluation_openai_task_facts(_recording_evaluation_task_id);

    -- 4. LOGIC + EFFECTS
    if _facts.has_evaluation then
        return jsonb_build_object('status', 'succeeded');
    end if;

    -- Let the generic OpenAI supervisor make progress on create/wait/retrieve.
    _openai_supervisor_result := openai.openai_response_supervisor(
        jsonb_build_object('openai_response_task_id', _facts.openai_response_task_id)
    );

    _facts := learning.recording_evaluation_openai_task_facts(_recording_evaluation_task_id);

    if not _facts.has_openai_retrieval then
        perform learning.recording_evaluation_supervisor_recheck(_recording_evaluation_task_id, _run_count);
        return jsonb_build_object(
            'status', 'waiting_for_openai_response',
            'openai_status', _openai_supervisor_result->>'status'
        );
    end if;

    _evaluation := learning.parse_recording_evaluation_response(_facts.response_body);

    if _evaluation is null then
        perform openai.record_openai_response_attempt_failure(
            _facts.openai_response_attempt_id,
            'invalid_recording_evaluation_response'
        );
        return jsonb_build_object('status', 'invalid_recording_evaluation_response');
    end if;

    perform learning.record_recording_evaluation(
        _recording_evaluation_task_id,
        _evaluation
    );

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- =============================================================================
-- api: request evaluation
-- =============================================================================

create or replace function api.request_recording_evaluation(
    profile_cue_recording_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _facts record;
    _task_result record;
begin
    -- 1. VALIDATION
    if _authenticated_account_id is null then
        raise exception 'Request Recording Evaluation Failed'
            using detail = 'Unauthorized', hint = 'unauthorized';
    end if;

    -- 2. FACTS
    _facts := learning.recording_evaluation_request_facts(profile_cue_recording_id);

    -- 3. LOGIC
    if _facts.profile_cue_recording_id is null then
        raise exception 'Request Recording Evaluation Failed'
            using detail = 'Recording not found', hint = 'recording_not_found';
    end if;

    if _facts.account_id <> _authenticated_account_id then
        raise exception 'Request Recording Evaluation Failed'
            using detail = 'Unauthorized', hint = 'unauthorized';
    end if;

    if _facts.transcript_text is null or btrim(_facts.transcript_text) = '' then
        return jsonb_build_object('status', 'transcript_not_ready');
    end if;

    if _facts.has_evaluation then
        return jsonb_build_object('status', 'already_evaluated');
    end if;

    if _facts.has_in_progress_task then
        return jsonb_build_object('status', 'in_progress');
    end if;

    -- 4. EFFECTS
    _task_result := learning.create_recording_evaluation_task(
        profile_cue_recording_id,
        _authenticated_account_id
    );

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'learning.recording_evaluation_supervisor',
            'recording_evaluation_task_id', _task_result.recording_evaluation_task_id
        ),
        now()
    );

    return jsonb_build_object(
        'status', 'started',
        'recording_evaluation_task_id', _task_result.recording_evaluation_task_id,
        'openai_response_task_id', _task_result.openai_response_task_id
    );
end;
$$;

grant execute on function api.request_recording_evaluation(bigint) to authenticated;

-- =============================================================================
-- report helpers
-- =============================================================================

create or replace function learning.recording_report_info(
    _profile_cue_recording_id bigint
)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'status', learning.recording_report_status(_profile_cue_recording_id),
        'transcript', learning.recording_transcript_by_recording(_profile_cue_recording_id),
        'evaluation', jsonb_build_object(
            'status', learning.recording_evaluation_status(_profile_cue_recording_id),
            'result', learning.recording_evaluation_by_recording(_profile_cue_recording_id)
        )
    );
$$;

-- =============================================================================
-- grants
-- =============================================================================

grant execute on function learning.recording_evaluation_supervisor(jsonb) to worker_service_user;
grant execute on function learning.recording_evaluation_supervisor_recheck(bigint, integer) to worker_service_user;
grant execute on function learning.record_recording_evaluation(bigint, jsonb) to worker_service_user;
grant execute on function learning.parse_recording_evaluation_response(jsonb) to worker_service_user;
grant execute on function openai.openai_response_output_text(jsonb) to worker_service_user;

-- recording transcription: async transcription via ElevenLabs with webhook-based completion
--
-- this migration implements recording transcription via a two-stage supervisor pattern:
-- stage 1: request succeeded (API call to ElevenLabs worked)
-- stage 2: response succeeded (webhook received and verified)

-- =============================================================================
-- foundation: extend task domain and create elevenlabs schema
-- =============================================================================

alter domain queues.task_type drop constraint if exists task_type_allowed_values;

alter domain queues.task_type
    add constraint task_type_allowed_values
    check (value in ('db_function', 'email', 'sms', 'file_delete', 'transcription_kickoff'));

create schema if not exists elevenlabs;

grant usage on schema elevenlabs to worker_service_user;

-- seed elevenlabs config
insert into internal.config (key, value)
values (
    'elevenlabs',
    '{
        "webhook_secret": "{secrets.elevenlabs_webhook_secret}"
    }'
)
on conflict (key) do nothing;

-- =============================================================================
-- tables (ordered by dependency: task -> attempt -> request -> response)
-- =============================================================================

-- task table: one per transcription request
create table learning.recording_transcription_task (
    recording_transcription_task_id bigserial primary key,
    profile_cue_recording_id bigint not null
        references learning.profile_cue_recording(profile_cue_recording_id)
        on delete cascade,
    created_at timestamp with time zone not null default now(),
    created_by bigint not null
        references accounts.account(account_id)
        on delete cascade
);

-- attempt table: one per API call attempt
create table learning.recording_transcription_attempt (
    recording_transcription_attempt_id bigserial primary key,
    recording_transcription_task_id bigint not null
        references learning.recording_transcription_task(recording_transcription_task_id)
        on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- recording transcription requests: tracks what we sent to ElevenLabs
-- written by: kickoff worker after successful API call
create table elevenlabs.recording_transcription_request (
    recording_transcription_request_id bigserial primary key,
    recording_transcription_attempt_id bigint not null unique
        references learning.recording_transcription_attempt(recording_transcription_attempt_id)
        on delete cascade,
    elevenlabs_request_id text not null unique,  -- unique constraint creates index for webhook lookup
    created_at timestamp with time zone not null default now()
);

-- recording transcription responses: raw webhook data from ElevenLabs
-- written by: webhook endpoint (no verification, just store)
-- uses JSON (not JSONB) to preserve exact bytes for signature verification
-- links to request via FK (looked up at webhook time using elevenlabs_request_id from webhook body)
create table elevenlabs.recording_transcription_response (
    recording_transcription_response_id bigserial primary key,
    recording_transcription_request_id bigint not null unique
        references elevenlabs.recording_transcription_request(recording_transcription_request_id)
        on delete cascade,
    raw_body json not null,
    signature_header text not null,
    received_at timestamp with time zone not null default now()
);

-- failure: any failure at either stage
-- note: success is inferred from existence of other records:
--   - request succeeded = recording_transcription_request exists for this attempt
--   - response succeeded = recording_transcript exists for this recording (terminal)
-- written by: transcription kickoff worker on API failure, OR supervisor on verification failure
create table learning.recording_transcription_attempt_failed (
    recording_transcription_attempt_id bigint primary key
        references learning.recording_transcription_attempt(recording_transcription_attempt_id)
        on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- transcript storage
create table learning.recording_transcript (
    recording_transcript_id bigserial primary key,
    profile_cue_recording_id bigint not null unique
        references learning.profile_cue_recording(profile_cue_recording_id)
        on delete cascade,
    text text not null,
    words jsonb not null,
    language_code text,
    language_probability numeric(4,3),
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- webhook: signature verification
-- =============================================================================

create or replace function elevenlabs.transcription_webhook_signature_is_valid(
    _raw_response_body text,
    _elevenlabs_signature_header text,
    _signing_secret text,
    _current_timestamp_epoch bigint,
    _timestamp_tolerance_seconds integer default 1800
)
returns boolean
language plpgsql
immutable
as $$
/**
 * Verifies ElevenLabs webhook signatures per official docs.
 *
 * This function has unit tests!
 * See: elevenlabs.transcription_webhook_signature_is_valid_run_unit_tests
 *
 * Header format: ElevenLabs-Signature: t=<timestamp>,v0=<hash>
 * Hash is HMAC-SHA256 of: timestamp + "." + raw_body
 *
 * Verification follows ElevenLabs official approach:
 * https://elevenlabs.io/docs/product-guides/administration/webhooks
 */
declare
    _parts text[];
    _received_timestamp bigint;
    _received_signature text;
    _expected_signature text;
begin
    -- 1. split header: "t=123,v0=abc" -> ["t=123", "v0=abc"]
    _parts := string_to_array(_elevenlabs_signature_header, ',');

    if array_length(_parts, 1) is null or array_length(_parts, 1) < 2 then
        return false;
    end if;

    -- 2. extract timestamp (strip "t=" prefix)
    begin
        _received_timestamp := substring(_parts[1] from 3)::bigint;
    exception when others then
        return false;
    end;

    -- 3. extract signature (full "v0=..." for comparison)
    _received_signature := _parts[2];

    -- 4. check timestamp not too old (replay attack protection)
    if _current_timestamp_epoch - _received_timestamp > _timestamp_tolerance_seconds then
        return false;
    end if;

    -- 5. compute expected signature
    _expected_signature := 'v0=' || encode(
        public.hmac(_received_timestamp::text || '.' || _raw_response_body, _signing_secret, 'sha256'),
        'hex'
    );

    -- 6. compare signatures
    return _received_signature = _expected_signature;
end;
$$;

-- unit tests for signature verification
create or replace function elevenlabs.transcription_webhook_signature_is_valid_run_unit_tests()
returns table(test text, passed boolean)
language plpgsql
immutable
as $$
begin
    -- test 1: valid signature, exact timestamp
    return query
    select
        'valid signature, exact timestamp -> valid'::text,
        elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
            't=1752155502,v0=' || encode(
                public.hmac(
                    '1752155502.{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
                    'whsec_test_secret',
                    'sha256'
                ),
                'hex'
            ),
            'whsec_test_secret',
            1752155502
        );

    -- test 2: valid signature, timestamp slightly in past (within 30 min tolerance)
    return query
    select
        'valid signature, timestamp 100s old -> valid'::text,
        elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
            't=1752155502,v0=' || encode(
                public.hmac(
                    '1752155502.{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
                    'whsec_test_secret',
                    'sha256'
                ),
                'hex'
            ),
            'whsec_test_secret',
            1752155602  -- 100 seconds later
        );

    -- test 3: valid signature, timestamp in future (allowed - only "too old" is rejected)
    return query
    select
        'valid signature, timestamp in future -> valid'::text,
        elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
            't=1752155502,v0=' || encode(
                public.hmac(
                    '1752155502.{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
                    'whsec_test_secret',
                    'sha256'
                ),
                'hex'
            ),
            'whsec_test_secret',
            1752155400  -- 102 seconds before (timestamp is "in future")
        );

    -- test 4: invalid - timestamp too old (beyond 30 min tolerance)
    return query
    select
        'timestamp too old -> fails'::text,
        not elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
            't=1752155502,v0=' || encode(
                public.hmac(
                    '1752155502.{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
                    'whsec_test_secret',
                    'sha256'
                ),
                'hex'
            ),
            'whsec_test_secret',
            1752157400  -- 1898 seconds later (> 1800s tolerance)
        );

    -- test 5: invalid - wrong secret
    return query
    select
        'wrong secret -> fails'::text,
        not elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
            't=1752155502,v0=' || encode(
                public.hmac(
                    '1752155502.{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
                    'whsec_test_secret',
                    'sha256'
                ),
                'hex'
            ),
            'whsec_wrong_secret',
            1752155502
        );

    -- test 6: invalid - modified payload
    return query
    select
        'modified payload -> fails'::text,
        not elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"speech_to_text_transcription","data":{"request_id":"MODIFIED"}}',
            't=1752155502,v0=' || encode(
                public.hmac(
                    '1752155502.{"type":"speech_to_text_transcription","data":{"request_id":"test123"}}',
                    'whsec_test_secret',
                    'sha256'
                ),
                'hex'
            ),
            'whsec_test_secret',
            1752155502
        );

    -- test 7: invalid - malformed header (missing v0)
    return query
    select
        'malformed header, missing v0 -> fails'::text,
        not elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"test"}',
            't=1752155502',
            'whsec_test_secret',
            1752155502
        );

    -- test 8: invalid - malformed header (missing timestamp)
    return query
    select
        'malformed header, missing timestamp -> fails'::text,
        not elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"test"}',
            'v0=abc123',
            'whsec_test_secret',
            1752155502
        );

    -- test 9: invalid - empty header
    return query
    select
        'empty header -> fails'::text,
        not elevenlabs.transcription_webhook_signature_is_valid(
            '{"type":"test"}',
            '',
            'whsec_test_secret',
            1752155502
        );
end;
$$;

-- =============================================================================
-- webhook: endpoint (receives webhooks from ElevenLabs)
-- =============================================================================

-- facts: extract and lookup everything needed for webhook processing
create or replace function elevenlabs.transcription_webhook_facts(
    _webhook_body json,
    out signature_header text,
    out elevenlabs_request_id text,
    out recording_transcription_request_id bigint,
    out response_already_exists boolean
)
language plpgsql
stable
as $$
begin
    -- extract signature from HTTP header
    signature_header := coalesce(
        current_setting('request.headers', true)::json->>'elevenlabs-signature',
        'missing-signature-header'
    );

    -- extract request_id from webhook body
    elevenlabs_request_id := _webhook_body::jsonb->'data'->>'request_id';

    -- lookup our internal request record
    recording_transcription_request_id := (
        select req.recording_transcription_request_id
        from elevenlabs.recording_transcription_request req
        where req.elevenlabs_request_id = transcription_webhook_facts.elevenlabs_request_id
    );

    -- check if response already exists
    response_already_exists := exists (
        select 1 from elevenlabs.recording_transcription_response res
        where res.recording_transcription_request_id = transcription_webhook_facts.recording_transcription_request_id
    );
end;
$$;

-- effect: store webhook response
create or replace function elevenlabs.record_transcription_webhook_response(
    _recording_transcription_request_id bigint,
    _raw_body json,
    _signature_header text
)
returns void
language sql
as $$
    insert into elevenlabs.recording_transcription_response (
        recording_transcription_request_id,
        raw_body,
        signature_header
    ) values (
        _recording_transcription_request_id,
        _raw_body,
        _signature_header
    );
$$;

-- api: webhook endpoint
-- function called by PostgREST: POST /rpc/eleven_labs_transcription_webhook
-- anonymous access required (ElevenLabs can't authenticate with our JWT)
-- this function does NO verification - just stores raw data and returns 200
-- CRITICAL: use JSON parameter type (not JSONB) to preserve exact formatting
create or replace function api.eleven_labs_transcription_webhook(
    json
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _webhook_body json := $1;
    _facts record;
begin
    -- 1. FACTS
    _facts := elevenlabs.transcription_webhook_facts(_webhook_body);

    -- 2. LOGIC
    if _facts.elevenlabs_request_id is null then
        raise warning 'api.eleven_labs_transcription_webhook.invalid.missing_request_id';
        return jsonb_build_object(
            'status', 'received',
            'warning', 'missing_request_id'
        );
    end if;

    if _facts.recording_transcription_request_id is null then
        raise warning 'api.eleven_labs_transcription_webhook.invalid.request_not_found: %', _facts.elevenlabs_request_id;
        return jsonb_build_object(
            'status', 'received',
            'warning', 'request_not_found'
        );
    end if;

    if _facts.response_already_exists then
        raise warning 'api.eleven_labs_transcription_webhook.invalid.response_already_exists: %', _facts.elevenlabs_request_id;
        return jsonb_build_object(
            'status', 'received',
            'warning', 'response_already_exists'
        );
    end if;

    -- 3. EFFECT
    perform elevenlabs.record_transcription_webhook_response(
        _facts.recording_transcription_request_id,
        _webhook_body,
        _facts.signature_header
    );

    return jsonb_build_object('status', 'received');
end;
$$;

-- =============================================================================
-- transcription kickoff: handlers for worker task
-- =============================================================================

-- facts: get kickoff payload facts from attempt_id
create or replace function learning.get_recording_transcription_kickoff_payload_facts(
    _recording_transcription_attempt_id bigint,
    out file_id bigint,
    out profile_cue_recording_id bigint
)
language sql
stable
as $$
    select
        r.file_id,
        r.profile_cue_recording_id
    from learning.recording_transcription_attempt a
    join learning.recording_transcription_task t
        on t.recording_transcription_task_id = a.recording_transcription_task_id
    join learning.profile_cue_recording r
        on r.profile_cue_recording_id = t.profile_cue_recording_id
    where a.recording_transcription_attempt_id = _recording_transcription_attempt_id;
$$;

-- before handler: build provider payload from recording_transcription_attempt_id in payload
create or replace function learning.get_recording_transcription_kickoff_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _recording_transcription_attempt_id bigint := (_payload->>'recording_transcription_attempt_id')::bigint;
    _facts record;
begin
    -- 1. VALIDATION
    if _recording_transcription_attempt_id is null then
        return jsonb_build_object('status', 'missing_recording_transcription_attempt_id');
    end if;

    -- 2. FACTS
    _facts := learning.get_recording_transcription_kickoff_payload_facts(_recording_transcription_attempt_id);

    -- 3. LOGIC
    if _facts.file_id is null then
        return jsonb_build_object('status', 'recording_not_found');
    end if;

    -- 4. OUTPUT
    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'file_id', _facts.file_id,
            'recording_transcription_attempt_id', _recording_transcription_attempt_id
        )
    );
end;
$$;

-- success handler: record request succeeded (API call worked)
-- receives: { original_payload: { recording_transcription_attempt_id, ... }, worker_payload: { request_id: "..." } }
create or replace function learning.record_recording_transcription_request_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _recording_transcription_attempt_id bigint := (_payload->'original_payload'->>'recording_transcription_attempt_id')::bigint;
    _request_id text := (_payload->'worker_payload'->>'request_id');
begin
    if _recording_transcription_attempt_id is null then
        return jsonb_build_object('status', 'missing_recording_transcription_attempt_id');
    end if;

    if _request_id is null or _request_id = '' then
        return jsonb_build_object('status', 'missing_request_id');
    end if;

    -- store ElevenLabs request details
    -- note: existence of this record IS the success fact (no separate succeeded table)
    insert into elevenlabs.recording_transcription_request (
        recording_transcription_attempt_id,
        elevenlabs_request_id
    ) values (
        _recording_transcription_attempt_id,
        _request_id
    )
    on conflict (recording_transcription_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- effect: record attempt failure
create or replace function learning.record_recording_transcription_attempt_failure(
    _recording_transcription_attempt_id bigint,
    _error_message text
)
returns void
language sql
as $$
    insert into learning.recording_transcription_attempt_failed (
        recording_transcription_attempt_id,
        error_message
    ) values (
        _recording_transcription_attempt_id,
        _error_message
    )
    on conflict (recording_transcription_attempt_id) do nothing;
$$;

-- error handler: record request failure (API call failed)
-- receives: { original_payload: { recording_transcription_attempt_id, ... }, error: "..." }
create or replace function learning.record_recording_transcription_request_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _recording_transcription_attempt_id bigint := (_payload->'original_payload'->>'recording_transcription_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _recording_transcription_attempt_id is null then
        return jsonb_build_object('status', 'missing_recording_transcription_attempt_id');
    end if;

    perform learning.record_recording_transcription_attempt_failure(
        _recording_transcription_attempt_id,
        _error_message
    );

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- effect: schedule a transcription kickoff attempt (returns attempt_id)
create or replace function learning.schedule_recording_transcription_kickoff(
    _recording_transcription_task_id bigint
)
returns bigint
language plpgsql
security definer
as $$
declare
    _recording_transcription_attempt_id bigint;
begin
    insert into learning.recording_transcription_attempt (recording_transcription_task_id)
    values (_recording_transcription_task_id)
    returning recording_transcription_attempt_id into _recording_transcription_attempt_id;

    perform queues.enqueue(
        'transcription_kickoff',
        jsonb_build_object(
            'task_type', 'transcription_kickoff',
            'recording_transcription_attempt_id', _recording_transcription_attempt_id,
            'before_handler', 'learning.get_recording_transcription_kickoff_payload',
            'success_handler', 'learning.record_recording_transcription_request_success',
            'error_handler', 'learning.record_recording_transcription_request_failure'
        ),
        now()
    );

    return _recording_transcription_attempt_id;
end;
$$;

-- =============================================================================
-- supervisor: orchestrates transcription workflow
-- =============================================================================

-- facts: check if recording already has a transcript
create or replace function learning.has_recording_transcript(
    _profile_cue_recording_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1 from learning.recording_transcript
        where profile_cue_recording_id = _profile_cue_recording_id
    );
$$;

-- facts: all supervisor facts in one function
create or replace function learning.recording_transcription_supervisor_facts(
    _recording_transcription_task_id bigint,
    _current_attempt_id bigint default null,
    out has_transcript boolean,
    out num_failures integer,
    out num_attempts integer,
    out attempt_has_request boolean,
    out attempt_has_response boolean,
    out attempt_has_failed boolean
)
language plpgsql
stable
as $$
declare
    _profile_cue_recording_id bigint;
begin
    -- get recording id for transcript check
    _profile_cue_recording_id := (
        select t.profile_cue_recording_id
        from learning.recording_transcription_task t
        where t.recording_transcription_task_id = _recording_transcription_task_id
    );

    -- task-level facts
    has_transcript := learning.has_recording_transcript(_profile_cue_recording_id);

    num_failures := (
        select count(*)::integer
        from learning.recording_transcription_attempt a
        join learning.recording_transcription_attempt_failed f
            on f.recording_transcription_attempt_id = a.recording_transcription_attempt_id
        where a.recording_transcription_task_id = _recording_transcription_task_id
    );

    num_attempts := (
        select count(*)::integer
        from learning.recording_transcription_attempt a
        where a.recording_transcription_task_id = _recording_transcription_task_id
    );

    -- attempt-level facts
    attempt_has_request := exists (
        select 1 from elevenlabs.recording_transcription_request
        where recording_transcription_attempt_id = _current_attempt_id
    );

    attempt_has_response := exists (
        select 1
        from elevenlabs.recording_transcription_request req
        join elevenlabs.recording_transcription_response res
            on res.recording_transcription_request_id = req.recording_transcription_request_id
        where req.recording_transcription_attempt_id = _current_attempt_id
    );

    attempt_has_failed := exists (
        select 1 from learning.recording_transcription_attempt_failed
        where recording_transcription_attempt_id = _current_attempt_id
    );
end;
$$;

-- effect: schedule supervisor recheck
-- _time_waiting_seconds: tracks how long we've been waiting for webhook (for timeout)
-- pass 0 to reset timer (after processing, failure, etc.)
create or replace function learning.schedule_recording_transcription_supervisor_recheck(
    _recording_transcription_task_id bigint,
    _run_count integer,
    _current_attempt_id bigint default null,
    _time_waiting_seconds integer default 0
)
returns void
language plpgsql
security definer
as $$
declare
    _recheck_interval_seconds integer := 3;
    _next_check_at timestamptz;
begin
    _next_check_at := now() + (_recheck_interval_seconds * interval '1 second');

    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'learning.recording_transcription_supervisor',
            'recording_transcription_task_id', _recording_transcription_task_id,
            'run_count', _run_count + 1,
            'current_attempt_id', _current_attempt_id,
            'time_waiting_seconds', _time_waiting_seconds + _recheck_interval_seconds
        ),
        _next_check_at
    );
end;
$$;

-- =============================================================================
-- response processing: verifies and stores transcript
-- =============================================================================

-- facts: get transcription response for attempt (via request join)
create or replace function elevenlabs.get_recording_transcription_response(
    _recording_transcription_attempt_id bigint
)
returns elevenlabs.recording_transcription_response
language sql
stable
as $$
    select res.*
    from elevenlabs.recording_transcription_request req
    join elevenlabs.recording_transcription_response res
        on res.recording_transcription_request_id = req.recording_transcription_request_id
    where req.recording_transcription_attempt_id = _recording_transcription_attempt_id;
$$;

-- process transcription response: verifies signature, stores transcript
create or replace function learning.process_recording_transcription_response(
    _recording_transcription_attempt_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _response elevenlabs.recording_transcription_response;
    _attempt learning.recording_transcription_attempt;
    _task learning.recording_transcription_task;
    _signing_secret text;
    _is_valid boolean;
    _transcription jsonb;
begin
    -- get response via attempt
    _response := elevenlabs.get_recording_transcription_response(_recording_transcription_attempt_id);
    if _response.recording_transcription_response_id is null then
        raise warning 'learning.process_recording_transcription_response.invalid.response_not_found: %', _recording_transcription_attempt_id;
        return jsonb_build_object(
            'status', 'failed',
            'reason', 'response_not_found'
        );
    end if;

    -- get signing secret from config
    _signing_secret := internal.get_config('elevenlabs')->>'webhook_secret';
    if _signing_secret is null or _signing_secret = '' then
        perform learning.record_recording_transcription_attempt_failure(_recording_transcription_attempt_id, 'missing_webhook_secret');
        raise warning 'learning.process_recording_transcription_response.invalid.missing_webhook_secret: %', _recording_transcription_attempt_id;
        return jsonb_build_object(
            'status', 'failed',
            'reason', 'missing_webhook_secret'
        );
    end if;

    -- verify signature
    _is_valid := elevenlabs.transcription_webhook_signature_is_valid(
        _response.raw_body::text,
        _response.signature_header,
        _signing_secret,
        extract(epoch from _response.received_at)::bigint
    );

    if not _is_valid then
        perform learning.record_recording_transcription_attempt_failure(_recording_transcription_attempt_id, 'invalid_signature');
        raise warning 'learning.process_recording_transcription_response.invalid.invalid_signature: %', _recording_transcription_attempt_id;
        return jsonb_build_object(
            'status', 'failed',
            'reason', 'invalid_signature'
        );
    end if;

    -- extract transcription data
    _transcription := _response.raw_body::jsonb->'data'->'transcription';
    if _transcription is null then
        perform learning.record_recording_transcription_attempt_failure(_recording_transcription_attempt_id, 'missing_transcription_data');
        raise warning 'learning.process_recording_transcription_response.invalid.missing_transcription_data: %', _recording_transcription_attempt_id;
        return jsonb_build_object(
            'status', 'failed',
            'reason', 'missing_transcription_data'
        );
    end if;

    -- get attempt and task for recording_id
    _attempt := (
        select a from learning.recording_transcription_attempt a
        where a.recording_transcription_attempt_id = _recording_transcription_attempt_id
    );

    _task := (
        select t from learning.recording_transcription_task t
        where t.recording_transcription_task_id = _attempt.recording_transcription_task_id
    );

    -- check if transcript already exists
    if learning.has_recording_transcript(_task.profile_cue_recording_id) then
        raise warning 'learning.process_recording_transcription_response.transcript_already_exists: %', _task.profile_cue_recording_id;
        return jsonb_build_object(
            'status', 'succeeded',
            'warning', 'transcript_already_exists'
        );
    end if;

    -- store transcript
    insert into learning.recording_transcript (
        profile_cue_recording_id,
        text,
        words,
        language_code,
        language_probability
    ) values (
        _task.profile_cue_recording_id,
        coalesce(_transcription->>'text', ''),
        coalesce(_transcription->'words', '[]'::jsonb),
        _transcription->>'language_code',
        (_transcription->>'language_probability')::numeric
    );

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- =============================================================================
-- supervisor: main orchestration function
-- =============================================================================

create or replace function learning.recording_transcription_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _recording_transcription_task_id bigint := (_payload->>'recording_transcription_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _current_attempt_id bigint := (_payload->>'current_attempt_id')::bigint;
    _time_waiting_seconds integer := coalesce((_payload->>'time_waiting_seconds')::integer, 0);
    _max_runs integer := 100;
    _max_attempts integer := 2;
    _max_wait_seconds integer := 300;
    _facts record;
    _new_attempt_id bigint;
begin
    -- 1. VALIDATION
    if _recording_transcription_task_id is null then
        return jsonb_build_object('status', 'missing_recording_transcription_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'learning.recording_transcription_supervisor.exceeded_max_runs'
            using detail = format('task_id=%s, run_count=%s', _recording_transcription_task_id, _run_count);
    end if;

    -- 2. LOCK
    perform 1
    from learning.recording_transcription_task t
    where t.recording_transcription_task_id = _recording_transcription_task_id
    for update;

    -- 3. FACTS
    _facts := learning.recording_transcription_supervisor_facts(
        _recording_transcription_task_id,
        _current_attempt_id
    );

    -- 4. LOGIC + EFFECTS

    -- terminal: transcript exists
    if _facts.has_transcript then
        return jsonb_build_object('status', 'succeeded');
    end if;

    -- terminal: max attempts exhausted
    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    -- no active attempt -> schedule kickoff
    if _facts.num_attempts = _facts.num_failures then
        _new_attempt_id := learning.schedule_recording_transcription_kickoff(_recording_transcription_task_id);
        perform learning.schedule_recording_transcription_supervisor_recheck(
            _recording_transcription_task_id, _run_count, _new_attempt_id, 0
        );
        return jsonb_build_object('status', 'kickoff_scheduled');
    end if;

    -- active attempt: response received -> process it
    if _facts.attempt_has_response then
        perform learning.process_recording_transcription_response(_current_attempt_id);
        -- reschedule: next run will see transcript (success) or failure (new attempt)
        perform learning.schedule_recording_transcription_supervisor_recheck(
            _recording_transcription_task_id, _run_count, null, 0
        );
        return jsonb_build_object('status', 'response_processed');
    end if;

    -- active attempt: request sent, waiting for webhook
    if _facts.attempt_has_request then
        -- check timeout
        if _time_waiting_seconds >= _max_wait_seconds then
            perform learning.record_recording_transcription_attempt_failure(_current_attempt_id, 'webhook_timeout');
            perform learning.schedule_recording_transcription_supervisor_recheck(
                _recording_transcription_task_id, _run_count, null, 0
            );
            return jsonb_build_object('status', 'webhook_timeout');
        end if;
        -- keep waiting
        perform learning.schedule_recording_transcription_supervisor_recheck(
            _recording_transcription_task_id, _run_count, _current_attempt_id, _time_waiting_seconds
        );
        return jsonb_build_object('status', 'waiting_for_webhook');
    end if;

    -- active attempt: kickoff worker still running
    perform learning.schedule_recording_transcription_supervisor_recheck(
        _recording_transcription_task_id, _run_count, _current_attempt_id, 0
    );
    return jsonb_build_object('status', 'kickoff_in_progress');
end;
$$;

-- =============================================================================
-- api: request transcription
-- =============================================================================

-- facts: check if there's an in-progress transcription task
create or replace function learning.has_in_progress_transcription_task(
    _profile_cue_recording_id bigint
)
returns boolean
language sql
stable
as $$
    select exists (
        select 1
        from learning.recording_transcription_task t
        where t.profile_cue_recording_id = _profile_cue_recording_id
          and not learning.has_recording_transcript(_profile_cue_recording_id)
          and (
              select count(*)
              from learning.recording_transcription_attempt a
              join learning.recording_transcription_attempt_failed f
                  on f.recording_transcription_attempt_id = a.recording_transcription_attempt_id
              where a.recording_transcription_task_id = t.recording_transcription_task_id
          ) < 2
    );
$$;

create or replace function api.request_recording_transcription(
    profile_cue_recording_id bigint
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _authenticated_account_id bigint := auth.jwt_account_id();
    _recording_transcription_task_id bigint;
begin
    -- 1. VALIDATION
    if _authenticated_account_id is null then
        raise exception 'Request Recording Transcription Failed'
            using detail = 'Unauthorized', hint = 'unauthorized';
    end if;

    -- verify recording exists and belongs to user
    if not exists (
        select 1
        from learning.profile_cue_recording pcr
        join learning.profile p on p.profile_id = pcr.profile_id
        where pcr.profile_cue_recording_id = request_recording_transcription.profile_cue_recording_id
          and p.account_id = _authenticated_account_id
    ) then
        raise exception 'Request Recording Transcription Failed'
            using detail = 'Recording not found', hint = 'recording_not_found';
    end if;

    -- 2. FACTS (check existing state)

    -- check for existing transcript
    if learning.has_recording_transcript(profile_cue_recording_id) then
        return jsonb_build_object('status', 'already_transcribed');
    end if;

    -- check for in-progress task
    if learning.has_in_progress_transcription_task(profile_cue_recording_id) then
        return jsonb_build_object('status', 'in_progress');
    end if;

    -- 3. EFFECTS

    -- create new task
    insert into learning.recording_transcription_task (profile_cue_recording_id, created_by)
    values (profile_cue_recording_id, _authenticated_account_id)
    returning recording_transcription_task_id into _recording_transcription_task_id;

    -- enqueue supervisor
    perform queues.enqueue(
        'db_function',
        jsonb_build_object(
            'task_type', 'db_function',
            'db_function', 'learning.recording_transcription_supervisor',
            'recording_transcription_task_id', _recording_transcription_task_id
        ),
        now()
    );

    return jsonb_build_object(
        'status', 'started',
        'recording_transcription_task_id', _recording_transcription_task_id
    );
end;
$$;

-- =============================================================================
-- grants
-- =============================================================================

-- webhook endpoint: anonymous access (ElevenLabs can't authenticate)
grant execute on function api.eleven_labs_transcription_webhook(json) to anon;

-- api endpoints for authenticated users
grant execute on function api.request_recording_transcription(bigint) to authenticated;

-- worker service user grants
grant execute on function learning.get_recording_transcription_kickoff_payload(jsonb) to worker_service_user;
grant execute on function learning.record_recording_transcription_request_success(jsonb) to worker_service_user;
grant execute on function learning.record_recording_transcription_request_failure(jsonb) to worker_service_user;
grant execute on function learning.schedule_recording_transcription_kickoff(bigint) to worker_service_user;
grant execute on function learning.schedule_recording_transcription_supervisor_recheck(bigint, integer, bigint, integer) to worker_service_user;
grant execute on function learning.recording_transcription_supervisor(jsonb) to worker_service_user;
grant execute on function learning.process_recording_transcription_response(bigint) to worker_service_user;

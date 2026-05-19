-- openai responses: generic async OpenAI Responses API foundation
--
-- this migration adds durable facts for background Responses API calls:
-- stage 1: response create succeeded (worker received an OpenAI response id)
-- stage 2: webhook received (OpenAI reported response state changed)
-- stage 3: response retrieved (worker fetched canonical response body)

-- =============================================================================
-- foundation: extend task domain and create openai schema
-- =============================================================================

alter domain queues.task_type drop constraint if exists task_type_allowed_values;

alter domain queues.task_type
    add constraint task_type_allowed_values
    check (value in (
        'db_function',
        'email',
        'sms',
        'file_delete',
        'transcription_kickoff',
        'openai_response_create',
        'openai_response_retrieve'
    ));

create schema if not exists openai;

grant usage on schema openai to worker_service_user;

-- seed openai config
insert into internal.config (key, value)
values (
    'openai',
    '{
        "webhook_secret": "{secrets.openai_webhook_secret}",
        "default_model": "gpt-5.5"
    }'
)
on conflict (key) do nothing;

-- =============================================================================
-- tables (ordered by dependency: task -> attempt -> request/webhook/retrieval)
-- =============================================================================

-- task table: one per logical OpenAI response workflow
create table openai.openai_response_task (
    openai_response_task_id bigserial primary key,
    purpose text not null,
    request_body jsonb not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamp with time zone not null default now(),
    created_by bigint
        references accounts.account(account_id)
        on delete set null
);

-- attempt table: one per OpenAI create attempt
create table openai.openai_response_attempt (
    openai_response_attempt_id bigserial primary key,
    openai_response_task_id bigint not null
        references openai.openai_response_task(openai_response_task_id)
        on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- response requests: tracks successful Responses API create calls
-- written by: openai_response_create worker success handler
create table openai.openai_response_request (
    openai_response_request_id bigserial primary key,
    openai_response_attempt_id bigint not null unique
        references openai.openai_response_attempt(openai_response_attempt_id)
        on delete cascade,
    openai_response_id text not null unique,
    request_body jsonb not null,
    initial_response_body jsonb not null,
    initial_status text,
    created_at timestamp with time zone not null default now()
);

-- raw webhook events from OpenAI
-- written by: webhook endpoint (no verification, just store)
-- uses JSON (not JSONB) to preserve exact bytes for signature verification
create table openai.openai_response_webhook_event (
    openai_response_webhook_event_id bigserial primary key,
    webhook_id text unique,
    openai_response_id text,
    event_type text,
    raw_body json not null,
    webhook_timestamp text not null,
    webhook_signature text not null,
    received_at timestamp with time zone not null default now()
);

create index openai_response_webhook_event_response_id_idx
    on openai.openai_response_webhook_event(openai_response_id);

-- response retrieve requests: tracks that retrieval has been scheduled
create table openai.openai_response_retrieve_request (
    openai_response_attempt_id bigint primary key
        references openai.openai_response_attempt(openai_response_attempt_id)
        on delete cascade,
    created_at timestamp with time zone not null default now()
);

-- response retrievals: canonical response body fetched after webhook/polling
-- written by: openai_response_retrieve worker success handler
create table openai.openai_response_retrieval (
    openai_response_retrieval_id bigserial primary key,
    openai_response_attempt_id bigint not null unique
        references openai.openai_response_attempt(openai_response_attempt_id)
        on delete cascade,
    response_body jsonb not null,
    response_status text,
    retrieved_at timestamp with time zone not null default now()
);

-- failure: any expected provider failure at create/retrieve/supervision stage
create table openai.openai_response_attempt_failed (
    openai_response_attempt_id bigint primary key
        references openai.openai_response_attempt(openai_response_attempt_id)
        on delete cascade,
    error_message text,
    created_at timestamp with time zone not null default now()
);

-- =============================================================================
-- webhook: endpoint stores raw OpenAI events
-- =============================================================================

-- facts: extract headers/body fields and dedupe state for webhook processing
create or replace function openai.openai_response_webhook_facts(
    _webhook_body json,
    out webhook_id text,
    out webhook_timestamp text,
    out webhook_signature text,
    out event_type text,
    out openai_response_id text,
    out webhook_event_already_exists boolean
)
language plpgsql
stable
as $$
begin
    webhook_id := nullif(
        current_setting('request.headers', true)::json->>'webhook-id',
        ''
    );

    webhook_timestamp := coalesce(
        nullif(current_setting('request.headers', true)::json->>'webhook-timestamp', ''),
        'missing-webhook-timestamp'
    );

    webhook_signature := coalesce(
        nullif(current_setting('request.headers', true)::json->>'webhook-signature', ''),
        'missing-webhook-signature'
    );

    event_type := _webhook_body::jsonb->>'type';
    openai_response_id := _webhook_body::jsonb->'data'->>'id';

    webhook_event_already_exists := webhook_id is not null and exists (
        select 1
        from openai.openai_response_webhook_event e
        where e.webhook_id = openai_response_webhook_facts.webhook_id
    );
end;
$$;

-- effect: store webhook event
create or replace function openai.record_openai_response_webhook_event(
    _webhook_id text,
    _openai_response_id text,
    _event_type text,
    _raw_body json,
    _webhook_timestamp text,
    _webhook_signature text
)
returns void
language sql
as $$
    insert into openai.openai_response_webhook_event (
        webhook_id,
        openai_response_id,
        event_type,
        raw_body,
        webhook_timestamp,
        webhook_signature
    ) values (
        _webhook_id,
        _openai_response_id,
        _event_type,
        _raw_body,
        _webhook_timestamp,
        _webhook_signature
    )
    on conflict (webhook_id) do nothing;
$$;

-- =============================================================================
-- webhook: signature verification
-- =============================================================================

create or replace function openai.standard_webhook_secret_key(
    _signing_secret text
)
returns bytea
language plpgsql
immutable
as $$
declare
    _secret text;
begin
    if _signing_secret is null or _signing_secret = '' then
        return null;
    end if;

    _secret := case
        when starts_with(_signing_secret, 'whsec_') then substring(_signing_secret from 7)
        else _signing_secret
    end;

    begin
        return decode(_secret, 'base64');
    exception when others then
        return null;
    end;
end;
$$;

create or replace function openai.standard_webhook_signature_is_valid(
    _raw_response_body text,
    _webhook_id text,
    _webhook_timestamp text,
    _webhook_signature text,
    _signing_secret text,
    _current_timestamp_epoch bigint,
    _timestamp_tolerance_seconds integer default 300
)
returns boolean
language plpgsql
immutable
as $$
/**
 * Verifies Standard Webhooks signatures as used by OpenAI.
 *
 * This function has unit tests!
 * See: openai.standard_webhook_signature_is_valid_run_unit_tests
 *
 * Headers:
 *   webhook-id: unique delivery/event id
 *   webhook-timestamp: unix timestamp in seconds
 *   webhook-signature: space-delimited signatures, e.g. "v1,<base64>"
 *
 * Signed content: webhook-id || "." || webhook-timestamp || "." || raw_body
 * HMAC key: base64-decoded signing secret after stripping the "whsec_" prefix
 */
declare
    _received_timestamp bigint;
    _secret_key bytea;
    _signed_content text;
    _expected_signature text;
    _candidate text;
begin
    -- 1. validate required values
    if _raw_response_body is null
        or _webhook_id is null or _webhook_id = ''
        or _webhook_timestamp is null or _webhook_timestamp = ''
        or _webhook_signature is null or _webhook_signature = ''
        or _signing_secret is null or _signing_secret = ''
    then
        return false;
    end if;

    -- 2. parse timestamp
    begin
        _received_timestamp := _webhook_timestamp::bigint;
    exception when others then
        return false;
    end;

    -- 3. check timestamp tolerance (replay attack protection)
    if abs(_current_timestamp_epoch - _received_timestamp) > _timestamp_tolerance_seconds then
        return false;
    end if;

    -- 4. decode Standard Webhooks secret
    _secret_key := openai.standard_webhook_secret_key(_signing_secret);
    if _secret_key is null then
        return false;
    end if;

    -- 5. compute expected signature
    _signed_content := _webhook_id || '.' || _webhook_timestamp || '.' || _raw_response_body;
    _expected_signature := 'v1,' || encode(
        public.hmac(convert_to(_signed_content, 'utf8'), _secret_key, 'sha256'),
        'base64'
    );

    -- 6. compare against all signatures (supports secret rotation)
    foreach _candidate in array string_to_array(_webhook_signature, ' ')
    loop
        if _candidate = _expected_signature then
            return true;
        end if;
    end loop;

    return false;
end;
$$;

create or replace function openai.standard_webhook_signature_is_valid_run_unit_tests()
returns table(test text, passed boolean)
language plpgsql
immutable
as $$
declare
    _secret text := 'whsec_' || encode(convert_to('test secret', 'utf8'), 'base64');
    _body text := '{"object":"event","id":"evt_test","type":"response.completed","data":{"id":"resp_test"}}';
    _webhook_id text := 'evt_test';
    _webhook_timestamp text := '1752155502';
    _signature text;
begin
    _signature := 'v1,' || encode(
        public.hmac(
            convert_to(_webhook_id || '.' || _webhook_timestamp || '.' || _body, 'utf8'),
            openai.standard_webhook_secret_key(_secret),
            'sha256'
        ),
        'base64'
    );

    -- test 1: valid signature, exact timestamp
    return query
    select
        'valid signature, exact timestamp -> valid'::text,
        openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            _webhook_timestamp,
            _signature,
            _secret,
            1752155502
        );

    -- test 2: valid signature among multiple signatures
    return query
    select
        'valid signature among multiple signatures -> valid'::text,
        openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            _webhook_timestamp,
            'v1,invalid ' || _signature,
            _secret,
            1752155502
        );

    -- test 3: invalid - wrong secret
    return query
    select
        'wrong secret -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            _webhook_timestamp,
            _signature,
            'whsec_' || encode(convert_to('wrong secret', 'utf8'), 'base64'),
            1752155502
        );

    -- test 4: invalid - modified body
    return query
    select
        'modified body -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            '{"object":"event","id":"evt_test","type":"response.completed","data":{"id":"resp_modified"}}',
            _webhook_id,
            _webhook_timestamp,
            _signature,
            _secret,
            1752155502
        );

    -- test 5: invalid - timestamp too old
    return query
    select
        'timestamp too old -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            _webhook_timestamp,
            _signature,
            _secret,
            1752156103,
            300
        );

    -- test 6: invalid - timestamp too far in future
    return query
    select
        'timestamp too far in future -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            _webhook_timestamp,
            _signature,
            _secret,
            1752154901,
            300
        );

    -- test 7: invalid - missing webhook id
    return query
    select
        'missing webhook id -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            _body,
            null,
            _webhook_timestamp,
            _signature,
            _secret,
            1752155502
        );

    -- test 8: invalid - malformed timestamp
    return query
    select
        'malformed timestamp -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            'not-a-timestamp',
            _signature,
            _secret,
            1752155502
        );

    -- test 9: invalid - malformed secret
    return query
    select
        'malformed secret -> fails'::text,
        not openai.standard_webhook_signature_is_valid(
            _body,
            _webhook_id,
            _webhook_timestamp,
            _signature,
            'whsec_not-base64',
            1752155502
        );
end;
$$;

-- api: webhook endpoint
-- function called by PostgREST: POST /rpc/openai_webhook
-- anonymous access required (OpenAI cannot authenticate with our JWT)
-- this function does NO verification - just stores raw data and returns 200
-- CRITICAL: use JSON parameter type (not JSONB) to preserve exact formatting
create or replace function api.openai_webhook(
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
    _facts := openai.openai_response_webhook_facts(_webhook_body);

    -- 2. LOGIC
    if _facts.webhook_event_already_exists then
        return jsonb_build_object(
            'status', 'received',
            'warning', 'webhook_event_already_exists'
        );
    end if;

    -- 3. EFFECT
    perform openai.record_openai_response_webhook_event(
        _facts.webhook_id,
        _facts.openai_response_id,
        _facts.event_type,
        _webhook_body,
        _facts.webhook_timestamp,
        _facts.webhook_signature
    );

    return jsonb_build_object('status', 'received');
end;
$$;

-- =============================================================================
-- response create/retrieve: handlers for worker tasks
-- =============================================================================

-- facts: get Responses API create payload from attempt_id
create or replace function openai.get_openai_response_create_payload_facts(
    _openai_response_attempt_id bigint,
    out request_body jsonb
)
language sql
stable
as $$
    select t.request_body
    from openai.openai_response_attempt a
    join openai.openai_response_task t
        on t.openai_response_task_id = a.openai_response_task_id
    where a.openai_response_attempt_id = _openai_response_attempt_id;
$$;

-- before handler: build worker payload for POST /v1/responses
create or replace function openai.get_openai_response_create_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _openai_response_attempt_id bigint := (_payload->>'openai_response_attempt_id')::bigint;
    _facts record;
begin
    -- 1. VALIDATION
    if _openai_response_attempt_id is null then
        return jsonb_build_object('status', 'missing_openai_response_attempt_id');
    end if;

    -- 2. FACTS
    _facts := openai.get_openai_response_create_payload_facts(_openai_response_attempt_id);

    -- 3. LOGIC
    if _facts.request_body is null then
        return jsonb_build_object('status', 'openai_response_attempt_not_found');
    end if;

    if _facts.request_body->'background' is distinct from 'true'::jsonb then
        return jsonb_build_object('status', 'background_true_required');
    end if;

    -- 4. OUTPUT
    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'openai_response_attempt_id', _openai_response_attempt_id,
            'request_body', _facts.request_body
        )
    );
end;
$$;

-- success handler: record Responses API create success
-- receives: { original_payload: { openai_response_attempt_id, ... }, worker_payload: { openai_response_id, status, response_body } }
create or replace function openai.record_openai_response_create_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _openai_response_attempt_id bigint := (_payload->'original_payload'->>'openai_response_attempt_id')::bigint;
    _openai_response_id text := _payload->'worker_payload'->>'openai_response_id';
    _response_status text := _payload->'worker_payload'->>'status';
    _response_body jsonb := _payload->'worker_payload'->'response_body';
    _facts record;
begin
    -- 1. VALIDATION
    if _openai_response_attempt_id is null then
        return jsonb_build_object('status', 'missing_openai_response_attempt_id');
    end if;

    if _openai_response_id is null or _openai_response_id = '' then
        return jsonb_build_object('status', 'missing_openai_response_id');
    end if;

    if _response_body is null then
        return jsonb_build_object('status', 'missing_response_body');
    end if;

    -- 2. FACTS
    _facts := openai.get_openai_response_create_payload_facts(_openai_response_attempt_id);

    -- 3. LOGIC
    if _facts.request_body is null then
        return jsonb_build_object('status', 'openai_response_attempt_not_found');
    end if;

    -- 4. EFFECT
    insert into openai.openai_response_request (
        openai_response_attempt_id,
        openai_response_id,
        request_body,
        initial_response_body,
        initial_status
    ) values (
        _openai_response_attempt_id,
        _openai_response_id,
        _facts.request_body,
        _response_body,
        _response_status
    )
    on conflict (openai_response_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- error handler: record Responses API create failure
-- receives: { original_payload: { openai_response_attempt_id, ... }, error: "..." }
create or replace function openai.record_openai_response_create_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _openai_response_attempt_id bigint := (_payload->'original_payload'->>'openai_response_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _openai_response_attempt_id is null then
        return jsonb_build_object('status', 'missing_openai_response_attempt_id');
    end if;

    perform openai.record_openai_response_attempt_failure(
        _openai_response_attempt_id,
        _error_message
    );

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- facts: get Responses API retrieve payload from attempt_id
create or replace function openai.get_openai_response_retrieve_payload_facts(
    _openai_response_attempt_id bigint,
    out openai_response_id text
)
language sql
stable
as $$
    select req.openai_response_id
    from openai.openai_response_request req
    where req.openai_response_attempt_id = _openai_response_attempt_id;
$$;

-- before handler: build worker payload for GET /v1/responses/{response_id}
create or replace function openai.get_openai_response_retrieve_payload(
    _payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
as $$
declare
    _openai_response_attempt_id bigint := (_payload->>'openai_response_attempt_id')::bigint;
    _facts record;
begin
    -- 1. VALIDATION
    if _openai_response_attempt_id is null then
        return jsonb_build_object('status', 'missing_openai_response_attempt_id');
    end if;

    -- 2. FACTS
    _facts := openai.get_openai_response_retrieve_payload_facts(_openai_response_attempt_id);

    -- 3. LOGIC
    if _facts.openai_response_id is null or _facts.openai_response_id = '' then
        return jsonb_build_object('status', 'openai_response_request_not_found');
    end if;

    -- 4. OUTPUT
    return jsonb_build_object(
        'status', 'succeeded',
        'payload', jsonb_build_object(
            'openai_response_attempt_id', _openai_response_attempt_id,
            'openai_response_id', _facts.openai_response_id
        )
    );
end;
$$;

-- success handler: record canonical Responses API retrieval
-- receives: { original_payload: { openai_response_attempt_id, ... }, worker_payload: { openai_response_id, status, response_body } }
create or replace function openai.record_openai_response_retrieve_success(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _openai_response_attempt_id bigint := (_payload->'original_payload'->>'openai_response_attempt_id')::bigint;
    _response_status text := _payload->'worker_payload'->>'status';
    _response_body jsonb := _payload->'worker_payload'->'response_body';
begin
    -- 1. VALIDATION
    if _openai_response_attempt_id is null then
        return jsonb_build_object('status', 'missing_openai_response_attempt_id');
    end if;

    if _response_body is null then
        return jsonb_build_object('status', 'missing_response_body');
    end if;

    -- 2. EFFECT
    insert into openai.openai_response_retrieval (
        openai_response_attempt_id,
        response_body,
        response_status
    ) values (
        _openai_response_attempt_id,
        _response_body,
        _response_status
    )
    on conflict (openai_response_attempt_id) do nothing;

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- error handler: record Responses API retrieve failure
-- receives: { original_payload: { openai_response_attempt_id, ... }, error: "..." }
create or replace function openai.record_openai_response_retrieve_failure(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _openai_response_attempt_id bigint := (_payload->'original_payload'->>'openai_response_attempt_id')::bigint;
    _error_message text := _payload->>'error';
begin
    if _openai_response_attempt_id is null then
        return jsonb_build_object('status', 'missing_openai_response_attempt_id');
    end if;

    perform openai.record_openai_response_attempt_failure(
        _openai_response_attempt_id,
        _error_message
    );

    return jsonb_build_object('status', 'succeeded');
end;
$$;

-- effect: schedule a Responses API create attempt
create or replace function openai.schedule_openai_response_create(
    _openai_response_task_id bigint
)
returns bigint
language plpgsql
security definer
as $$
declare
    _openai_response_attempt_id bigint;
begin
    insert into openai.openai_response_attempt (openai_response_task_id)
    values (_openai_response_task_id)
    returning openai_response_attempt_id into _openai_response_attempt_id;

    perform queues.enqueue(
        'openai_response_create',
        jsonb_build_object(
            'task_type', 'openai_response_create',
            'openai_response_attempt_id', _openai_response_attempt_id,
            'before_handler', 'openai.get_openai_response_create_payload',
            'success_handler', 'openai.record_openai_response_create_success',
            'error_handler', 'openai.record_openai_response_create_failure'
        ),
        now()
    );

    return _openai_response_attempt_id;
end;
$$;

-- effect: schedule canonical Responses API retrieval for an existing attempt
create or replace function openai.schedule_openai_response_retrieve(
    _openai_response_attempt_id bigint
)
returns void
language plpgsql
security definer
as $$
declare
    _scheduled_attempt_id bigint;
begin
    insert into openai.openai_response_retrieve_request (
        openai_response_attempt_id
    ) values (
        _openai_response_attempt_id
    )
    on conflict (openai_response_attempt_id) do nothing
    returning openai_response_attempt_id into _scheduled_attempt_id;

    if _scheduled_attempt_id is null then
        return;
    end if;

    perform queues.enqueue(
        'openai_response_retrieve',
        jsonb_build_object(
            'task_type', 'openai_response_retrieve',
            'openai_response_attempt_id', _openai_response_attempt_id,
            'before_handler', 'openai.get_openai_response_retrieve_payload',
            'success_handler', 'openai.record_openai_response_retrieve_success',
            'error_handler', 'openai.record_openai_response_retrieve_failure'
        ),
        now()
    );
end;
$$;

-- =============================================================================
-- generic facts/effects for future OpenAI response supervisors
-- =============================================================================

-- facts: all generic response task facts in one function
create or replace function openai.openai_response_supervisor_facts(
    _openai_response_task_id bigint,
    _current_attempt_id bigint default null,
    out openai_response_attempt_id bigint,
    out num_attempts integer,
    out num_failures integer,
    out attempt_has_request boolean,
    out attempt_has_completion_event boolean,
    out attempt_has_terminal_event boolean,
    out terminal_event_type text,
    out terminal_event_is_valid boolean,
    out attempt_has_retrieve_request boolean,
    out attempt_has_retrieval boolean,
    out attempt_has_failed boolean
)
language plpgsql
stable
as $$
declare
    _openai_response_id text;
    _terminal_event openai.openai_response_webhook_event;
    _signing_secret text;
begin
    openai_response_attempt_id := coalesce(
        _current_attempt_id,
        (
            select a.openai_response_attempt_id
            from openai.openai_response_attempt a
            where a.openai_response_task_id = _openai_response_task_id
              and not exists (
                  select 1
                  from openai.openai_response_attempt_failed f
                  where f.openai_response_attempt_id = a.openai_response_attempt_id
              )
            order by a.created_at desc, a.openai_response_attempt_id desc
            limit 1
        )
    );

    num_attempts := (
        select count(*)::integer
        from openai.openai_response_attempt a
        where a.openai_response_task_id = _openai_response_task_id
    );

    num_failures := (
        select count(*)::integer
        from openai.openai_response_attempt a
        join openai.openai_response_attempt_failed f
            on f.openai_response_attempt_id = a.openai_response_attempt_id
        where a.openai_response_task_id = _openai_response_task_id
    );

    _openai_response_id := (
        select req.openai_response_id
        from openai.openai_response_request req
        where req.openai_response_attempt_id = openai_response_supervisor_facts.openai_response_attempt_id
    );

    attempt_has_request := _openai_response_id is not null;

    attempt_has_completion_event := exists (
        select 1
        from openai.openai_response_webhook_event e
        where e.openai_response_id = _openai_response_id
          and e.event_type = 'response.completed'
    );

    attempt_has_terminal_event := exists (
        select 1
        from openai.openai_response_webhook_event e
        where e.openai_response_id = _openai_response_id
          and e.event_type in (
              'response.completed',
              'response.failed',
              'response.incomplete',
              'response.cancelled'
          )
    );

    attempt_has_retrieval := exists (
        select 1
        from openai.openai_response_retrieval r
        where r.openai_response_attempt_id = openai_response_supervisor_facts.openai_response_attempt_id
    );

    attempt_has_failed := exists (
        select 1
        from openai.openai_response_attempt_failed f
        where f.openai_response_attempt_id = openai_response_supervisor_facts.openai_response_attempt_id
    );

    attempt_has_retrieve_request := exists (
        select 1
        from openai.openai_response_retrieve_request rr
        where rr.openai_response_attempt_id = openai_response_supervisor_facts.openai_response_attempt_id
    );

    select e.*
    into _terminal_event
    from openai.openai_response_webhook_event e
    where e.openai_response_id = _openai_response_id
      and e.event_type in (
          'response.completed',
          'response.failed',
          'response.incomplete',
          'response.cancelled'
      )
    order by e.received_at desc, e.openai_response_webhook_event_id desc
    limit 1;

    terminal_event_type := _terminal_event.event_type;
    _signing_secret := internal.get_config('openai')->>'webhook_secret';

    terminal_event_is_valid := case
        when _terminal_event.openai_response_webhook_event_id is null then false
        else openai.standard_webhook_signature_is_valid(
            _terminal_event.raw_body::text,
            _terminal_event.webhook_id,
            _terminal_event.webhook_timestamp,
            _terminal_event.webhook_signature,
            _signing_secret,
            extract(epoch from _terminal_event.received_at)::bigint
        )
    end;
end;
$$;

-- effect: record attempt failure
create or replace function openai.record_openai_response_attempt_failure(
    _openai_response_attempt_id bigint,
    _error_message text
)
returns void
language sql
as $$
    insert into openai.openai_response_attempt_failed (
        openai_response_attempt_id,
        error_message
    ) values (
        _openai_response_attempt_id,
        _error_message
    )
    on conflict (openai_response_attempt_id) do nothing;
$$;

-- effect: schedule supervisor recheck
create or replace function openai.schedule_openai_response_supervisor_recheck(
    _openai_response_task_id bigint,
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
            'db_function', 'openai.openai_response_supervisor',
            'openai_response_task_id', _openai_response_task_id,
            'run_count', _run_count + 1,
            'current_attempt_id', _current_attempt_id,
            'time_waiting_seconds', _time_waiting_seconds + _recheck_interval_seconds
        ),
        _next_check_at
    );
end;
$$;

-- supervisor: orchestrates generic OpenAI background response lifecycle
create or replace function openai.openai_response_supervisor(
    _payload jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
    _openai_response_task_id bigint := (_payload->>'openai_response_task_id')::bigint;
    _run_count integer := coalesce((_payload->>'run_count')::integer, 0);
    _current_attempt_id bigint := (_payload->>'current_attempt_id')::bigint;
    _time_waiting_seconds integer := coalesce((_payload->>'time_waiting_seconds')::integer, 0);
    _max_runs integer := 200;
    _max_attempts integer := 2;
    _max_wait_seconds integer := 900;
    _facts record;
    _new_attempt_id bigint;
begin
    -- 1. VALIDATION
    if _openai_response_task_id is null then
        return jsonb_build_object('status', 'missing_openai_response_task_id');
    end if;

    if _run_count >= _max_runs then
        raise exception 'openai.openai_response_supervisor.exceeded_max_runs'
            using detail = format('task_id=%s, run_count=%s', _openai_response_task_id, _run_count);
    end if;

    -- 2. LOCK
    perform 1
    from openai.openai_response_task t
    where t.openai_response_task_id = _openai_response_task_id
    for update;

    -- 3. FACTS
    _facts := openai.openai_response_supervisor_facts(
        _openai_response_task_id,
        _current_attempt_id
    );

    -- 4. LOGIC + EFFECTS

    -- terminal: canonical response has been retrieved
    if _facts.attempt_has_retrieval then
        return jsonb_build_object('status', 'succeeded');
    end if;

    -- terminal: max attempts exhausted
    if _facts.num_failures >= _max_attempts then
        return jsonb_build_object('status', 'max_attempts_reached');
    end if;

    -- no active attempt -> schedule Responses API create
    if _facts.num_attempts = _facts.num_failures then
        _new_attempt_id := openai.schedule_openai_response_create(_openai_response_task_id);
        perform openai.schedule_openai_response_supervisor_recheck(
            _openai_response_task_id, _run_count, _new_attempt_id, 0
        );
        return jsonb_build_object('status', 'create_scheduled');
    end if;

    -- create worker still running
    if not _facts.attempt_has_request then
        perform openai.schedule_openai_response_supervisor_recheck(
            _openai_response_task_id, _run_count, _facts.openai_response_attempt_id, 0
        );
        return jsonb_build_object('status', 'create_in_progress');
    end if;

    -- OpenAI delivered a terminal webhook event
    if _facts.attempt_has_terminal_event then
        if not _facts.terminal_event_is_valid then
            perform openai.record_openai_response_attempt_failure(
                _facts.openai_response_attempt_id,
                'invalid_webhook_signature'
            );
            perform openai.schedule_openai_response_supervisor_recheck(
                _openai_response_task_id, _run_count, null, 0
            );
            return jsonb_build_object('status', 'invalid_webhook_signature');
        end if;

        if _facts.terminal_event_type <> 'response.completed' then
            perform openai.record_openai_response_attempt_failure(
                _facts.openai_response_attempt_id,
                _facts.terminal_event_type
            );
            perform openai.schedule_openai_response_supervisor_recheck(
                _openai_response_task_id, _run_count, null, 0
            );
            return jsonb_build_object(
                'status', 'terminal_event_failure',
                'event_type', _facts.terminal_event_type
            );
        end if;

        if not _facts.attempt_has_retrieve_request then
            perform openai.schedule_openai_response_retrieve(_facts.openai_response_attempt_id);
        end if;

        perform openai.schedule_openai_response_supervisor_recheck(
            _openai_response_task_id, _run_count, _facts.openai_response_attempt_id, 0
        );
        return jsonb_build_object('status', 'retrieve_scheduled');
    end if;

    -- create succeeded, waiting for webhook
    if _time_waiting_seconds >= _max_wait_seconds then
        perform openai.record_openai_response_attempt_failure(
            _facts.openai_response_attempt_id,
            'webhook_timeout'
        );
        perform openai.schedule_openai_response_supervisor_recheck(
            _openai_response_task_id, _run_count, null, 0
        );
        return jsonb_build_object('status', 'webhook_timeout');
    end if;

    perform openai.schedule_openai_response_supervisor_recheck(
        _openai_response_task_id, _run_count, _facts.openai_response_attempt_id, _time_waiting_seconds
    );
    return jsonb_build_object('status', 'waiting_for_webhook');
end;
$$;

-- =============================================================================
-- grants
-- =============================================================================

-- webhook endpoint: anonymous access (OpenAI cannot authenticate)
grant execute on function api.openai_webhook(json) to anon;

-- worker service user grants for future processors/supervisors
grant execute on function openai.standard_webhook_secret_key(text) to worker_service_user;
grant execute on function openai.standard_webhook_signature_is_valid(text, text, text, text, text, bigint, integer) to worker_service_user;
grant execute on function openai.openai_response_webhook_facts(json) to worker_service_user;
grant execute on function openai.record_openai_response_webhook_event(text, text, text, json, text, text) to worker_service_user;
grant execute on function openai.get_openai_response_create_payload_facts(bigint) to worker_service_user;
grant execute on function openai.get_openai_response_create_payload(jsonb) to worker_service_user;
grant execute on function openai.record_openai_response_create_success(jsonb) to worker_service_user;
grant execute on function openai.record_openai_response_create_failure(jsonb) to worker_service_user;
grant execute on function openai.get_openai_response_retrieve_payload_facts(bigint) to worker_service_user;
grant execute on function openai.get_openai_response_retrieve_payload(jsonb) to worker_service_user;
grant execute on function openai.record_openai_response_retrieve_success(jsonb) to worker_service_user;
grant execute on function openai.record_openai_response_retrieve_failure(jsonb) to worker_service_user;
grant execute on function openai.schedule_openai_response_create(bigint) to worker_service_user;
grant execute on function openai.schedule_openai_response_retrieve(bigint) to worker_service_user;
grant execute on function openai.openai_response_supervisor_facts(bigint, bigint) to worker_service_user;
grant execute on function openai.record_openai_response_attempt_failure(bigint, text) to worker_service_user;
grant execute on function openai.schedule_openai_response_supervisor_recheck(bigint, integer, bigint, integer) to worker_service_user;
grant execute on function openai.openai_response_supervisor(jsonb) to worker_service_user;

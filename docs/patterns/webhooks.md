## Webhooks

Status: current
Last verified: 2026-02-01

← Back to [`docs/patterns/README.md`](./README.md)

### Why this pattern

Third-party services often deliver results via webhooks. These webhooks arrive at unpredictable times, may be retried, and require signature verification. A naive approach that verifies and processes inline can lose data if verification has bugs, cause slow responses that trigger retries, or create race conditions with our supervisors.

### The pattern: store first, verify later

1. **Receive webhook** - Accept the raw payload and signature header
2. **Store immediately** - Save to database without verification, return 200 fast
3. **Supervisor verifies** - On next recheck, supervisor finds the response and verifies signature
4. **Process on valid** - If valid, extract data and mark success; if invalid, mark failure for retry

```
Third Party                PostgREST                 PostgreSQL               Supervisor
    |                          |                          |                      |
    |  POST /rpc/webhook       |                          |                      |
    |  Signature: ...          |                          |                      |
    |  { raw body }            |                          |                      |
    |------------------------->|                          |                      |
    |                          |  api.webhook_handler()   |                      |
    |                          |------------------------->|                      |
    |                          |                          |  INSERT raw_body,    |
    |                          |                          |  signature_header    |
    |                          |                          |  (no verification)   |
    |                          |                          |                      |
    |                          |  200 OK                  |                      |
    |<-------------------------|                          |                      |
    |                          |                          |                      |
    |                          |                          |      (already scheduled)
    |                          |                          |<---------------------|
    |                          |                          |  Supervisor recheck  |
    |                          |                          |                      |
    |                          |                          |  Response exists?    |
    |                          |                          |  Yes -> Verify sig   |
    |                          |                          |  Valid -> Process    |
    |                          |                          |--------------------->|
    |                          |                          |                      |
```

### Why this approach

**Never loses data** - Even if verification logic has bugs, the raw payload is preserved for debugging and replay.

**Fast response** - Returns 200 immediately, preventing the third party from retrying due to timeouts.

**Debuggable** - Raw payloads preserved exactly as received for inspection.

**Secure** - Verification happens in a controlled environment (supervisor) with access to secrets.

**Race-condition safe** - Supervisor already polls for completion; webhook just provides data.

### Implementation details

#### Webhook endpoint function

Use `JSON` parameter type (not JSONB) to preserve exact formatting for signature verification:

```sql
CREATE OR REPLACE FUNCTION api.my_webhook(
    JSON  -- CRITICAL: JSON not JSONB, preserves exact bytes
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
    _webhook_body JSON := $1;
    _signature_header TEXT;
BEGIN
    -- Get signature from HTTP header
    _signature_header := coalesce(
        current_setting('request.headers', true)::json->>'my-signature-header',
        'missing-signature'
    );

    -- Store raw response (supervisor will verify)
    INSERT INTO my_schema.webhook_response (
        raw_body,
        signature_header
    ) VALUES (
        _webhook_body,
        _signature_header
    );

    RETURN jsonb_build_object('status', 'received');
END;
$$;

-- Anonymous access required (third party can't authenticate with JWT)
GRANT EXECUTE ON FUNCTION api.my_webhook(JSON) TO anon;
```

#### Why JSON not JSONB

The `raw_body` column uses `JSON` instead of `JSONB` because:

1. **Signature verification requires exact bytes** - JSONB normalizes whitespace and key ordering
2. **Debugging** - See exactly what the third party sent
3. **Audit trail** - Preserve original payload for disputes

After verification, you can parse the JSON and store structured data in JSONB columns for querying.

#### PostgREST header access

```sql
-- CORRECT: headers stored as JSON object
current_setting('request.headers', true)::json->>'my-header-name'

-- WRONG: doesn't work
current_setting('request.header.my-header-name', true)
```

### Supervisor integration

The supervisor doesn't need special webhook-handling code. It simply:

1. Checks if a response exists for the current attempt
2. If yes, verifies signature and processes
3. If no, reschedules itself to check again later
4. After timeout (e.g., 5 minutes), marks attempt as failed

```sql
-- In supervisor
IF _facts.request_succeeded AND _facts.response_received THEN
    _process_result := my_schema.process_webhook_response(
        _facts.attempt_id
    );
    -- ...
END IF;

IF _facts.request_succeeded AND NOT _facts.response_received THEN
    -- Check timeout
    IF _time_waiting_seconds >= _max_wait_seconds THEN
        -- Record failure due to timeout
        INSERT INTO my_schema.attempt_failed (attempt_id, error_message)
        VALUES (_attempt_id, 'no response within 5 minutes');
        -- ...
    END IF;
    -- Still waiting, reschedule
    PERFORM my_schema.schedule_supervisor_recheck(...);
END IF;
```

### Example implementations

- **ElevenLabs transcription** ([`postgres/migrations/1756075800_recording_transcription.sql`](../../postgres/migrations/1756075800_recording_transcription.sql)): `api.eleven_labs_transcription_webhook()` stores in `elevenlabs.recording_transcription_response`, supervisor verifies via `elevenlabs.transcription_webhook_signature_is_valid()`

### See also

- Supervisors: [`./supervisors.md`](./supervisors.md)
- Facts, Logic, Effects: [`./facts-logic-effects.md`](./facts-logic-effects.md)
- Transcription worker: [`../worker/transcription.md`](../worker/transcription.md)

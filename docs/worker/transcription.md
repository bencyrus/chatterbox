## Worker Transcription Processor

Status: current
Last verified: 2026-02-01

← Back to [`docs/worker/README.md`](./README.md)

### Why this exists

- Handle `transcription_kickoff` tasks that initiate async transcription via ElevenLabs Speech-to-Text API.
- Part of a two-stage success model where the worker kicks off the request and a webhook delivers the result.

### Two-stage success model

Unlike email/SMS which complete synchronously, transcription uses an async webhook pattern:

1. **Stage 1 (Request)**: Worker calls ElevenLabs API with `webhook=true`, records request in `elevenlabs.recording_transcription_request`
2. **Stage 2 (Response)**: ElevenLabs calls our webhook endpoint, supervisor verifies and stores transcript

The supervisor polls every 3 seconds for up to 5 minutes waiting for the webhook. If no response arrives within 5 minutes, the attempt is marked as failed and retried (up to 2 attempts).

### Flow

1. Parse task payload for handler names; require `before_handler`
2. Call `before_handler` (DB) to get `TranscriptionKickoffPayload { file_id, recording_transcription_attempt_id }`
3. Request signed download URL from files service
4. Call ElevenLabs API with:
   - `model_id: scribe_v2`
   - `cloud_storage_url`: signed GCS URL
   - `webhook: true`
   - `webhook_metadata: { recording_transcription_attempt_id }`
   - `tag_audio_events: true`
   - `timestamps_granularity: word`
5. Return `{ request_id }` for the success handler to record
6. Call `success_handler` or `error_handler` in DB

### Webhook handling

The webhook endpoint (`api.eleven_labs_transcription_webhook`) is separate from this processor:

- Receives POST from ElevenLabs with raw JSON body and signature header
- Looks up internal request record by `elevenlabs_request_id` from webhook body
- Stores raw data in `elevenlabs.recording_transcription_response` (no verification)
- Returns 200 immediately

The supervisor then:
- Detects the response via `attempt_has_response` fact
- Calls `learning.process_recording_transcription_response()` which:
  - Reads webhook secret from `internal.config` table
  - Verifies signature using `elevenlabs.transcription_webhook_signature_is_valid()`
  - Stores transcript in `learning.recording_transcript`
- Terminal success is inferred from existence of `learning.recording_transcript` record

See [Webhooks Pattern](../patterns/webhooks.md) for the store-first-verify-later approach.

### Code map

- Processor: [`worker/internal/processing/transcription_kickoff_processor.go`](../../worker/internal/processing/transcription_kickoff_processor.go)
- Types: [`worker/internal/types/transcription.go`](../../worker/internal/types/transcription.go)
- Files service: [`worker/internal/services/files/service.go`](../../worker/internal/services/files/service.go) (`GetSignedDownloadURL`)
- Migration: [`postgres/migrations/1756075800_recording_transcription.sql`](../../postgres/migrations/1756075800_recording_transcription.sql)

### Configuration

Required environment variable for worker:

```bash
ELEVENLABS_API_KEY=your_api_key_here
```

Webhook secret is stored in the `internal.config` table (seeded by migration):

```sql
-- The migration seeds this with a placeholder that gets replaced by your secrets
insert into internal.config (key, value)
values ('elevenlabs', '{ "webhook_secret": "{secrets.elevenlabs_webhook_secret}" }');

-- Read at runtime via:
internal.get_config('elevenlabs')->>'webhook_secret'
```

### ElevenLabs dashboard setup

1. Go to ElevenLabs Dashboard > Settings > Webhooks
2. Create webhook with URL: `https://your-domain.com/rpc/eleven_labs_transcription_webhook`
3. Enable HMAC signing
4. Associate with Speech-to-Text events
5. Copy signing secret to your secrets configuration (will be injected into `internal.config`)

### Notes

- The worker never enqueues; scheduling/retries are handled by DB supervisor
- Uses `scribe_v2` model for best accuracy
- Audio files can be up to 2GB and 10 hours in duration
- Provider errors are passed to `error_handler` which records in `learning.recording_transcription_attempt_failed`

### See also

- Lifecycle: [`./lifecycle.md`](./lifecycle.md)
- Payloads: [`./payloads.md`](./payloads.md)
- Webhooks pattern: [`../patterns/webhooks.md`](../patterns/webhooks.md)
- Supervisors pattern: [`../patterns/supervisors.md`](../patterns/supervisors.md)

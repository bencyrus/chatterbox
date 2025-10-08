## Worker Email Processor

Status: current
Last verified: 2025-10-08

← Back to [`docs/worker/README.md`](./README.md)

### Why this exists

- Handle `email` channel tasks with DB-driven payloads and Resend as provider.

### Flow

- Parse task payload for handler names; require `before_handler`.
- Call `before_handler` (DB) to get `EmailPayload { message_id, from_address, to_address, subject, html }`.
- Send email via Resend HTTP API; propagate the provider response on success.
- Call `success_handler` or `error_handler` in DB with `{ original_payload, worker_payload | error }`.

### Code map

- Processor: `internal/processing/email_processor.go`
- Service (Resend): `internal/services/email/service.go`
- Types: `internal/types/task.go` (EmailPayload)

### Notes

- The worker never enqueues; scheduling/retries are handled by DB supervisors.
- Provider errors are appended to `queues.error` and passed to `error_handler`.

### See also

- Lifecycle: [`./lifecycle.md`](./lifecycle.md)
- SMS: [`./sms.md`](./sms.md)

## Worker SMS Processor

Purpose

- Process `sms` tasks using a placeholder provider; mirrors the email flow with channel‑specific payload.

Flow

- Require `before_handler`; call DB to build `SMSPayload { message_id, to_number, body }`.
- Send SMS via a simulated provider (logs payload; returns a synthetic response).
- Call `success_handler` or `error_handler` with `{ original_payload, worker_payload | error }`.

Code map

- Processor: `internal/processing/sms_processor.go`
- Service (simulated): `internal/services/sms/service.go`
- Types: `internal/types/task.go` (SMSPayload)

Notes

- Placeholder implementation is suitable for local/testing; production providers can replace `internal/services/sms` with real clients.

Navigate

- Lifecycle: [`./lifecycle.md`](./lifecycle.md)
- Email: [`./email.md`](./email.md)

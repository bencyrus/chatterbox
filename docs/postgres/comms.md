## Communications (email and SMS)

Purpose

- Explain the `comms` domain built on the generic queue, including data model, templates, kickoff helpers, supervisors, handlers, and examples.

Data model

- `comms.message`
  - Base message record with `message_id` and `channel in ('email','sms')`.
- `comms.email_message`
  - Per-email payload: `from_address, to_address, subject, html`.
- `comms.sms_message`
  - Per-sms payload: `to_number, body`.
- Templates (optional, used by API helpers)
  - `comms.email_template`, `comms.sms_template` with `template_key`, `subject`/`body`, and `body_params`.

Process model (facts)

- Email
  - Root: `comms.send_email_task`
  - Facts: `..._scheduled` (append-only), `..._failed` (append-only), `..._succeeded` (terminal)
- SMS
  - Root: `comms.send_sms_task`
  - Facts: `..._scheduled`, `..._failed`, `..._succeeded`

Kickoff helpers (internal)

- `comms.create_email_message(from, to, subject, html) → OUT validation_failure_message, created_message_id`
- `comms.kickoff_send_email_task(message_id, scheduled_at default now()) → OUT validation_failure_message`
- `comms.create_and_kickoff_email_task(from, to, subject, html, scheduled_at default now()) → OUT validation_failure_message`
- SMS variants mirror email: `create_sms_message`, `kickoff_send_sms_task`, `create_and_kickoff_sms_task`.

Supervisors and handlers

- Supervisors are security definer functions:
  - `comms.send_email_supervisor(payload jsonb)`
  - `comms.send_sms_supervisor(payload jsonb)`
- Behavior (summary, see queues/worker doc for details):
  - Validate payload id, lock the root row, check terminal/attempt guards using facts helpers.
  - If no outstanding attempt (`scheduled <= failures`), insert a `..._scheduled` fact and enqueue a channel task now with handlers.
  - Re-enqueue the supervisor using exponential backoff based on failures.
- Handlers (security definer):
  - Before: `comms.get_email_payload(payload jsonb)`, `comms.get_sms_payload(payload jsonb)` → JSON envelope with `success/payload` or `validation_failure_message`.
  - Success: `comms.record_email_success(payload jsonb)`, `comms.record_sms_success(payload jsonb)` (insert terminal success fact, idempotent).
  - Error: `comms.record_email_failure(payload jsonb)`, `comms.record_sms_failure(payload jsonb)` (append failure fact).

Payload contracts

- Supervisor task payload:

```json
{
  "task_type": "db_function",
  "db_function": "comms.send_email_supervisor",
  "send_email_task_id": 123
}
```

- Channel task payload (email):

```json
{
  "task_type": "email",
  "send_email_task_id": 123,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

API examples

- Hello world

```sql
select api.hello_world_email('user@example.com');
select api.hello_world_sms('+15551234567');
```

Notes

- Error handling is append-only: operational errors are also written to `queues.error` by the worker.
- All business logic state is derived from facts tables and uniqueness constraints; functions are idempotent.
- See `docs/postgres/queues-and-worker.md` for the worker lifecycle and the standard function result envelope.

## Navigate

- Back to Postgres: [Postgres Index](README.md)

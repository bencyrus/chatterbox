## Communications (email and SMS)

Status: current
Last verified: 2025-10-08

← Back to [`docs/postgres/README.md`](./README.md)

### Why this exists

- Explain the `comms` domain built on the generic queue, including data model, templates, kickoff helpers, supervisors, handlers, and examples.

### Data model

- `comms.message`
  - Base message record with `message_id` and `channel in ('email','sms')`.
- `comms.email_message`
  - Per-email payload: `from_address, to_address, subject, html`.
- `comms.sms_message`
  - Per-sms payload: `to_number, body`.
- Templates (optional, used by API helpers)
  - `comms.email_template`, `comms.sms_template` with `template_key`, `subject`/`body`, and `body_params`.

### Process model (task and attempts)

- Email
  - Root: `comms.send_email_task`
  - Attempts: `comms.send_email_attempt` (append-only, one per scheduled execution)
  - Outcomes: `comms.send_email_attempt_succeeded`, `comms.send_email_attempt_failed` (one per attempt at most)
- SMS
  - Root: `comms.send_sms_task`
  - Attempts: `comms.send_sms_attempt`
  - Outcomes: `comms.send_sms_attempt_succeeded`, `comms.send_sms_attempt_failed`

### Kickoff helpers (internal)

- `comms.create_email_message(from, to, subject, html) → OUT validation_failure_message, created_message_id`
- `comms.kickoff_send_email_task(message_id, scheduled_at default now()) → OUT validation_failure_message`
- `comms.create_and_kickoff_email_task(from, to, subject, html, scheduled_at default now()) → OUT validation_failure_message`
- SMS variants mirror email: `create_sms_message`, `kickoff_send_sms_task`, `create_and_kickoff_sms_task`.

### Supervisors and handlers

- Supervisors are security definer functions:
  - `comms.send_email_supervisor(_payload jsonb)`
  - `comms.send_sms_supervisor(_payload jsonb)`
- Behavior (summary, see queues/worker doc for details):
  - Validate payload id, lock the root row, check terminal/attempt guards using facts helpers.
  - If no outstanding attempt (`attempts = failures`), create an attempt and enqueue a channel task with handlers.
  - Re-enqueue the supervisor using exponential backoff based on failures.
- Handlers (security definer):
  - Before: `comms.get_email_payload(_payload jsonb)`, `comms.get_sms_payload(_payload jsonb)` → JSON envelope with `success/payload` or `validation_failure_message`. Receives `send_email_attempt_id` (or `send_sms_attempt_id`).
  - Success: `comms.record_email_success(_payload jsonb)`, `comms.record_sms_success(_payload jsonb)` (insert attempt success fact, idempotent).
  - Error: `comms.record_email_failure(_payload jsonb)`, `comms.record_sms_failure(_payload jsonb)` (insert attempt failure fact).

### Payload contracts

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
  "send_email_attempt_id": 456,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

Note: The supervisor receives `send_email_task_id` (the root task). The channel task receives `send_email_attempt_id` (the specific attempt). Handlers record success/failure against the attempt, which can then be joined back to the task for supervisor decisions.

### API examples

- Hello world

```sql
select api.hello_world_email('user@example.com');
select api.hello_world_sms('+15551234567');
```

### Notes

- Seeded templates (for examples): `hello_world_email`, `hello_world_sms`.

- Error handling: operational errors are written to `queues.error` by the worker.
- All business logic state is derived from attempt facts; functions are idempotent.
- Success/failure is recorded per attempt, not per task. The supervisor queries `has_send_email_succeeded_attempt(_task_id)` to check if any attempt succeeded.
- See `docs/postgres/queues-and-worker.md` for the worker lifecycle and the standard function result envelope.

### See also

- Back to Postgres: [Postgres Index](README.md)

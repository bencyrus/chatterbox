## Comms system (email/sms) on top of the job queue

This document explains the communication domain (`comms`) built on the generic queue. It covers message storage, payloads, and supervisor-driven kickoff/enqueue helpers.

### Data model

- `comms.message`
  - Base record with `message_id` and `channel` (`email` or `sms`).
- `comms.email_message`
  - Per-email fields: `from_address, to_address, subject, html`.
- `comms.sms_message`
  - Per-sms fields: `to_number, body`.
- Templates (optional, for app use)
  - `comms.email_template`, `comms.sms_template` (app can read these to build bodies outside the DB).

### Creation helpers (internal)

- `comms.create_email_message(from_address, to_address, subject, html)`
  - Validates required inputs; returns OUT params `validation_failure_message text`, `created_message_id bigint`.
- `comms.create_sms_message(to_number, body)`
  - Validates required inputs; returns OUT params `validation_failure_message text`, `created_message_id bigint`.

### Kickoff helpers (internal, supervisor-driven)

- `comms.kickoff_send_email_task(message_id, scheduled_at timestamptz default now())`
  - Creates a root `comms.send_email_task` and enqueues the supervisor `comms.send_email_supervisor`. Returns OUT param `validation_failure_message text` (null on success).
- `comms.create_and_kickoff_email_task(from_address, to_address, subject, html, scheduled_at timestamptz default now())`
  - Validates and creates the email message, then kicks off the supervisor. Returns OUT `validation_failure_message text`.
- `comms.kickoff_send_sms_task(message_id, scheduled_at timestamptz default now())` and `comms.create_and_kickoff_sms_task(to_number, body, scheduled_at timestamptz default now())` mirror the email flow.

These helpers ultimately call `queues.enqueue(task_type, payload jsonb, scheduled_at timestamptz)` from within supervisors/handlers. The worker itself never enqueues work.

### Worker consumption

- The worker leases the next task via `queues.dequeue_next_available_task()` and inspects `task_type` and `payload`.
- For `task_type = 'db_function'`, the worker invokes `internal.run_function(payload.db_function, payload)`.
- For channel tasks (`'email'`, `'sms'`):
  - Optionally run `before_handler` (from the payload) to build provider payload (`{ success: true, payload: {...} }`).
  - Call the provider using the worker's integration.
  - On success, call `success_handler`; on error, append `queues.error` and call `error_handler`.
  - See `docs/worker.md` for the standard JSON envelope and lifecycle.

### Error handling and validation

- Internal supervisors/handlers return a standard JSON envelope with `success`, optional `validation_failure_message`, and optional `payload`. Use `validation_failure_message` for non-retriable validation issues.
- Public `api.*` RPCs raise exceptions on validation errors with `detail`/`hint` for clients.

### Examples

```sql
-- Hello world email via public API (builds from template and schedules send)
select api.hello_world_email('user@example.com');

-- Direct internal kickoff (email)
select comms.create_and_kickoff_email_task(
  _from_address => 'no-reply@example.com',
  _to_address   => 'user@example.com',
  _subject      => 'Welcome!',
  _html         => '<h1>Hello</h1>'
);

-- Hello world sms via public API
select api.hello_world_sms('+15551234567');
```

Worker processing details: see `docs/worker.md`.

## Comms system (email/sms) on top of the job queue

This document explains the communication domain (`comms`) built on the generic queue. It covers message storage, payloads, and enqueue helpers.

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

- `comms.create_email_message(from_address, to_address, subject, html)` → `create_email_message_result`
  - Validates required inputs; returns `{ validation_failure_message, message_id }`.
- `comms.create_sms_message(to_number, body)` → `create_sms_message_result`
  - Validates required inputs; returns `{ validation_failure_message, message_id }`.

### Enqueue helpers (internal)

- `comms.create_and_enqueue_email(...)` → `enqueue_job_result`
  - Creates the email message, enqueues a job: returns `{ validation_failure_message, job }`.
- `comms.create_and_enqueue_sms(...)` → `enqueue_job_result`
  - Creates the sms message, enqueues a job: returns `{ validation_failure_message, job }`.

These helpers call `queues.enqueue(task_type, resource_id, priority, num_max_attempts, scheduled_at)`.

### Worker consumption

- Workers fetch jobs via `service_api.fetch_next_task` and receive:
  - `job`: `{ job_id, lease_id, task_type, resource_id, priority, scheduled_at }`
  - `payload`: channel-specific JSON built by `comms.get_email_payload(message_id)` or `comms.get_sms_payload(message_id)`.

### Error handling and validation

- Internal functions never raise exceptions; they return `validation_failure_message` on failure.
- Public `service_api` RPCs raise exceptions on validation errors (PostgREST returns detail/hint).

### Example: enqueue and process email

```sql
-- App code: create and enqueue
select *
from comms.create_and_enqueue_email(
  _from_address => 'no-reply@example.com',
  _to_address   => 'user@example.com',
  _subject      => 'Welcome!',
  _html         => '<h1>Hello</h1>'
);
```

Worker fetches and processes via `service_api.fetch_next_task` and reports with `service_api.report_task_result` (see docs/worker.md).

## Worker Task Payloads and Handlers

Status: current
Last verified: 2025-10-08

← Back to [`docs/worker/README.md`](./README.md)

### Why this exists

- Define the standard task payload shapes and handler lifecycle used by all worker‑processed tasks.

### Task types and shapes

- DB function task (pure database step)

```json
{
  "task_type": "db_function",
  "db_function": "schema.function_name",
  "...": "domain-specific fields (e.g., a single resource id)"
}
```

- Handler‑based task (any domain; email/SMS are examples)

```json
{
  "task_type": "<domain-task-type>",
  "before_handler": "schema.get_*_payload",
  "success_handler": "schema.record_*_success",
  "error_handler": "schema.record_*_failure",
  "...": "domain-specific fields (typically one resource id)"
}
```

### Standard function result envelope

```json
{
  "success": true,
  "error": "",
  "validation_failure_message": "",
  "payload": {}
}
```

### Lifecycle (how the worker executes)

- DB function

  - Calls `internal.run_function(db_function, payload)`.
  - If `error` is set → task failure (appended to `queues.error`).
  - If `validation_failure_message` is set → logged, treated as non‑fatal; no retries by the worker.
  - Otherwise `success`.

- Handler‑based task
  - Before: call `before_handler(payload)`; expects the envelope with provider `payload` on success.
    - If `error` or `validation_failure_message` → worker appends to `queues.error` and invokes `error_handler({ original_payload, error: message })`. No provider call.
  - Provider call: the worker invokes the external/system provider using the before‑payload.
    - On provider success → call `success_handler({ original_payload, worker_payload })`.
    - On provider error → append `queues.error(task_id, message)` and call `error_handler({ original_payload, error })`.

### Expectations

- The worker never enqueues tasks; supervisors/handlers in SQL schedule work via `queues.enqueue`.
- Payloads should include a single resource identifier that the DB can use to fetch facts and enforce idempotency.
- Providers and handlers must be idempotent; supervisors derive state from append‑only facts and uniqueness constraints.
- The worker forwards the full original task payload to all handlers; handlers extract what they need.

### Example (comms: send email)

- Supervisor task (db function)

```json
{
  "task_type": "db_function",
  "db_function": "comms.send_email_supervisor",
  "send_email_task_id": 123
}
```

- Channel task (email)

```json
{
  "task_type": "email",
  "send_email_task_id": 123,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

- Flow
  - Before builds provider payload `{ message_id, from_address, to_address, subject, html }`.
  - Worker calls email provider (Resend). On success → `success_handler({ original_payload, worker_payload })`; on failure → append `queues.error` and call `error_handler({ original_payload, error })`.

### See also

- Lifecycle: [`./lifecycle.md`](./lifecycle.md)
- Email: [`./email.md`](./email.md)
- SMS: [`./sms.md`](./sms.md)
- Queues/worker contract: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)

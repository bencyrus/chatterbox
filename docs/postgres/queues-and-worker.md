## Queues and Worker

Purpose

- Describe the generic queue, the worker contract, and the supervisor-driven orchestration pattern implemented in SQL.

Core data model (queues)

- `queues.task`
  - Columns: `task_id`, `task_type` (`'db_function' | 'email' | 'sms'`), `payload jsonb`, `enqueued_at`, `scheduled_at`, `dequeued_at`.
- `queues.error`
  - Append-only operational error log with `task_id` and `error_message`.

Functions

- `queues.enqueue(_task_type, _payload, _scheduled_at default now()) returns void`
  - Used by supervisors/handlers to schedule work; the worker never enqueues.
- `queues.dequeue_next_available_task() returns queues.task`
  - Selects one ready task ordered by `scheduled_at, task_id` using `for update skip locked`; sets `dequeued_at`.
- `queues.append_error(task_id, error_message) returns jsonb`
  - Appends an error row.
- `internal.run_function(function_name text, payload jsonb) returns jsonb`
  - Security invoker runner that executes named functions (supervisors/handlers). Worker has execute on this and on whitelisted business functions (security definer).

Worker lifecycle (Go)

- Lease a task via `queues.dequeue_next_available_task()` in its own transaction.
- Dispatch by `task_type` to the appropriate processor:
  - `db_function`: call `internal.run_function(payload.db_function, payload)` and respect the JSON envelope
  - `email`/`sms`: call `before_handler` to build a provider payload, call the provider, then call `success_handler` or `error_handler`
- Always pass the full `payload jsonb` through; DB functions extract what they need.
- Append operational errors to `queues.error` but avoid failing the overall worker loop.

Standard JSON envelope (DBFunctionResult)

```json
{
  "success": true,
  "error": "",
  "validation_failure_message": "",
  "payload": {}
}
```

- `success`: `true` on success.
- `error`: for unexpected operational errors (rare; logged and often retried via supervisor scheduling logic).
- `validation_failure_message`: set for non-retriable validation issues; treated as non-fatal by the worker.
- `payload`: optional typed data returned by `before_handler` calls.

Supervisor pattern (ICO: Input → Compute → Output)

- Supervisors orchestrate business processes using append-only facts.
- Inputs: small facts functions like `has_*_succeeded(id)`, `count_*_failures(id)`, `count_*_scheduled(id)`.
- Compute: decide whether to schedule a channel task; compute next check time (e.g., exponential backoff based on failures).
- Output: insert a `..._scheduled` fact, enqueue a channel task with handlers, and re-enqueue the supervisor.
- Termination: exit when a terminal fact exists or attempts are exhausted.

Email example (current implementation)

- Root tables and facts: `comms.send_email_task`, `..._scheduled`, `..._failed`, `..._succeeded`.
- Supervisor: `comms.send_email_supervisor(payload jsonb)`
  - Validates `send_email_task_id`, locks the root row, checks success/failure counts.
  - If no outstanding attempt (`scheduled <= failures`), inserts a scheduled fact and enqueues an `email` task with handlers:
    - `before_handler`: `comms.get_email_payload`
    - `success_handler`: `comms.record_email_success`
    - `error_handler`: `comms.record_email_failure`
  - Re-enqueues itself based on exponential backoff from failures.

Payload contracts (examples)

Supervisor task payload

```json
{
  "task_type": "db_function",
  "db_function": "comms.send_email_supervisor",
  "send_email_task_id": 123
}
```

Channel task payload (email)

```json
{
  "task_type": "email",
  "send_email_task_id": 123,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

Security and grants

- Worker role: `worker_service_user`
  - Grants: usage on `queues`, `internal`, and business schemas; execute on `queues.dequeue_next_available_task`, `internal.run_function`, `queues.append_error`, and specific business functions it must call (supervisors/handlers).
- Business functions (supervisors/handlers): `security definer` with targeted `execute` grants to `worker_service_user`.
- Function runner: `security invoker`; no direct table grants to the worker.

Operational notes

- Dequeue and processing are separate transactions to avoid infinite retry loops on failure.
- Use `for update skip locked` to prevent duplicate processing.
- Supervisors/handlers perform all scheduling; the worker never enqueues tasks by itself.

## Navigate

- Back to Postgres: [Postgres Index](README.md)
- Worker details: [Worker Docs](../worker/README.md)

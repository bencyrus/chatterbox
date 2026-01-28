## Worker Lifecycle

Status: current
Last verified: 2025-10-08

← Back to [`docs/worker/README.md`](./README.md)

### Why this exists

- Describe the worker’s execution model and contracts with the database and providers.

### Flow

- **Dequeue**: calls `queues.dequeue_next_available_task()` which uses `for update skip locked` to claim one ready task with a 5-minute lease.
- **Dispatch**: routes by `task_type` via a `Dispatcher` to a `Processor` implementation.
- **Process**:
  - `db_function`: runs `internal.run_function(name, payload)`; interprets standard JSON envelope; logs validation failures.
  - `email` / `sms`: call `before_handler` to build provider payload, invoke provider, then call `success_handler` or `error_handler`.
- **Record failure** (if error): calls `queues.fail_task(task_id, message)` for observability.
- **Complete**: always calls `queues.complete_task(task_id)` after processing, whether success or failure.

### Why always complete?

Retries are handled by **supervisors**, not by re-processing the same queue task. When a task fails:

1. The error handler records the failure fact (e.g., `send_email_attempt_failed`)
2. The task is completed (removed from queue)
3. The supervisor sees the failure and creates a **new attempt** with a **new task**

Lease expiry is only for **crash recovery**: if the worker dies mid-processing before reaching `complete_task`, the lease expires and the task becomes available again. Handlers are idempotent (`ON CONFLICT DO NOTHING`), so re-running after a crash is safe.

### Code map

- Entry: `cmd/worker/main.go` (init, concurrency, graceful shutdown)
- Core loop: `internal/worker/worker.go` (Run, processTask, handleTaskResult)
- DB client: `internal/database/client.go` (dequeue, complete_task, fail_task, run_function)
- Processing: `internal/processing/*` (dispatchers, processors, handler invoker)

### Contracts

- Standard envelope for DB functions:
  - `{ "status": "succeeded", "payload": {} }`.
  - `status` is `"succeeded"` for success; any other value is a non-success outcome.
- Handlers receive the full original task payload; worker does not pre‑parse business fields beyond handler names.

### See also

- Email: [`./email.md`](./email.md)
- SMS: [`./sms.md`](./sms.md)
- Task payloads and handlers: [`./payloads.md`](./payloads.md)
- Queues/worker contract: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)

## Worker Lifecycle

Purpose

- Explain how the worker leases and processes tasks, calls handlers, and records errors.

Flow

- Dequeue: calls `queues.dequeue_next_available_task()` which uses `for update skip locked` to claim one ready task and set `dequeued_at`.
- Dispatch: routes by `task_type` via a `Dispatcher` to a `Processor` implementation.
- Process:
  - `db_function`: runs `internal.run_function(name, payload)`; interprets standard JSON envelope; logs validation failures.
  - `email` / `sms`: call `before_handler` to build provider payload, invoke provider, then call `success_handler` or `error_handler`.
- Errors: append operational errors to `queues.error` via `queues.append_error(task_id, message)`; do not abort the main loop.

Code map

- Entry: `cmd/worker/main.go` (init, concurrency, graceful shutdown)
- Core loop: `internal/worker/worker.go` (Run, processTask, handleTaskResult)
- DB client: `internal/database/client.go` (dequeue, run_function, append_error)
- Processing: `internal/processing/*` (dispatchers, processors, handler invoker)

Contracts

- Standard envelope for DB functions:
  - `{ "success": true, "error": "", "validation_failure_message": "", "payload": {} }`.
- Handlers receive the full original task payload; worker does not pre‑parse business fields beyond handler names.

Navigate

- Email: [`./email.md`](./email.md)
- SMS: [`./sms.md`](./sms.md)
- Task payloads and handlers: [`./payloads.md`](./payloads.md)
- Queues/worker contract: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)

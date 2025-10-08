## Worker

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Execute work scheduled by database supervisors with minimal orchestration in Go.
- Keep business logic and scheduling in Postgres for idempotency and clarity.

### Role in the system

- Dequeues tasks from `queues.task` and dispatches by `task_type` to processors (`db_function`, `email`, `sms`).
- Invokes database handlers (`before_handler`, `success_handler`, `error_handler`) via `internal.run_function` and calls providers.
- Appends operational errors to `queues.error`; never enqueues tasks.
- Runs with minimal database privileges: usage on `queues`/`internal`, execute on `queues.dequeue_next_available_task`, `internal.run_function(text,jsonb)`, and per‑function grants to business functions.
  - Source: [`postgres/migrations/1756074000_base_queues_and_worker.sql`](../../postgres/migrations/1756074000_base_queues_and_worker.sql)

### How it works

- Core loop: leases a task, selects a processor, processes, then calls success/error handlers.
- Contract: DB functions return a standard envelope `{ success, error, validation_failure_message, payload }`.
- For detailed flow and code references, see Lifecycle and Payloads.

### Operations

- Env (required): `DATABASE_URL`.
- Env (optional): `RESEND_API_KEY`, `WORKER_POLL_INTERVAL_SECONDS` (default `5`), `WORKER_MAX_IDLE_TIME_SECONDS` (default `30`), `WORKER_CONCURRENCY` (default `2`), `LOG_LEVEL` (default `info`).
- Entrypoint: [`worker/cmd/worker/main.go`](../../worker/cmd/worker/main.go)
- Database grants: [`postgres/migrations/1756074000_base_queues_and_worker.sql`](../../postgres/migrations/1756074000_base_queues_and_worker.sql)

### Examples

- Add a new task type: implement a `Processor`, register it in `NewWorker`, add DB handlers/supervisor (see [Payloads](./payloads.md) for contracts).

### Future

- None at this time.

### See also

- Lifecycle: [`./lifecycle.md`](./lifecycle.md)
- Task payloads and handlers: [`./payloads.md`](./payloads.md)
- Email: [`./email.md`](./email.md)
- SMS: [`./sms.md`](./sms.md)
- Postgres queues/worker: [`../postgres/queues-and-worker.md`](../postgres/queues-and-worker.md)

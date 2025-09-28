### Chatterbox Worker

Worker that processes tasks from Postgres `queues.task` using a dispatcher/processor architecture.

#### Architecture

- `internal/worker/worker.go`: main loop. Dequeues tasks, dispatches by `task_type`, invokes success/error handlers.
- `internal/processing`: orchestration primitives
  - `Processor` interface: per `task_type` implementation (`TaskType()`, `HasHandlers()`, `Process(ctx, task)`)
  - `Dispatcher`: routes to processors
  - `HandlerInvoker`: runs before/success/error handlers via `internal.run_function`, unmarshals `payload` from the standardized envelope
- `internal/services`: provider clients (e.g., `email`, `sms`)
- `internal/database`: thin DB client for `dequeue_next_available_task`, `run_function`, and `append_error`
- Concurrency is configurable via `WORKER_CONCURRENCY` and each worker goroutine uses `for update skip locked` semantics enforced by the SQL side.

#### Contracts with the database

- Tasks live in `queues.task` with `task_type in ('db_function','email','sms')`.
- Only supervisors/handlers enqueue tasks via `queues.enqueue`; worker never enqueues.
- Worker calls `internal.run_function(text, jsonb)` using a dedicated role with minimal grants.

Standard function result envelope (DBFunctionResult):

```json
{
  "success": true,
  "error": "",
  "validation_failure_message": "",
  "payload": {}
}
```

- Supervisors return `success: true`. If inputs invalid, set `validation_failure_message`.
- Before-handlers: on success, must include `payload` (provider payload). For invalid inputs, set `validation_failure_message` (no retries by the worker).
- Success/error handlers: typically return `{ "success": true }`.

#### Adding a new service (task type)

1. Implement a provider client under `internal/services/<name>/`.

2. Create a processor in `internal/processing/<name>_processor.go`:

```go
type MyProcessor struct {
    handlers *processing.HandlerInvoker
    service  *myservice.Service
}

func (p *MyProcessor) TaskType() string { return "my_task_type" }
func (p *MyProcessor) HasHandlers() bool { return true }
func (p *MyProcessor) Process(ctx context.Context, task *types.Task) *types.TaskResult {
    var payload types.TaskPayload
    if err := json.Unmarshal(task.Payload, &payload); err != nil {
        return types.NewTaskFailure(err)
    }
    if payload.BeforeHandler == "" { return types.NewTaskFailure(fmt.Errorf("missing before_handler")) }
    var providerPayload myservice.Payload
    if err := p.handlers.CallBefore(ctx, payload.BeforeHandler, task.Payload, &providerPayload); err != nil {
        return types.NewTaskFailure(err)
    }
    res, err := p.service.Do(ctx, &providerPayload)
    if err != nil { return types.NewTaskFailure(err) }
    return types.NewTaskSuccess(res)
}
```

3. Register your processor in `NewWorker`:

```go
dispatcher.Register(processing.NewMyProcessor(handlers, mySvc))
```

4. DB side: add a supervisor (if needed) and before/success/error handlers that follow the envelope above. Ensure the worker role has execute on those functions.

#### Configuration

- `DATABASE_URL`: Postgres connection
- `RESEND_API_KEY`: email provider key (example)
- `WORKER_CONCURRENCY`: number of goroutines (default 2)
- `WORKER_POLL_INTERVAL_SECONDS`: dequeue poll interval
- `WORKER_MAX_IDLE_TIME_SECONDS`: idle logging threshold

#### Logging & Errors

- Structured logs via `shared/logger`.
- Operational errors appended via `queues.append_error(task_id, message)`.
- Validation failures are not retried by the worker and should be returned via `validation_failure_message`.

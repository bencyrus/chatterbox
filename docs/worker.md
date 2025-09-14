### Worker and Supervisor Design

This document describes the internal queues/worker system, the supervisor orchestration pattern, payload contracts, scheduling/backoff, and security conventions used in this project.

## Concepts

- **task**: a unit of work scheduled to run at or after `scheduled_at`. Stored as a row in `queues.task` with a `task_type` and `payload jsonb`.
- **task_type**: enumerated via `queues.task_type` domain. Current values: `db_function`, `email`, `sms`.
- **payload**: full jsonb blob passed through the system. Functions extract what they need; passing extra fields is fine.
- **handlers**: optional internal db functions referenced by name in the payload for business tasks: `before_handler`, `success_handler`, `error_handler`.
- **supervisor**: a db function that orchestrates a business process using facts. It enqueues child tasks, decides if/when to re-enqueue itself, and terminates when a terminal fact exists or limits are reached.
- **facts (append-only)**: internal business process tables are append-only. Derive state from the latest facts; avoid updates/deletes. Enforce uniqueness to guarantee at-most-once per logical event.
- **business process**: an orchestrated domain workflow (e.g., send email/sms) managed by a supervisor function. It records progress via append-only facts, enqueues child tasks (e.g., email, sms, itself), and terminates when a terminal fact exists or retry/run limits are met. Code remains idempotent and stateless; all state lives in the db and retrieved using facts functions. Kickoff typically inserts a new `queues.task` record to enqueue the supervisor.
- **function runner**: a thin wrapper that accepts a function name and a jsonb payload and invokes the target internal function. The runner is security invoker; target business functions are security definer with explicit per-function grants to the worker role.

## Worker database user and permissions

- The worker connects using a dedicated database role (for example, `worker_service_user`) with minimal privileges.
- Grants should be narrowly scoped:
  - usage on required schemas (e.g., `queues`)
  - execute on `queues.dequeue_available_task`
  - execute on `internal.run_function(function_name text, payload jsonb) returns jsonb` (security invoker)
  - execute on allowed business functions individually (security definer) such as supervisors and handlers
- Avoid direct table privileges; the worker interacts via `queues` functions and the business functions only.

### Function runner (pattern)

Shape of the security-invoker runner that dispatches calls (relies on per-function grants):

```sql
-- internal.run_function(function_name text, payload jsonb) returns jsonb
-- security invoker; executes target and returns jsonb; authorization via per-function grants
```

## Data model (internal)

- `queues.task`: unit of work with `task_id`, `task_type`, `payload jsonb`, timestamps `enqueued_at`, `scheduled_at`, optional `dequeued_at`.
- `queues.error`: append-only record of worker/handler errors for observability.
- `comms.message`: base comms record with `channel in ('email','sms')`.
- `comms.email_message`, `comms.sms_message`: channel-specific payload data.
- `comms.email_send_attempt`, `comms.sms_send_attempt`: root attempts per logical send.
- `comms.email_attempt_started/succeeded/failed`, `comms.sms_attempt_started/succeeded/failed`: facts that track progress and outcomes.
- Facts tables per process (email/sms): `..._succeeded`, `..._failed`. Primary key is the process task id (also a foreign key to the root task table). We do not store separate surrogate ids.

### Retry derivation (no started/retried facts)

- First enqueue and retries are derived, not stored. For example, allowing one retry for email is computed as follows:
  - If no email task has been enqueued for the `send_email_task_id`: enqueue the first email task.
  - If exactly one email task has been enqueued and a failure fact exists: enqueue one more email task.
  - Otherwise, do not enqueue additional email tasks. Terminate when success exists or retry limit is reached.

## Payload contracts

Supervisor task payload (db function) — prefer a single resource identifier:

```json
{
  "task_type": "db_function",
  "db_function": "comms.email_send_supervisor",
  "send_email_task_id": 123
}
```

Business task payloads (email, sms, etc.) — also reference the same single id:

```json
{
  "task_type": "email",
  "send_email_task_id": 123,
  "before_handler": "comms.get_email_payload",
  "success_handler": "comms.record_email_success",
  "error_handler": "comms.record_email_failure"
}
```

## Worker lifecycle (high-level)

Pseudo-code for the Go worker loop that processes available tasks:

```pseudo
loop forever:
  task := fetch_next_ready_task()  // select ... for update skip locked where scheduled_at <= now()
  if task is none:
    sleep(backoff)
    continue

  switch task.task_type:
    case 'db_function':
      result := run_function(task.payload.db_function, task.payload)
      if result.validation_failure_message is not null:
        record queues.error

    case 'email':
      provider_payload := null
      if task.before_handler:
        provider_payload := run_function(task.before_handler, task.payload)
      provider_result, err := send_email(provider_payload)
      if err == nil:
        if task.success_handler: run_function(task.success_handler, {original_payload: task.payload, worker_payload: provider_result})
      else:
        record queues.error
        if task.error_handler: run_function(task.error_handler, {original_payload: task.payload, error: error})

    case 'sms':
      provider_payload := null
      if task.before_handler:
        provider_payload := run_function(task.before_handler, task.payload)
      provider_result, err := send_sms(provider_payload)
      if err == nil:
        if task.success_handler: run_function(task.success_handler, {original_payload: task.payload, worker_payload: provider_result})
      else:
        record queues.error
        if task.error_handler: run_function(task.error_handler, {original_payload: task.payload, error: error})
```

Notes:

- Pass the entire `payload` to db functions and handlers; they extract what they need.
- Keep dequeuing and processing in separate transactions to avoid infinite retry loops on failure.
- Use `select ... for update skip locked` semantics to prevent duplicate processing under concurrency.
- The worker never enqueues tasks; supervisors/handlers (in db) perform scheduling and re-enqueueing as needed.

## Supervisor orchestration (email example)

```pseudo
-- comms.email_send_supervisor(payload jsonb)
-- payload: { send_email_task_id }

facts := read_current_facts_for(payload.send_email_task_id)

# 1) terminate if terminal
if success_fact exists for payload.send_email_task_id:
  return
if failure_fact exists for payload.send_email_task_id and not retries_remaining(facts):
  return

# 2) decide if we need to enqueue the channel task, and for when
if started_fact not exists for payload.send_email_task_id or (failure_fact exists for payload.send_email_task_id and retries_remaining(facts)):
  enqueue queues.task:
    task_type: 'email'
    payload:
      send_email_task_id
      before_handler: 'comms.get_email_payload'
      success_handler: 'comms.record_email_success'
      error_handler: 'comms.record_email_failure'
    scheduled_at: now()

# 3) decide if we need to enqueue the supervisor again, and for when
next_check_at := compute_next_check_time(facts)
if next_check_at is not null:
  enqueue queues.task:
    task_type: 'db_function'
    payload:
      db_function: 'comms.email_send_supervisor'
      send_email_task_id
    scheduled_at: next_check_at

return
```

## Scheduling and backoff

- Supervisors choose the next check time based on process-specific rules (for example: small delay after first enqueue, a polling interval while awaiting provider result, or a precise future time for scheduled sends).
- Only supervisors enqueue work; the worker never enqueues tasks.

## Operational guidance

- **Idempotency**: Supervisors must be safe to re-run; guards rely on facts and uniqueness constraints.
- **Observability**: Use `queues.error` for handler failures; add metrics/logging in the worker.
- **Throughput**: Use multiple worker goroutines with contention guarded by `skip locked`.
- Worker operational errors are appended to `queues.error` and do not abort the process beyond the current task.

## Notes

- Ensure grants are scoped to service roles; avoid broad `public` execute on internal functions.
- Security variation: For finer granularity, keep `internal.run_function` as security invoker and grant execute only on specific business functions (security definer) to `worker_service_user`.
- For certain tasks, you can run work fully in the worker and let the frontend poll for results via a controlled polling endpoint or long-lived connection.

## Example Flow: Send Email Task

This is a concrete, step-by-step story of a single email being sent with Resend as the provider. The process allows one retry.

1. Kickoff

- App creates an email message and a `send_email_task` with id X.
- A supervisor task is enqueued with payload `{ task_type: 'db_function', db_function: 'comms.email_send_supervisor', send_email_task_id: X }`.

2. Supervisor run #1

- Worker takes on the supervisor task and invokes the function.
- Supervisor reads facts for X: no success, no failure, not started.
- Supervisor enqueues one email task now with handlers `{ before_handler: 'comms.get_email_payload', success_handler: 'comms.record_email_success', error_handler: 'comms.record_email_failure' }`.
- Supervisor also enqueues itself to run again in a few seconds.

3. Email attempt #1 (failure)

- Worker takes the email task.
- Worker runs the before handler to build the provider payload and calls Resend.
- Provider call fails; worker appends `queues.error` and calls the error handler, which records a failure fact for X.

4. Supervisor run #2

- Worker takes the supervisor task again.
- Supervisor reads facts for X: failure exists, retry still allowed.
- Supervisor enqueues a second email task now with the same handlers.
- Supervisor enqueues itself to run again shortly.

5. Email attempt #2 (success)

- Worker takes the second email task.
- Worker runs the before handler and calls Resend.
- Provider call succeeds; worker calls the success handler, which records a success fact for X.

6. Supervisor run #3 (terminal)

- Worker teakes the supervisor task.
- Supervisor reads facts for X: success fact exists.
- Supervisor terminates; no further tasks are enqueued.

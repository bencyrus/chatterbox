## Account Deletion

Status: current  
Last verified: 2025-12-09

← Back to [`docs/postgres/README.md`](README.md)

### Why this exists

- Provide an in-app, supervisor-driven way to delete user accounts and their associated data.
- Keep the process observable, idempotent, and aligned with Apple’s account deletion requirements.

### Role in the system

- Owns the end-to-end account deletion workflow:
  - Tracks deletion jobs in `accounts.account_deletion_task`.
  - Orchestrates clean-up via `accounts.account_deletion_supervisor(payload jsonb)`.
  - Enqueues `file_delete` tasks for user recording files.
- Exposed to clients via `api.request_account_deletion()` at `/rpc/request_account_deletion`.

### How it works

- Data model (see [`postgres/migrations/1756075600_account_deletion.sql`](../../postgres/migrations/1756075600_account_deletion.sql)):
  - `accounts.account_deletion_task`
    - One row per logical deletion request: `account_deletion_task_id`, `account_id`, `created_at`.
    - `account_id` is a plain bigint (no FK) so the job record can outlive future schema changes.
  - Facts (append-only, supervisor pattern):
    - `accounts.account_deletion_task_scheduled`
    - `accounts.account_deletion_task_failed`
    - `accounts.account_deletion_task_succeeded`
  - Fact helpers:
    - `accounts.has_account_deletion_task_succeeded(_account_deletion_task_id)`
    - `accounts.count_account_deletion_task_failures(_account_deletion_task_id)`
    - `accounts.count_account_deletion_task_scheduled(_account_deletion_task_id)`

- Kickoff:
  - `accounts.kickoff_account_deletion(_account_id, _scheduled_at default now())`:
    - Validates the account exists.
    - Inserts or reuses an `account_deletion_task` row (idempotent on `account_id`).
    - Enqueues a `db_function` task in `queues.task`:
      - Payload shape:
        - `{ "task_type": "db_function", "db_function": "accounts.account_deletion_supervisor", "account_deletion_task_id": <id>, "account_id": <account_id> }`
  - Public RPC:
    - `api.request_account_deletion()`:
      - Resolves the current account via `auth.jwt_account_id()`.
      - Calls `accounts.kickoff_account_deletion(...)`.
      - Returns `{ "status": "succeeded" }` or raises a structured exception on validation failures.

- Supervisor behavior:
  - `accounts.account_deletion_supervisor(payload jsonb)`:
    - Validates payload and locks the root `accounts.account_deletion_task` row `for update`.
    - Terminates early when `accounts.has_account_deletion_task_succeeded(id)` is true.
    - Uses failure/scheduled counters to bound retries and compute an exponential backoff.
    - When no attempt is outstanding (`scheduled <= failures`):
      - Inserts a `..._scheduled` fact.
      - Calls `accounts.perform_account_deletion(account_deletion_task_id, account_id)` inside a `begin/exception` block:
        - On success: inserts `..._succeeded`.
        - On error: inserts `..._failed` with `sqlerrm` captured as `error_message`.
    - Always re-enqueues itself as a `db_function` task at the computed next check time.

- Account-level clean-up:
  - `accounts.perform_account_deletion(_account_deletion_task_id, _account_id)`:
    - Fetches the current `accounts.account` row; if absent, returns (idempotent).
    - Derives user recording files via `files.account_files(_account_id)` (which encapsulates the joins across `learning.profile`, `learning.profile_cue_recording`, and `files.file`).
    - For each file:
      - Enqueues a `file_delete` task:
        - `{ "task_type": "file_delete", "account_deletion_task_id": <id>, "account_id": <account_id>, "file_id": <file_id>, "bucket": <bucket>, "object_key": <object_key> }`
      - No hard deletes of `files.file` rows; file objects are removed from storage and rows are marked as deleted.
    - Anonymizes the account via `accounts.anonymize_account(_account_id)`:
      - Clears PII columns (e.g., `email", `phone_number`, `hashed_password`) while keeping the row for auditing.
    - Inserts an `accounts.account_flag` row with `flag = 'deleted'` (if not already present) so `created_at` on that flag acts as the deletion timestamp.
    - Comms (`comms.email_message`, `comms.sms_message`) and other domain rows remain in place but are no longer tied to identifiable account data.

### Worker integration (`file_delete` tasks)

- Queue contract (see [`postgres/migrations/1756074000_base_queues_and_worker.sql`](../../postgres/migrations/1756074000_base_queues_and_worker.sql)):
  - `queues.task_type` domain includes `'file_delete'`.
  - Supervisors enqueue `file_delete` tasks with payload containing:
    - `before_handler = 'files.get_file_delete_payload'`
    - `success_handler = 'files.record_file_delete_success'`
    - `error_handler = 'files.record_file_delete_failure'`
    - Context fields such as `account_deletion_task_id`, `account_id`, and `file_id`.

- Worker implementation (see [`worker/internal/processing/file_delete_processor.go`](../../worker/internal/processing/file_delete_processor.go)):
  - `FileDeleteProcessor`:
    - Handles `task_type == "file_delete"`.
    - Uses `HandlerInvoker` to call `files.get_file_delete_payload(...)`, which resolves `file_id`, `bucket`, and `object_key` into a typed Go payload.
    - Calls the files HTTP service (see [`files/internal/httpserver/server.go`](../../files/internal/httpserver/server.go)) at `/signed_delete_url` using `FILE_SERVICE_URL` and `FILE_SERVICE_API_KEY` to obtain a signed GCS `DELETE` URL for the object.
    - Issues an HTTP `DELETE` to the signed URL to remove the object from storage.
    - Returns a `TaskResult` whose `worker_payload` includes basic observability fields (e.g. `file_id`, `bucket`, `object_key`).
  - Database handlers:
    - On success, `files.record_file_delete_success` writes success facts and calls `files.mark_file_deleted(file_id)` to set a `deleted` metadata flag.
    - On error, `files.record_file_delete_failure` appends failure facts used by `files.is_file_deletion_stuck`.

### Operations

- Schema changes:
  - Applied via `postgres/migrations/1756075600_account_deletion.sql`.
  - Assumes existing `accounts`, `auth`, `learning`, `files`, `comms`, and `queues` schemas.
- Worker:
  - Processes `file_delete` tasks alongside `db_function`, `email`, and `sms` tasks.
  - Requires `FILE_SERVICE_URL` and `FILE_SERVICE_API_KEY` to reach the files service; the files service itself owns GCS signing credentials and bucket configuration.

### Examples

- Start account deletion for the current user (from the client, via PostgREST):

```sql
select api.request_account_deletion();
```

### Future

- Extend clean-up to additional user-owned domains if/when they are added.
- Add more granular per-file facts if we need multi-attempt deletion with visibility per object.

### See also

- Queues and worker: [`docs/postgres/queues-and-worker.md`](queues-and-worker.md)  
- User recording uploads: [`docs/postgres/user-recording-uploads.md`](user-recording-uploads.md)  
- Files service: [`docs/files/README.md`](../files/README.md)

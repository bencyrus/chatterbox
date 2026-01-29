## Account Deletion

Status: current  
Last verified: 2025-01-27

← Back to [`docs/postgres/README.md`](README.md)

### Why this exists

- Provide an in-app, supervisor-driven way to delete user accounts and their associated data.
- Keep the process observable, idempotent, and aligned with Apple's account deletion requirements.

### Role in the system

- Owns the end-to-end account deletion workflow:
  - Tracks deletion jobs in `accounts.account_deletion_task`.
  - Orchestrates clean-up via `accounts.account_deletion_supervisor(payload jsonb)`.
  - Kicks off `files.file_deletion_supervisor` for user recording files.
  - Kicks off `accounts.account_anonymization_supervisor` for PII removal.
- Exposed to clients via `api.request_account_deletion()` at `/rpc/request_account_deletion`.

### How it works

- Data model (see [`postgres/migrations/1756075620_account_deletion.sql`](../../postgres/migrations/1756075620_account_deletion.sql)):
  - `accounts.account_deletion_task`
    - One row per logical deletion request: `account_deletion_task_id`, `account_id`, `created_at`.
    - `account_id` is a plain bigint (no FK) so the job record can outlive future schema changes.
  - Attempts (append-only, supervisor pattern):
    - `accounts.account_deletion_attempt` - one per supervisor scheduling cycle
    - `accounts.account_deletion_attempt_succeeded` - keyed by attempt_id
    - `accounts.account_deletion_attempt_failed` - keyed by attempt_id, includes error_message
  - Fact helpers:
    - `accounts.has_account_deletion_succeeded_attempt(_account_deletion_task_id)`
    - `accounts.has_account_deletion_failed_attempt(_account_deletion_task_id)`
    - `accounts.count_account_deletion_failed_attempts(_account_deletion_task_id)`
    - `accounts.count_account_deletion_attempts(_account_deletion_task_id)`
    - `accounts.account_deletion_supervisor_facts(_task_id, _account_id)` - aggregated facts including phase checks

- Kickoff:
  - `accounts.kickoff_account_deletion(_account_id, _scheduled_at default now())`:
    - Validates the account exists.
    - Inserts or reuses an `account_deletion_task` row (idempotent on `account_id`).
    - Marks account as deleted immediately via `accounts.account_flag`.
    - Enqueues a `db_function` task in `queues.task`:
      - Payload shape (minimal):
        - `{ "task_type": "db_function", "db_function": "accounts.account_deletion_supervisor", "account_deletion_task_id": <id> }`
  - Public RPC:
    - `api.request_account_deletion(account_id)`:
      - Validates the caller is the account owner via `auth.jwt_account_id()`.
      - Calls `accounts.kickoff_account_deletion(...)`.
      - Returns `{ "success": true }` or raises a structured exception on validation failures.

- Supervisor behavior:
  - `accounts.account_deletion_supervisor(payload jsonb)`:
    - Validates payload and locks the root `accounts.account_deletion_task` row `for update`.
    - Includes run_count protection to prevent infinite loops.
    - Gathers facts via `accounts.account_deletion_supervisor_facts(_task_id, _account_id)`.
    - Phase 1 (file deletion):
      - Checks `all_files_deleted` and `any_file_stuck` flags.
      - Kicks off file deletion supervisors via `accounts.kickoff_account_file_deletions(_account_id)`.
      - Records failure if any file deletion is stuck.
    - Phase 2 (anonymization):
      - Checks `is_anonymized` and `anonymization_stuck` flags.
      - Kicks off anonymization via `accounts.kickoff_account_anonymization(_account_id)`.
      - Records failure if anonymization is stuck.
    - Phase 3 (completion):
      - Records success via `accounts.record_account_deletion_success(_task_id)`.
    - Re-enqueues itself via `accounts.schedule_account_deletion_supervisor_recheck(...)` with exponential backoff.

### Worker integration (`file_delete` tasks)

- Queue contract (see [`postgres/migrations/1756074000_base_queues_and_worker.sql`](../../postgres/migrations/1756074000_base_queues_and_worker.sql)):
  - `queues.task_type` domain includes `'file_delete'`.
  - File deletion supervisor enqueues `file_delete` tasks with payload containing:
    - `file_deletion_attempt_id` - the attempt being processed
    - `before_handler = 'files.get_file_deletion_payload'`
    - `success_handler = 'files.record_file_deletion_success'`
    - `error_handler = 'files.record_file_deletion_failure'`

- Worker implementation (see [`worker/internal/processing/file_delete_processor.go`](../../worker/internal/processing/file_delete_processor.go)):
  - `FileDeleteProcessor`:
    - Handles `task_type == "file_delete"`.
    - Uses `HandlerInvoker` to call `files.get_file_deletion_payload(...)`, which resolves `file_deletion_attempt_id` -> `file_id` into a typed Go payload.
    - Calls the files HTTP service (see [`files/internal/httpserver/server.go`](../../files/internal/httpserver/server.go)) at `/signed_delete_url` using `FILE_SERVICE_URL` and `FILE_SERVICE_API_KEY` to obtain a signed GCS `DELETE` URL for the object.
    - Issues an HTTP `DELETE` to the signed URL to remove the object from storage.
    - Returns a `TaskResult` whose `worker_payload` includes basic observability fields (e.g. `file_id`).
  - Database handlers:
    - On success, `files.record_file_deletion_success` records the attempt success and calls `files.mark_file_deleted(file_id)` to set a `deleted` metadata flag.
    - On error, `files.record_file_deletion_failure` records the attempt failure with error message, used by `files.is_file_deletion_stuck`.

### File deletion facts model

- Tables (see [`postgres/migrations/1756075600_file_deletion.sql`](../../postgres/migrations/1756075600_file_deletion.sql)):
  - `files.file_deletion_task` - one per file being deleted
  - `files.file_deletion_attempt` - one per scheduled attempt
  - `files.file_deletion_attempt_succeeded` - keyed by attempt_id
  - `files.file_deletion_attempt_failed` - keyed by attempt_id
- Fact helpers:
  - `files.has_file_deletion_succeeded_attempt(_file_deletion_task_id)`
  - `files.count_file_deletion_failed_attempts(_file_deletion_task_id)`
  - `files.count_file_deletion_attempts(_file_deletion_task_id)`
  - `files.file_deletion_supervisor_facts(_task_id)` - aggregated facts
  - `files.is_file_deletion_stuck(_file_id)` - max retries exceeded without success

### Account anonymization facts model

- Tables (see [`postgres/migrations/1756075610_account_anonymization.sql`](../../postgres/migrations/1756075610_account_anonymization.sql)):
  - `accounts.account_anonymization_task` - one per account being anonymized
  - `accounts.account_anonymization_attempt` - one per scheduled attempt
  - `accounts.account_anonymization_attempt_succeeded` - keyed by attempt_id
  - `accounts.account_anonymization_attempt_failed` - keyed by attempt_id
- Fact helpers:
  - `accounts.has_account_anonymization_succeeded_attempt(_task_id)`
  - `accounts.count_account_anonymization_failed_attempts(_task_id)`
  - `accounts.count_account_anonymization_attempts(_task_id)`
  - `accounts.account_anonymization_supervisor_facts(_task_id)` - aggregated facts
  - `accounts.is_account_anonymization_stuck(_account_id)` - max retries exceeded without success

### Operations

- Schema changes:
  - Applied via:
    - `postgres/migrations/1756075600_file_deletion.sql`
    - `postgres/migrations/1756075610_account_anonymization.sql`
    - `postgres/migrations/1756075620_account_deletion.sql`
  - Assumes existing `accounts`, `auth`, `learning`, `files`, `comms`, and `queues` schemas.
- Worker:
  - Processes `file_delete` tasks alongside `db_function`, `email`, and `sms` tasks.
  - Requires `FILE_SERVICE_URL` and `FILE_SERVICE_API_KEY` to reach the files service; the files service itself owns GCS signing credentials and bucket configuration.

### Examples

- Start account deletion for the current user (from the client, via PostgREST):

```sql
select api.request_account_deletion(account_id);
```

### See also

- Queues and worker: [`docs/postgres/queues-and-worker.md`](queues-and-worker.md)  
- User recording uploads: [`docs/postgres/user-recording-uploads.md`](user-recording-uploads.md)  
- Files service: [`docs/files/README.md`](../files/README.md)
- Supervisor patterns: [`docs/patterns/supervisors.md`](../patterns/supervisors.md)
- Supervision trees: [`docs/patterns/supervision-trees.md`](../patterns/supervision-trees.md)

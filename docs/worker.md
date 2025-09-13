## Worker integration guide (service_api)

This document explains how a worker service fetches jobs and reports results using the service-facing schema secured by an API key.

### Endpoints (service_api)

- fetch_next_task(worker_id text, lease_seconds int default 60, task_type queues.task_type default null) → jsonb

  - Returns `{ job, payload }` or `{ job: null }` if no work.
  - `job` includes: `job_id, lease_id, task_type, resource_id, priority, scheduled_at`.
  - `payload` is channel-specific (email/sms), built server-side.

- report_task_result(worker_id text, job_id bigint, lease_id bigint, succeeded boolean, error_code text default null, error_message text default null, base_delay_seconds int default 30) → jsonb
  - Returns `{ completed, scheduled_retry, next_job_id, next_scheduled_at }`.
  - Throws exceptions on validation failures (invalid/missing lease, wrong worker, expired lease, already attempted).

### Authentication and schema selection

- Include the service API key in the request header `x-api-key`.
- Select the `service_api` schema via profile headers (PostgREST):
  - Use `Accept-Profile: service_api` for GET/HEAD
  - Use `Content-Profile: service_api` for POST/PATCH/PUT/DELETE/RPC
- Reference: [PostgREST Schemas](https://docs.postgrest.org/en/v12/references/api/schemas.html)

### Example (curl)

Fetch next task:

```bash
curl -s \
  -H "Accept-Profile: service_api" \
  -H "x-api-key: $SERVICE_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"worker_id":"service:host:pid","lease_seconds":60,"task_type":"email"}' \
  http://localhost:3000/rpc/fetch_next_task
```

Report result:

```bash
curl -s \
  -H "Accept-Profile: service_api" \
  -H "x-api-key: $SERVICE_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"worker_id":"service:host:pid","job_id":123,"lease_id":456,"succeeded":true}' \
  http://localhost:3000/rpc/report_task_result
```

### Worker loop (high-level)

1. Call `service_api.fetch_next_task(...)`.
2. If `job` is null, backoff and retry later.
3. Switch on `job.task_type`:
   - For `email`, use the `payload` to send email.
   - For `sms`, use the `payload` to send sms.
4. Call `service_api.report_task_result(...)` with `succeeded` and optional error info.
5. Repeat.

### Notes

- Leases are time-bound. Keep work within `lease_seconds` or plan for a future lease extension RPC.
- A job cannot be reprocessed after a success attempt exists. The API ensures safety and throws on invalid reports.

## Shared Logger

Purpose

- Structured JSON logging for all services with consistent fields and request correlation support.

API

- Initialize once per process: `logger.Init("<service>")`.
- Emit logs: `logger.Info|Warn|Error|Debug(ctx, message, logger.Fields{...})`.
- Attach request id: `ctx = logger.WithRequestID(ctx, requestID)`.

Fields

- `timestamp` (UTC), `level`, `service`, `message`.
- Optional: `request_id`, `error`, and custom `fields`.

Usage in services

- Gateway: initialized in main, used across proxy/auth/files helpers.
- Files: initialized in main for endpoint logs.
- Worker: initialized in main; used across dequeue/processing and error reporting.

Why

- Uniform logs simplify Datadog ingestion and cross‑service debugging. The request id stitches together edge, proxy, and service logs.

Navigate

- Docs index: [`../README.md`](../README.md)
- Shared Middleware: [`./middleware.md`](./middleware.md)
- Observability: [`../observability/README.md`](../observability/README.md)

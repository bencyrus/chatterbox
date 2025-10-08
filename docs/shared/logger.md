## Shared Logger

Status: current
Last verified: 2025-10-08

← Back to [`docs/shared/README.md`](./README.md)

### Why this exists

- Provide structured JSON logs with consistent fields and request correlation across services.

### Role in the system

- Centralizes logging in `gateway`, `files`, and `worker`; emits logs consumed by the platform (Docker/Datadog).

### API

- Source: [`shared/logger/logger.go`](../../shared/logger/logger.go)
- Initialize once per process

```go
logger.Init("gateway")
```

- Emit logs

```go
logger.Info(ctx, "starting", logger.Fields{"port": 8080})
logger.Error(ctx, "failed", err)
```

- Attach request id

```go
ctx = logger.WithRequestID(ctx, requestID)
```

### Fields

- `timestamp` (UTC), `level`, `service`, `message`.
- Optional: `request_id`, `error`, and custom `fields`.

### See also

- Docs index: [`../README.md`](../README.md)
- Shared Middleware: [`./middleware.md`](./middleware.md)
- Observability: [`../observability/README.md`](../observability/README.md)

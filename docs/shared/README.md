## Shared Components

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Provide common building blocks (logging and HTTP middleware) that ensure consistent observability and request correlation across services.

### Role in the system

- Used by `gateway`, `files`, and `worker` to standardize JSON logs and correlation via `X-Request-ID`.
- Enables end‑to‑end tracing of requests originating at Caddy through downstream services.

### Components

- Logger

  - Source: [`shared/logger/logger.go`](../../shared/logger/logger.go)
  - Initialize once per process, then use typed helpers to emit JSON logs.
  - Minimal example

    ```go
    logger.Init("gateway")
    logger.Info(ctx, "starting", logger.Fields{"port": 8080})
    ```

- HTTP Middleware

  - Source: [`shared/middleware/logging.go`](../../shared/middleware/logging.go)
  - Wraps a handler, extracts `X-Request-ID`, logs request/response with duration.
  - Minimal example

    ```go
    handler := middleware.RequestIDMiddleware(mux)
    ```

### See also

- Observability: [`../observability/README.md`](../observability/README.md)
- Caddy: [`../caddy/README.md`](../caddy/README.md)

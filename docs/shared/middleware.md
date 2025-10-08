## Shared HTTP Middleware

Status: current
Last verified: 2025-10-08

← Back to [`docs/shared/README.md`](./README.md)

### Why this exists

- Standardize request correlation and access logging for HTTP services.

### Role in the system

- Connects Caddy’s `X-Request-ID` header to downstream services by storing it in context and logging consistently.

### Component

- Source: [`shared/middleware/logging.go`](../../shared/middleware/logging.go)
- Signature: `RequestIDMiddleware(next http.Handler) http.Handler`
- Behavior
  - Extracts `X-Request-ID` header and stores it in context via `logger.WithRequestID`.
  - Logs an "incoming request" entry (method, path, remote) and a "request completed" entry (status, duration_ms).
  - Wraps the provided handler; does not mutate response bodies.

### Usage

- Gateway: wraps the reverse proxy in `cmd/gateway/main.go` to propagate `X-Request-ID`.
- Files: wraps the mux in `cmd/files/main.go` for request/response logging.

### See also

- Shared Logger: [`./logger.md`](./logger.md)
- Caddy: [`../caddy/README.md`](../caddy/README.md)
- Docs index: [`../README.md`](../README.md)

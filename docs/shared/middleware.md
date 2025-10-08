## Shared HTTP Middleware

Purpose

- Standardize request correlation and access logging for HTTP services.

Component

- `RequestIDMiddleware(next http.Handler) http.Handler`
  - Extracts `X-Request-ID` header and stores it in the context via `logger.WithRequestID`.
  - Logs an "incoming request" entry (method, path, remote) and a "request completed" entry (status, duration_ms).
  - Wraps the provided handler without altering response bodies.

Usage

- Gateway: wraps the reverse proxy in `cmd/gateway/main.go` to propagate `X-Request-ID`.
- Files: wraps the mux in `cmd/files/main.go` for request/response logging.

Why

- Ensures every request has a correlation id and consistent access logs across services.

Navigate

- Docs index: [`../README.md`](../README.md)
- Shared Logger: [`./logger.md`](./logger.md)
- Caddy: [`../caddy/README.md`](../caddy/README.md)

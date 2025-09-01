Shared

Purpose

- Common logging and HTTP middleware used by services.

Packages

- `logger`: JSON logs, includes `service` and optional `request_id`. Initialize with `logger.Init("<service>")`.
- `middleware`: `RequestIDMiddleware` extracts `X-Request-ID`, logs request/response, and measures duration.

Usage

- Initialize logger in `main()` and wrap your mux/handler with `RequestIDMiddleware`.

References

- Logger: [`shared/logger/logger.go`](logger/logger.go)
- Middleware: [`shared/middleware/logging.go`](middleware/logging.go)

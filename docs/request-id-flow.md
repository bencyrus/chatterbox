# Request ID Standardization

This document describes how request IDs flow through the Chatterbox system to enable distributed tracing and log correlation.

## Overview

Every request through the system gets a unique UUID that flows through all services, enabling you to trace a single request across multiple services and correlate logs in Datadog.

## Request ID Flow

```
Client Request
    ↓
Caddy (generates UUID)
    ↓ X-Request-ID header
Gateway (logs with request_id)
    ↓ X-Request-ID + X-Correlation-ID headers
PostgREST (receives headers)
    ↓ X-Request-ID header
Files Service (logs with request_id)
```

## Implementation Details

### 1. Caddy (Entry Point)

- **Generates**: UUID using `{http.request.uuid}`
- **Adds to response**: `X-Request-ID` header for clients
- **Forwards**: `X-Request-ID` header to gateway
- **Logs**: Request ID included in JSON access logs

**Configuration**: `/caddy/Caddyfile`

```caddy
header X-Request-ID {http.request.uuid}
reverse_proxy gateway:8080 {
    header_up X-Request-ID {http.request.uuid}
}
log {
    output stdout
    format json {
        request_id {http.request.uuid}
    }
}
```

### 2. Gateway Service

- **Receives**: `X-Request-ID` from Caddy
- **Middleware**: `middleware.RequestIDMiddleware` extracts header and adds to context
- **Logs**: All log entries include `request_id` field
- **Forwards**: `X-Request-ID` and `X-Correlation-ID` to PostgREST
- **Forwards**: `X-Request-ID` to Files service

**Key Files**:

- `gateway/cmd/gateway/main.go` - applies middleware
- `shared/middleware/logging.go` - extracts request ID
- `gateway/internal/proxy/proxy.go` - forwards to PostgREST
- `gateway/internal/files/processor.go` - forwards to Files service

### 3. Files Service

- **Receives**: `X-Request-ID` from Gateway
- **Middleware**: Same `middleware.RequestIDMiddleware` as Gateway
- **Logs**: All log entries include `request_id` field

**Key Files**:

- `files/cmd/files/main.go` - applies middleware

### 4. PostgREST

- **Receives**: `X-Request-ID` and `X-Correlation-ID` from Gateway
- **Logs**: Standard PostgREST access logs (limited request ID support)
- **Configuration**: Set to `info` log level for more detailed request logging

**Configuration**: `docker-compose.yaml`

```yaml
environment:
  - PGRST_LOG_LEVEL=info
```

## Log Examples

### Gateway/Files Services (Structured JSON)

```json
{
  "timestamp": "2025-09-02T00:00:37.665890251Z",
  "level": "info",
  "service": "gateway",
  "request_id": "b55ec992-4ac3-4286-a6ec-88b2264f6a77",
  "message": "incoming request",
  "fields": {
    "path": "/hello_secure",
    "method": "GET",
    "remote": "172.18.0.6:49542"
  }
}
```

### Caddy (JSON Access Logs)

```json
{
  "request_id": "b55ec992-4ac3-4286-a6ec-88b2264f6a77",
  "status": 200,
  "duration": 0.044059062,
  "request": {
    "method": "GET",
    "uri": "/hello_secure",
    "headers": {...}
  },
  "resp_headers": {
    "X-Request-Id": ["b55ec992-4ac3-4286-a6ec-88b2264f6a77"]
  }
}
```

### PostgREST (Standard Access Logs)

```
172.18.0.5 - authenticated [02/Sep/2025:00:00:37 +0000] "GET /hello_secure HTTP/1.1" 200 37 "" "PostmanRuntime/7.43.0"
```

_Note: PostgREST logs don't include request IDs by default, but headers are forwarded for potential custom logging solutions._

## Datadog Integration

All services are configured with Datadog log collection labels in `docker-compose.yaml`:

```yaml
labels:
  - 'com.datadoghq.ad.logs=[{"source": "gateway", "service": "gateway"}]'
```

In Datadog, you can:

1. **Filter by request ID**: Search for `request_id:"b55ec992-4ac3-4286-a6ec-88b2264f6a77"`
2. **Correlate across services**: Same request ID appears in Gateway, Files, and Caddy logs
3. **Trace request flow**: Follow a request through the entire system

## Benefits

1. **Distributed Tracing**: Follow requests across multiple services
2. **Debugging**: Quickly find all logs related to a specific request
3. **Performance Analysis**: Measure total request time across services
4. **Error Correlation**: Link errors across service boundaries

## Troubleshooting

### Request ID Missing in Logs

- Check that `middleware.RequestIDMiddleware` is applied in service main.go
- Verify Caddy is forwarding `X-Request-ID` header
- Ensure logger is initialized with `logger.Init("service-name")`

### PostgREST Not Showing Request IDs

- PostgREST has limited request ID support
- Request IDs are forwarded as headers but not logged by default
- Consider implementing custom logging middleware if needed

## Future Enhancements

1. **Custom PostgREST Logging**: Implement middleware to capture request IDs
2. **Metrics Integration**: Add request ID to custom metrics
3. **Error Tracking**: Include request IDs in error reporting systems

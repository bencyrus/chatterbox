Gateway

Overview

The gateway fronts PostgREST and transparently handles:

- Auth token maintenance: When the access token is close to expiry (within REFRESH_THRESHOLD_SECONDS) and a refresh token header is present, it preflights a refresh (max 2s budget). If successful, it adds new tokens to the response headers without blocking or failing the upstream request.
- File URL resolution: When an upstream JSON response includes a files array, the gateway calls the file service to resolve signed URLs and injects processed_files into the JSON while preserving the original files field.

How it works

- Request in → gateway → optional token refresh (preflight, 2s timeout) → reverse proxy to PostgREST
- Response from PostgREST → gateway injects signed file URLs if files found → response out
- Refresh success or failure never blocks or fails the main request. New tokens, when available, are returned via headers for the client to rotate.

Headers

- Incoming refresh header: REFRESH_TOKEN_HEADER_IN (default X-Refresh-Token)
- Outgoing refreshed tokens: NEW_ACCESS_TOKEN_HEADER_OUT (default X-New-Access-Token), NEW_REFRESH_TOKEN_HEADER_OUT (default X-New-Refresh-Token)

Environment variables

Required

- POSTGREST_URL: Base URL for the PostgREST upstream (e.g., http://postgrest:3000)
- JWT_SECRET: Must match the DB secret used to sign tokens
- REFRESH_TOKENS_PATH: RPC path for token refresh (e.g., /rpc/refresh_tokens)
- REFRESH_THRESHOLD_SECONDS: Only refresh when the access token expires within this many seconds
- FILE_SERVICE_URL: Base URL for the file service (e.g., https://files.glovee.io)
- FILE_SIGNED_URL_PATH: Path to the signed URL endpoint (e.g., /signed_url)
- FILES_FIELD_NAME: JSON field name for file IDs array (e.g., files)
- PROCESSED_FILES_FIELD_NAME: JSON field name for injected results (e.g., processed_files)

Optional (defaults shown)

- PORT=8080
- REFRESH_TOKEN_HEADER_IN=X-Refresh-Token
- NEW_ACCESS_TOKEN_HEADER_OUT=X-New-Access-Token
- NEW_REFRESH_TOKEN_HEADER_OUT=X-New-Refresh-Token
- HTTP_CLIENT_TIMEOUT_SECONDS=10

Example env (copy into secrets/.env.gateway)

```
PORT=8080

POSTGREST_URL=http://postgrest:3000
JWT_SECRET=replace_me_with_jwt_secret
REFRESH_TOKENS_PATH=/rpc/refresh_tokens
REFRESH_THRESHOLD_SECONDS=60

REFRESH_TOKEN_HEADER_IN=X-Refresh-Token
NEW_ACCESS_TOKEN_HEADER_OUT=X-New-Access-Token
NEW_REFRESH_TOKEN_HEADER_OUT=X-New-Refresh-Token

FILE_SERVICE_URL=http://files:8080
FILE_SIGNED_URL_PATH=/signed_url
FILES_FIELD_NAME=files
PROCESSED_FILES_FIELD_NAME=processed_files

HTTP_CLIENT_TIMEOUT_SECONDS=10
```

Development & running

- docker-compose: The root compose file defines the gateway service and mounts secrets/.env.gateway.
- Local build: inside gateway/, run go build ./... or go run ./cmd/gateway

Notes

- Refresh runs only when Authorization: Bearer <access> is within REFRESH_THRESHOLD_SECONDS of exp and REFRESH_TOKEN_HEADER_IN is provided.
- File URL processing only runs for application/json responses containing a top-level files array.
- Fail-safe design: both features are best-effort and never fail the main request.

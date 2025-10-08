## Gateway Auth Refresh

Purpose

- Refresh access/refresh tokens opportunistically when the access token is near expiry, without blocking the main request.

How it works

- Parse Authorization bearer using the configured `JWT_SECRET` to read `exp`.
- If seconds remaining ≤ `REFRESH_THRESHOLD_SECONDS` and a refresh token header is present, start a preflight refresh with a short timeout (2s budget).
- On success, attach refreshed tokens to the downstream response headers; the main proxied request proceeds regardless of refresh outcome.

Key code paths

- Token parsing: `internal/auth/helpers.go` → `AccessTokenSecondsRemaining`, `ShouldRefreshAccessToken`.
- Preflight refresh: `internal/auth/helpers.go` → `PreflightRefresh` (2s timeout), `AttachRefreshedTokens`.
- Refresh RPC: `internal/auth/refresher.go` → `RefreshIfPresent` POSTs to `POSTGREST_URL + REFRESH_TOKENS_PATH`, expects `{ access_token, refresh_token }`.
- Proxy integration: `internal/proxy/proxy.go` → `ModifyResponse` attaches new tokens if present.

Configuration (env)

- `POSTGREST_URL` (required): PostgREST base URL.
- `JWT_SECRET` (required): used to parse access token `exp`.
- `REFRESH_TOKENS_PATH` (required): RPC path (e.g., `/rpc/refresh_tokens`).
- `REFRESH_THRESHOLD_SECONDS` (required): seconds remaining to trigger preflight refresh.
- `REFRESH_TOKEN_HEADER_IN` (optional, default `X-Refresh-Token`): incoming refresh header.
- `NEW_ACCESS_TOKEN_HEADER_OUT` (optional, default `X-New-Access-Token`): outgoing header with new access token.
- `NEW_REFRESH_TOKEN_HEADER_OUT` (optional, default `X-New-Refresh-Token`): outgoing header with new refresh token.
- `HTTP_CLIENT_TIMEOUT_SECONDS` (optional, default `10`): refresh HTTP client timeout.

Headers

- Incoming: `Authorization: Bearer <access>`, `X-Refresh-Token: <refresh>`.
- Outgoing (if refreshed): `X-New-Access-Token`, `X-New-Refresh-Token`.

Behavior notes

- Refresh is best‑effort; failure never blocks or fails the proxied request.
- Only attempts refresh when both: access token is near expiry and the refresh header is present.

Navigate

- File URL injection: [`./files-injection.md`](./files-injection.md)
- Gateway index: [`./README.md`](./README.md)

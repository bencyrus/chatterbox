## Gateway Auth Refresh

Status: current
Last verified: 2025-10-08

← Back to [`docs/gateway/README.md`](./README.md)

### Why this exists

- Keep access tokens fresh without adding latency or coupling to the main request path.

### How it works

- Parse `Authorization: Bearer <token>` using `JWT_SECRET` (HS256) to read `exp`.
- If seconds remaining ≤ `REFRESH_THRESHOLD_SECONDS` and a refresh header is present, attempt a preflight refresh with ~2s timeout.
- On success, attach refreshed tokens to response headers; the proxied request proceeds regardless of refresh outcome.

### Key code paths

- Token parsing & decision: [`gateway/internal/auth/helpers.go`](../../gateway/internal/auth/helpers.go)

  ```go
  remaining, ok := AccessTokenSecondsRemaining(cfg, headers, now)
  if ok && remaining <= cfg.RefreshThresholdSeconds { /* refresh */ }
  ```

- Proxy preflight refresh: [`gateway/internal/proxy/proxy.go`](../../gateway/internal/proxy/proxy.go)

  ```go
  var refreshed *auth.RefreshResult
  if auth.ShouldRefreshAccessToken(g.cfg, r.Header, time.Now()) && r.Header.Get(g.cfg.RefreshTokenHeaderIn) != "" {
      refreshed = auth.PreflightRefresh(ctx, g.cfg, r.Header, 2*time.Second)
  }
  ```

- Refresh RPC: [`gateway/internal/auth/refresher.go`](../../gateway/internal/auth/refresher.go)

  ```go
  // POST to POSTGREST_URL + REFRESH_TOKENS_PATH expecting { access_token, refresh_token }
  ```

- Proxy integration: [`gateway/internal/proxy/proxy.go`](../../gateway/internal/proxy/proxy.go)

  ```go
  auth.AttachRefreshedTokens(resp.Header, g.cfg, refreshed)
  ```

### Configuration (env)

- Required: `POSTGREST_URL`, `JWT_SECRET`, `REFRESH_TOKENS_PATH`, `REFRESH_THRESHOLD_SECONDS`.
- Optional: `REFRESH_TOKEN_HEADER_IN` (default `X-Refresh-Token`), `NEW_ACCESS_TOKEN_HEADER_OUT` (default `X-New-Access-Token`), `NEW_REFRESH_TOKEN_HEADER_OUT` (default `X-New-Refresh-Token`), `HTTP_CLIENT_TIMEOUT_SECONDS` (default `10`).

### Headers

- Incoming: `Authorization: Bearer <access>`, `X-Refresh-Token: <refresh>`.
- Outgoing (if refreshed): `X-New-Access-Token`, `X-New-Refresh-Token`.

### Example

```bash
curl -i \
  -H "Authorization: Bearer <access>" \
  -H "X-Refresh-Token: <refresh>" \
  http://localhost:8080/any/path
# If refreshed, response includes: X-New-Access-Token, X-New-Refresh-Token
```

### Behavior notes

- Best‑effort: failure never blocks the proxied request.
- Only attempts refresh when both conditions are met (near expiry and refresh header present).

### See also

- File URL injection: [`./files-injection.md`](./files-injection.md)
- Gateway index: [`./README.md`](./README.md)

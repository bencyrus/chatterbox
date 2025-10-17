## Gateway OpenAPI

Status: current
Last verified: 2025-10-15

← Back to [`docs/gateway/README.md`](./README.md)

### Why this exists

- Expose PostgREST’s OpenAPI schema through the gateway at a stable path for tooling (codegen, docs, testing).
- Forward caller Authorization so the schema reflects role-based visibility.

### Role in the system

- The gateway serves `GET /openapi.json` and proxies to PostgREST, requesting the OpenAPI in JSON.
- The response mirrors PostgREST’s OpenAPI, including content type and status.

### How it works

- The gateway route is served by a dedicated handler package that fetches from the configured PostgREST URL with `Accept: application/openapi+json` and forwards `Authorization`.
- Source: [`gateway/internal/httpapi/openapi.go`](../../gateway/internal/httpapi/openapi.go)

```1:34:gateway/internal/httpapi/openapi.go
func NewOpenAPIHandler(cfg config.Config) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx := r.Context()
        client := &http.Client{Timeout: time.Duration(cfg.HTTPClientTimeoutSeconds) * time.Second}
        req, _ := http.NewRequestWithContext(ctx, http.MethodGet, cfg.PostgRESTURL, nil)
        if authz := r.Header.Get("Authorization"); authz != "" { req.Header.Set("Authorization", authz) }
        req.Header.Set("Accept", "application/openapi+json")
        resp, _ := client.Do(req)
        defer resp.Body.Close()
        for k, vals := range resp.Header { for _, v := range vals { w.Header().Add(k, v) } }
        if w.Header().Get("Content-Type") == "" { w.Header().Set("Content-Type", "application/openapi+json") }
        w.WriteHeader(resp.StatusCode)
        io.Copy(w, resp.Body)
    })
}
```

### Operations

- Endpoint: `GET /openapi.json` (via gateway, default port `8080`).
- Auth: forward `Authorization: Bearer <token>` to see the schema for that role.

### Examples

- Fetch schema

```bash
curl -sS http://localhost:8080/openapi.json | jq '.info, .paths | keys[0:10]'
```

- With Authorization (authenticated role)

```bash
curl -sS \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  http://localhost:8080/openapi.json | jq '.paths | keys[]'
```

- Generate client (TypeScript, using openapi-typescript)

```bash
npx openapi-typescript http://localhost:8080/openapi.json -o api.types.ts
```

### See also

- Gateway: [`./README.md`](./README.md)
- Auth refresh: [`./auth-refresh.md`](./auth-refresh.md)
- File URL injection: [`./files-injection.md`](./files-injection.md)

## Caddy (Reverse Proxy)

Purpose

- Public entrypoint for the system. Terminates TLS, assigns a request correlation id, and reverse‑proxies to the gateway.

Behavior

- Generates a unique `X-Request-ID` per request and sets it on the response.
- Forwards the same `X-Request-ID` upstream to the gateway so all downstream logs share the correlation id.
- Emits JSON access logs.

Configuration

- Caddy is configured to proxy all traffic to the gateway on the private network.
- It injects and forwards `X-Request-ID` so downstream services and logs are correlated end‑to‑end.
- Only ports `80` and `443` are exposed externally; all other services are internal.

Headers

- `X-Request-ID`: required for request correlation. The gateway and other Go services read this header via the shared middleware and include it in structured logs.

Security model

- Only Caddy is internet‑facing. The gateway, PostgREST, Postgres, files service, and worker communicate on a private bridge network behind it.
- PostgREST is not exposed externally; public access flows through Caddy → gateway → PostgREST.

Operations

- Logs are emitted in JSON to stdout (consumed by Datadog).
- Configuration changes are applied by reloading/restarting the container.

Navigate

- Docs index: [`../README.md`](../README.md)
- Gateway: [`../gateway/README.md`](../gateway/README.md)
- Observability: [`../observability/README.md`](../observability/README.md)
- Compose topology: [`../compose/README.md`](../compose/README.md)

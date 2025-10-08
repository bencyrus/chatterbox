## Gateway

Purpose

- Reverse proxy to PostgREST with two responsibilities: best‑effort token refresh and file URL post‑processing.

Philosophy

- Edge responsibilities belong at the edge: token freshness and response enrichment are handled here to keep the database API stable and focused.
- The gateway does not alter business logic; it performs safe, fail‑open enhancements:
  - Token refresh is best‑effort and never blocks the proxied request.
  - File URL injection preserves original fields and only adds `processed_files`.
- This separation lets PostgREST remain a thin lens over database state while the gateway handles protocol and UX concerns.

Read next

- Auth refresh flow: [`./auth-refresh.md`](./auth-refresh.md)
- File URL injection: [`./files-injection.md`](./files-injection.md)
- Shared components: [`../shared/README.md`](../shared/README.md)
- Docs index: [`../README.md`](../README.md)

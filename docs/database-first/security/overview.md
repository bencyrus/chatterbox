# Security

## Philosophy

In a database-first system, security is enforced at the data layer, not the application layer. The database is the authority — not middleware, not application code.

Four principles govern this model:

- **Authentication logic lives in PostgreSQL functions.** Login, token creation, and verification are SQL.
- **Authorization is enforced via Row-Level Security (RLS).** Tenants are isolated by the database, not by `WHERE` clauses scattered across application code.
- **Each service gets the minimum database privileges it needs.** Grants target specific functions, never tables.
- **Secrets never touch application code.** They're injected at deploy time through environment substitution.

---

## Authentication Architecture

### In-Database JWT

JWT creation and validation happen inside PostgreSQL using the `pgjwt` extension. When a user authenticates, a PostgreSQL function generates a signed JWT containing three claims:

| Claim | Purpose |
|---|---|
| `role` | The PostgreSQL role PostgREST should assume |
| `account_id` | Tenant identifier for RLS policy evaluation |
| `token_use` | Domain separation: `access` or `refresh` |

PostgREST reads the incoming JWT, validates the signature, and sets the PostgreSQL role for the session. Every subsequent query runs under that role with its grants and RLS policies in effect.

```sql
create or replace function auth.generate_token(account auth.account)
returns auth.token_pair as $$
declare
  access_token  text;
  refresh_token text;
  refresh_raw   text;
begin
  access_token := sign(
    json_build_object(
      'role',       'app_user',
      'account_id', account.account_id::text,
      'token_use',  'access',
      'exp',        extract(epoch from now() + interval '15 minutes')::integer
    ),
    current_setting('app.jwt_secret')
  );

  refresh_raw := encode(gen_random_bytes(32), 'hex');

  insert into auth.refresh_token (account_id, token_hash, expires_at)
  values (account.account_id, crypt(refresh_raw, gen_salt('bf')), now() + interval '7 days');

  return (access_token, refresh_raw);
end;
$$ language plpgsql security definer;
```

### Login Flows

All login flows are implemented as PostgreSQL functions. No application-layer authentication code exists.

**OTP (one-time password):** A function generates a short-lived numeric code and stores a hashed copy. Delivery (SMS or email) is triggered via event queue. A second function verifies the code, enforces expiry, and returns a token pair on success.

**Magic links:** A function generates a random token, stores its hash, and emits the link via event queue. On click, a verification function compares the hash, enforces single-use (deletes on success), and issues credentials. The token row is consumed — replay is impossible.

**Reviewer login:** Issues tokens with a `reviewer` role carrying limited grants — read access to specific views, no write access to core tables.

### Token Refresh

Refresh tokens are hashed with bcrypt before storage. The raw token is returned to the client exactly once. On refresh, the client sends the raw token; the database compares it against the stored hash. Access tokens are short-lived (15 minutes). Refresh tokens are longer-lived (7 days) and single-use — each refresh rotates the token.

The API gateway performs best-effort refresh as a preflight step. If the access token is expired but a valid refresh token is present, the gateway transparently refreshes before proxying. This never blocks — if refresh fails, the request proceeds and PostgREST returns `401`.

---

## Authorization: Principle of Least Privilege

### Service Users

Each backend service connects to PostgreSQL with its own restricted user. No service shares credentials with another.

```sql
create user worker_service_user with login password '...';
create user file_service_user with login password '...';
create user backup_service_user with login password '...';

grant execute on function queues.dequeue_next_available_task() to worker_service_user;
grant execute on function storage.generate_signed_url(text, text, interval) to file_service_user;
```

Grants target specific functions, never tables. A service that needs to dequeue tasks cannot read the task table directly — it can only call the dequeue function.

### SECURITY DEFINER vs INVOKER

PostgreSQL functions run in one of two security contexts:

- **`SECURITY DEFINER`**: Executes with the privileges of the function owner. Used for business logic that needs table access the caller doesn't have.
- **`SECURITY INVOKER`**: Executes with the privileges of the caller. Used for the function runner — a generic wrapper that inherits the caller's restricted grants.

This creates a controlled escalation pattern. A worker can call a supervisor function (`SECURITY DEFINER`, broad access), but has no direct table grants. If the function doesn't exist, the worker can't improvise access.

### Row-Level Security (RLS)

RLS enforces tenant isolation at the database level. Every query — regardless of origin — is filtered through RLS policies.

```sql
alter table accounts.account enable row level security;

create policy account_isolation on accounts.account
  for all
  using (account_id = current_setting('request.jwt.claims')::jsonb->>'account_id');
```

PostgREST sets JWT claims as PostgreSQL session variables. RLS policies reference these variables. A query from account `A` physically cannot return rows belonging to account `B`. Multi-tenant isolation requires zero application code.

---

## ID Generation Strategy

### Internal IDs: `bigserial`

All internal primary keys and foreign keys use `bigserial`. Sequential IDs are fast (no random I/O), compact (8 bytes), and optimal for B-tree index performance. Join performance is predictable.

### External-Facing IDs: Opaque Identifiers

Sequential IDs exposed to clients enable enumeration attacks — revealing total counts, enabling scraping, and leaking growth rate. External-facing identifiers use a separate column:

```sql
alter table accounts.account
  add column external_id text not null default generate_cuid2();

create unique index on accounts.account (external_id);
```

Two strong options:

| Format | Properties |
|---|---|
| **CUID2** | Compact, URL-safe, collision-resistant, no ordering leakage |
| **UUID v7** | Time-ordered (good for index locality), native in PostgreSQL 18+ |

The external ID is never the primary key. Internal joins use `bigserial`. API responses expose only the opaque identifier.

---

## File Security

### Signed URLs

Files are never served directly through the application. Every file operation goes through time-limited signed URLs issued by the cloud storage provider.

- **Upload:** The client requests a signed PUT URL from the API. The API generates it (server-side, using storage credentials the client never sees). The client uploads directly to cloud storage.
- **Download:** The gateway enriches API responses by replacing file references with signed GET URLs. URLs expire after a short TTL.
- **Delete:** The worker receives signed DELETE URLs for cleanup operations during account deletion or file management.

### Recommendations for Sensitive Files

**Envelope encryption.** Each file is encrypted with a unique data encryption key (DEK) using AES-256-GCM. The DEK is encrypted with a key encryption key (KEK) from cloud KMS. The encrypted DEK is stored alongside the ciphertext. Compromised storage alone yields nothing.

**Opaque object keys.** Storage paths must not contain account IDs or filenames. Use random identifiers: `objects/cln3x9k2a0001...` not `accounts/42/profile.jpg`.

**Short TTL on signed URLs.** 15 minutes or less. Leaked URLs become useless quickly.

**Client-side encryption.** For maximum security, encrypt before upload. The server never sees plaintext.

---

## Secrets Management

### Pattern

All secrets live in `secrets/.env.*` files, which are gitignored. The structure enforces per-service isolation and environment separation:

```
secrets/
├── .env.gateway.local     # Local development
├── .env.gateway            # Production
├── .env.worker.local
├── .env.worker
├── .env.files.local
├── .env.files
└── .env.db.local
```

Database migration files use `{secrets.key}` placeholders. At migration apply time, a substitution step replaces placeholders with values from the appropriate env file. Secrets never appear in version-controlled SQL.

### Best Practices

- **Never commit secrets.** The `.gitignore` covers `secrets/`, but verify before every push.
- **Strong generation.** All passwords are randomly generated, minimum 32 characters. Use `openssl rand -base64 32` or equivalent.
- **Rotation.** Rotate production credentials on a regular schedule. The per-service isolation model means rotating one service's credentials doesn't affect others.
- **File permissions.** `chmod 600` on all env files. Only the deploying user can read them.
- **Environment separation.** Development and production credentials are completely independent. A leaked dev secret yields zero production access.

---

## Account Deletion and Data Privacy

### GDPR-Compliant Deletion

Account deletion is a supervisor-driven, multi-phase process with a full audit trail.

| Phase | Action | Verification |
|---|---|---|
| **1** | Delete all user files from cloud storage via signed DELETE URLs | Storage provider confirms object removal |
| **2** | Anonymize PII — replace names with `[deleted]`, hash email addresses, clear metadata | Row-level verification that no PII remains |
| **3** | Mark account as deleted, revoke all tokens | Login guard confirms account is inaccessible |

Each phase completion is recorded with a timestamp. If any phase fails, the process halts and alerts — partial deletion is never silently accepted.

### Anonymization vs Hard Delete

Hard deletion destroys the audit trail. Anonymization preserves referential integrity — foreign keys remain valid, aggregate analytics stay accurate — while removing all PII. The account row exists but contains nothing identifiable.

Deleted accounts cannot authenticate. The login function checks deletion status before credential verification, and all refresh tokens are revoked at deletion time.

---

## TLS and Network Security

Only the reverse proxy (Caddy) is internet-facing. It terminates TLS and proxies to internal services.

Internal services communicate over a Docker bridge network. Traffic never leaves the host, so internal TLS is unnecessary — the network boundary is the Docker daemon.

Caddy handles automatic TLS certificate provisioning and renewal via ACME (Let's Encrypt). All outbound API calls (cloud storage, email providers, SMS gateways) use HTTPS. Outbound HTTP is blocked at the network level.

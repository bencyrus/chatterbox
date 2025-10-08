## OTP Login (passwordless)

Status: current
Last verified: 2025-10-08

← Back to [`docs/postgres/README.md`](./README.md)

### Why this exists

- Document the passwordless one-time code login flow that complements basic auth, including data model, helpers, API, delivery via comms, and behaviors.

### Highlights

- Identifiers: email or E.164 phone number; accounts may have either or both.
- Codes: 6-digit numeric; validity window from config (`internal.config` → key `login_with_code` → `code_expiry_minutes`, default 5).
- Delivery: via `comms` system (email or SMS) using templates; scheduling is asynchronous.
- Verification: accepts the latest unused code, within TTL.

### Data model

- `accounts.account`: base account; constraints validate email/phone and require at least one.
- `auth.login_code`: issued codes `(login_code_id, account_id, code, created_at)`.
- `auth.login_code_usage`: usage facts `(login_code_usage_id, login_code_id unique, used_at)`.

### Helpers

- Identifier handling: `accounts.get_account_identifier_type`, `accounts.get_account_by_identifier`, `accounts.get_or_create_account_by_identifier`.
- Codes: `auth.generate_login_code()`, `auth.code_expiry_minutes()`.
- Latest unused code (unexpired): `auth.get_latest_unused_login_code_for_account(account_id)`.
- Get or create active code: `auth.get_or_create_active_login_code_for_account(account_id)`.
- Record usage: `auth.record_login_code_usage(login_code_id)`.
- Record login: `auth.record_account_login(account_id)`.

### API

- Request code

```sql
select api.request_login_code('user@example.com');
-- or
select api.request_login_code('+15551234567');
```

- Validates identifier, finds or creates account, gets or creates an active code, renders template, and schedules delivery via comms.
- Errors (exception hints): `missing_identifier`, `invalid_identifier`, `email_template_not_found`, `sms_template_not_found`.

- Verify code

```sql
select api.login_with_code('user@example.com', '123456');
```

- Validates identifier, loads account, ensures the latest unused code matches and is within TTL, records usage and login, and returns `{ access_token, refresh_token }`.
- Errors (exception hints): `missing_identifier`, `invalid_identifier`, `account_not_found`, `invalid_login_code`.

Templates (seeded)

- Email: `login_with_code` subject/body include `${code}` and `${minutes}`.
- SMS: `login_with_code` body includes `${code}` and `${minutes}`.

### Notes

- Delivery is scheduled asynchronously; the request itself is synchronous.
- Comm templates are rendered with `comms.render_email_template` and `comms.render_sms_template` using params `{ code, minutes }`.

### See also

- Back to Postgres: [Postgres Index](README.md)

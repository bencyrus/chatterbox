## Magic Token Login (passwordless)

Status: current
Last verified: 2025-10-18

← Back to [`docs/auth/README.md`](./README.md)

### Why this exists

- Provide a passwordless login that removes code entry; links delivered by email or SMS.

### Highlights

- Single-use tokens, hashed at rest, TTL from config.
- Delivery via `comms` system; scheduling is asynchronous.
- Verification exchanges the token for `{ access_token, refresh_token }`.

### Configuration

- `internal.config` key `magic_login` is seeded via migrations with secrets placeholders:

```
{
  "token_expiry_minutes": 15,
  "link_https_base_url": "{secrets.magic_login_link_https_base_url}"
}
```

- Provide `MAGIC_LOGIN_LINK_HTTPS_BASE_URL` in `secrets/.env.postgres` (and `.env.postgres.example`).

### Data model

- `auth.magic_login_token`: tokens `(magic_login_token_id, account_id, token_hash, created_at)`.
- `auth.magic_login_token_usage`: usage facts `(magic_login_token_usage_id, magic_login_token_id unique, used_at)`.

### Helpers

- Expiry config: `auth.magic_token_expiry_minutes()` from `internal.config` key `magic_login`.
- Generate+store token: `auth.create_magic_login_token(account_id)` returns plaintext token + row; stores only hash.
- Latest unused token (unexpired): `auth.get_latest_unused_magic_login_token_for_account(account_id)`.
- Record usage: `auth.record_magic_login_token_usage(magic_login_token_id)`.
- Record login: `auth.record_account_login(account_id)`.

### API

- Request link

```sql
select api.request_magic_link('user@example.com');
-- or
select api.request_magic_link('+15551234567');
```

- Validates identifier, finds or creates account, generates a fresh token, builds a link URL from config (`link_https_base_url` primary, fallback `link_app_scheme_url`), renders template, and schedules delivery via comms.
- Errors (exception hints): `missing_identifier`, `invalid_identifier`, `email_template_not_found`, `sms_template_not_found`.

- Login with link

```sql
select api.login_with_magic_token('token-from-url');
```

- Validates token, finds latest unused and unexpired hash match, records usage and login, and returns `{ access_token, refresh_token }`.
- Errors (exception hints): `missing_magic_link_token`, `invalid_magic_link`.

### Templates (seeded)

- Email: `magic_login_link_email` subject/body include `${url}` and `${minutes}`.
- SMS: `magic_login_link_sms` body includes `${url}` and `${minutes}`.

### Behavior notes

- Single-use: consumption records usage; subsequent attempts are rejected.
- TTL enforced via created_at check; active tokens may be reused by request endpoint to limit churn.

### See also

- OTP: [`./otp-login.md`](./otp-login.md)
- Access token refresh: [`./auth-refresh.md`](./auth-refresh.md)

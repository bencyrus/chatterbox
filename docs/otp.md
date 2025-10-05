## OTP login (email or SMS)

This document describes the passwordless OTP login flow that complements existing basic auth. The OTP system follows the project conventions: append-only facts, exceptions only at the `api.*` layer, and supervisor-driven comms scheduling for delivery.

### Highlights

- **Identifiers**: Users authenticate via either email or phone number (E.164). Accounts may have either or both.
- **No password**: Accounts can be passwordless; existing basic auth remains untouched and compatible.
- **Codes**: 6-digit numeric code, valid for 2 minutes. On request, if an unused code exists with at least 30 seconds remaining, the same code is returned (to avoid churn); otherwise a new code is generated.
- **Delivery**: Codes are sent via the `comms` system (email or SMS) using seeded templates and the supervisor pattern. The request itself is synchronous; sending is asynchronous.
- **Verification**: Only the latest unused code for the account is accepted. Success records usage and issues JWTs; failures are logged.

### Data model (auth)

- `auth.account`
  - Adds `phone_number text` (validated, unique when present)
  - `email` and `hashed_password` may be null; constraint enforces at least one of `email` or `phone_number`
- `auth.otp_code`
  - Append-only issued codes: `(otp_code_id, account_id, code, created_at)`
- `auth.otp_code_used`
  - Append-only successful consumptions: `(otp_code_used_id, otp_code_id unique, used_at)`
- `auth.otp_code_failed_attempt`
  - Append-only failed verifications for observability: `(otp_code_failed_attempt_id, account_id, code_attempted, created_at)`

### Templates (comms)

- Email: `otp_login_email`
  - Subject: `Your Chatterbox sign-in code: ${code}`
  - Body params: `code`, `minutes`
- SMS: `otp_login_sms`
  - Body: `Your Chatterbox sign-in code is ${code}. Expires in ${minutes} min.`

### Internal helpers

- `auth.is_phone_valid(text)`, `auth.normalize_phone(text)`
- `auth.generate_otp_code()`: 6-digit code (may include leading zeros)
- `auth.get_latest_unused_otp_for_account(account_id)`
- `auth.get_or_create_login_code(account_id)`

### API

- `api.request_login_code(identifier text) returns jsonb`

  - Identifier is an email or phone; validates, finds/creates account, gets or creates an OTP code, and schedules delivery via comms.
  - Returns: `{ "success": true }` on success.
  - Errors (exception hints): `missing_identifier`, `invalid_email`, `invalid_phone_number`, `template_not_found`.

- `api.verify_login_code(identifier text, code text) returns jsonb`
  - Validates, loads account, checks the latest unused code is not expired and matches.
  - On success: records usage and login, and returns `{ access_token, refresh_token }`.
  - Errors (exception hints): `missing_identifier`, `missing_code`, `account_not_found`, `code_not_found`, `code_expired`, `invalid_code`.

### Behavior notes

- **Expiry**: Codes expire 2 minutes after creation; verification uses this TTL rather than storing explicit expiry.
- **Reuse threshold**: If a code is unused and has less than 30 seconds remaining, it is reused on request; otherwise a new code is generated.
- **Append-only facts**: All OTP events (issued, used, failed) are append-only; current state is derived from these facts.
- **Observability**: Failed verifications insert into `auth.otp_code_failed_attempt` with the attempted code value.

### Examples

```sql
-- Request a code to email
select api.request_login_code('user@example.com');

-- Request a code to phone
select api.request_login_code('+15551234567');

-- Verify (from client after receiving code)
select api.verify_login_code('user@example.com', '123456');
```

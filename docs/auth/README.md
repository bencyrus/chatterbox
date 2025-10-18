## Auth Overview

Status: current
Last verified: 2025-10-18

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Centralize authentication options and point to focused pages with data models and flows.

### Options

- Basic (password): sign up and login via password. Returns `{ access_token, refresh_token }`.
- OTP login (passwordless): request 6-digit code via email/SMS; verify code.
- Magic token (passwordless): request a single-use link via email/SMS; clicking logs in.

### See also

- OTP: [`./otp-login.md`](./otp-login.md)
- Magic token: [`./magic-link-login.md`](./magic-link-login.md)
- Access token refresh: [`./auth-refresh.md`](./auth-refresh.md)

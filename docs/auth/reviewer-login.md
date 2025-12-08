## Reviewer Login (Instant Auth for App Review)

Status: current
Last verified: 2025-12-08

← Back to [`docs/auth/README.md`](./README.md)

### Why this exists

- Provide a streamlined authentication flow for the app review account (`reviewer@chatterboxtalk.com`) that bypasses email sending and returns tokens immediately.
- Simplifies app store review process by removing dependency on external email services during review.

### Role in the system

- Special-case authentication endpoint that validates the reviewer account and returns tokens directly.
- Keeps the app logic clean by using a separate endpoint rather than adding conditional logic to the magic link flow.

### How it works

#### Backend (PostgreSQL)

1. **Configuration**: The reviewer email is stored in `internal.config('reviewer_login')` via the `1756075500_reviewer_login.sql` migration.
2. **Validation**: The `api.reviewer_login(identifier text)` function:
   - Validates that the identifier is a properly formatted email
   - Checks that the identifier matches the configured reviewer email (case-insensitive)
   - Gets or creates the reviewer account
   - Creates access and refresh tokens immediately
   - Records the login event
   - Returns tokens directly without sending any email
3. **Security**: The function uses the same account creation and token generation logic as normal logins, ensuring consistency.

#### iOS App

1. **Configuration**: The reviewer email is loaded from `Info.plist` (`REVIEWER_EMAIL` key) into the `Environment` struct.
2. **Detection**: When `requestMagicLink` is called:
   - `AuthRepository` checks if the identifier matches the reviewer email (case-insensitive)
   - If it matches, calls `/rpc/reviewer_login` instead of `/rpc/request_magic_link`
   - If it doesn't match, uses the normal magic link flow
3. **Flow**: For the reviewer account:
   - User enters `reviewer@chatterboxtalk.com`
   - App calls reviewer login endpoint
   - Tokens are returned immediately
   - Session is established without any cooldown
   - User is logged in instantly

### Operations

#### Setup (Backend)

Add the reviewer email to `secrets/.env.postgres`:

```bash
REVIEWER_EMAIL=reviewer@chatterboxtalk.com
```

Then apply the migration:

```bash
./postgres/scripts/apply_migrations.sh --only 1756075500_reviewer_login
```

Or apply all pending migrations:

```bash
./postgres/scripts/apply_migrations.sh
```

#### Setup (iOS)

The reviewer email is already configured in `Chatterbox-Info.plist` as:

```xml
<key>REVIEWER_EMAIL</key>
<string>reviewer@chatterboxtalk.com</string>
```

To change it for different environments, update the value in the Info.plist or use build settings to override it.

#### Testing

1. **Normal accounts**: Use any other email/phone to verify the magic link flow still works normally
2. **Reviewer account**: Use `reviewer@chatterboxtalk.com` to verify instant login without email
3. **Case insensitivity**: Try `REVIEWER@chatterboxtalk.com` to verify case-insensitive matching

### Implementation details

#### Key files

Backend:
- Migration: [`postgres/migrations/1756075500_reviewer_login.sql`](../../postgres/migrations/1756075500_reviewer_login.sql)
- Helper: `auth.reviewer_email()` to get configured reviewer email
- Endpoint: `api.reviewer_login(text)` for instant authentication

iOS:
- Endpoint: [`Core/Networking/Endpoints.swift`](../../../chatterbox-apple/Core/Networking/Endpoints.swift) - `AuthEndpoints.ReviewerLogin`
- Repository: [`Features/Auth/Repositories/AuthRepository.swift`](../../../chatterbox-apple/Features/Auth/Repositories/AuthRepository.swift)
- Use case: [`Features/Auth/UseCases/AuthUseCases.swift`](../../../chatterbox-apple/Features/Auth/UseCases/AuthUseCases.swift)
- Config: [`Core/Config/Environment.swift`](../../../chatterbox-apple/Core/Config/Environment.swift)

#### Security considerations

- The reviewer account follows the same security model as normal accounts
- Token expiry and refresh work identically
- No sensitive information is logged
- The reviewer email is compared case-insensitively to prevent bypass via case variation
- Only email identifiers are allowed for reviewer login (not phone numbers)

### See also

- Magic link login: [`./magic-link-login.md`](./magic-link-login.md)
- Auth overview: [`./README.md`](./README.md)
- Migrations: [`../postgres/migrations-and-secrets.md`](../postgres/migrations-and-secrets.md)


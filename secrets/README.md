# Secrets Configuration

This directory contains environment variable files for each service. These files are **not** committed to git.

## Required Files

### `.env.postgres`

Used by the PostgreSQL container and migration scripts.

**Required variables:**
```bash
# Database
POSTGRES_DB=chatterbox
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password_here
PGTZ=UTC

# Authentication
AUTHENTICATOR_PASSWORD=your_authenticator_password_here
JWT_SECRET=your_jwt_secret_here

# Email Configuration
HELLO_EMAIL=hello@chatterboxtalk.com
NOREPLY_EMAIL=noreply@chatterboxtalk.com

# Reviewer Account (for app store review)
REVIEWER_EMAIL=reviewer@chatterboxtalk.com
```

### Other Service Files

Create these as needed for your deployment:
- `.env.postgrest` - PostgREST configuration
- `.env.gateway` - Gateway service configuration
- `.env.worker` - Worker service configuration
- `.env.files` - Files service configuration
- `.env.caddy` - Caddy web server configuration
- `.env.datadog` - Datadog agent configuration

## Security Notes

- **Never commit these files to git**
- Use strong, randomly generated passwords and secrets
- Rotate secrets regularly in production
- Keep development and production secrets separate
- Use environment-specific values where appropriate

## Setup

1. Copy this template for each required service
2. Fill in the actual values (never use defaults in production)
3. Ensure the files are readable only by necessary users (`chmod 600`)
4. For production, consider using a secrets management service

## Reviewer Account

The `REVIEWER_EMAIL` variable configures a special account that can log in instantly without email verification. This is used for app store review purposes.

- The account bypasses email sending
- Tokens are returned immediately
- Use only for legitimate app review purposes
- In production, use a real monitored email address

See: [`docs/auth/reviewer-login.md`](../docs/auth/reviewer-login.md)


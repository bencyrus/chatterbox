## Deploy and Operations

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Provide a clear overview of how to run the system locally and in simple deployments, with links to topology and operational scripts.

### Role in the system

- Documentation hub for compose topology, migrations, secrets, and backups/restore procedures.

### Start here

- Runtime topology (Docker Compose): [`./runtime-topology.md`](./runtime-topology.md)
- Migrations and secrets: [`../postgres/migrations-and-secrets.md`](../postgres/migrations-and-secrets.md)
- Backups and restore: [`./backups-restore.md`](./backups-restore.md)

### Operations

- Service env files are in `secrets/.env.*` and are consumed by compose and scripts.
- Ensure JWT secret and PostgREST role settings match the values seeded by migrations.

### See also

- Docs index: [`../README.md`](../README.md)

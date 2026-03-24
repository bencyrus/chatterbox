## Grafana Cloud Setup

Status: current
Last verified: 2026-03-24

← Back to [`README.md`](README.md)

### Why this exists

- Ship all container logs to Grafana Cloud Loki for centralized querying and alerting.
- Query Postgres directly from Grafana Cloud for business dashboards without exposing the database to the internet.

### Components

Two containers handle observability, both defined in [`docker-compose.yaml`](../../docker-compose.yaml):

| Container | Image | Purpose |
|-----------|-------|---------|
| `alloy` | `grafana/alloy:latest` | Collects Docker container logs and ships them to Grafana Cloud Loki |
| `pdc-agent` | `grafana/pdc-agent:latest` | SSH tunnel allowing Grafana Cloud to query private Postgres |

### Logs: Grafana Alloy

Alloy auto-discovers all Docker containers via the Docker socket, tails their stdout/stderr, and pushes logs to Grafana Cloud Loki. No per-service labels or configuration needed — every container is collected automatically.

#### How it works

1. `discovery.docker` discovers containers via `/var/run/docker.sock`.
2. `discovery.relabel` extracts the container name as a `container` label.
3. `loki.source.docker` tails stdout/stderr from discovered containers.
4. `loki.process` adds static labels (`env=prod`, `job=chatterbox`).
5. `loki.write` pushes logs to Grafana Cloud Loki with basic auth.

Source: [`alloy/config.alloy`](../../alloy/config.alloy)

#### Compose service

```yaml
alloy:
  image: grafana/alloy:latest
  container_name: alloy
  restart: unless-stopped
  env_file:
    - ./secrets/.env.alloy
  volumes:
    - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  ports:
    - "12345:12345"
  command: run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy
```

Alloy runs unconditionally (no Compose profile) — it starts with every `docker compose up`.

#### Secrets

File: `secrets/.env.alloy` (template: [`secrets/.env.alloy.example`](../../secrets/.env.alloy.example))

| Variable | Purpose |
|----------|---------|
| `GRAFANA_CLOUD_LOKI_URL` | Loki push endpoint (e.g. `https://logs-prod-018.grafana.net/loki/api/v1/push`) |
| `GRAFANA_CLOUD_LOKI_USERNAME` | Numeric user ID from Grafana Cloud Loki details |
| `GRAFANA_CLOUD_LOKI_PASSWORD` | API token with `logs:write` scope |

The API token must have **write** scope. Create it via **Grafana Cloud > Access Policies** — the pre-made token on the Loki details page is read-only and will not work for pushing logs.

#### Querying logs

In Grafana Cloud, go to **Explore** and select the Loki data source. Useful queries:

- `{job="chatterbox"}` — all containers
- `{container="gateway"}` — single service
- `{container="worker"} |= "error"` — worker errors

#### Alloy UI

Alloy exposes a web UI on port `12345` showing the pipeline graph and component health. Access it at `http://<server>:12345`.

### Postgres: Private Data Source Connect (PDC)

Grafana Cloud runs on Grafana's servers and cannot reach Postgres inside the Docker network. PDC solves this: the `pdc-agent` container initiates an **outbound** SSH tunnel to Grafana Cloud, which then routes database queries through it. No inbound ports need to be opened.

#### Compose service

```yaml
pdc-agent:
  image: grafana/pdc-agent:latest
  container_name: pdc-agent
  restart: unless-stopped
  env_file:
    - ./secrets/.env.pdc
  entrypoint: ["sh", "-c"]
  command:
    - "pdc -token $$GCLOUD_PDC_SIGNING_TOKEN -cluster $$GCLOUD_PDC_CLUSTER -gcloud-hosted-grafana-id $$GCLOUD_HOSTED_GRAFANA_ID"
  depends_on:
    postgres:
      condition: service_healthy
```

The `entrypoint` override is needed because Compose's `command` field does not interpolate variables from `env_file` — the shell expands them at runtime instead. `$$` escapes to a literal `$` so Compose passes the variable references through to the shell.

#### Secrets

File: `secrets/.env.pdc` (template: [`secrets/.env.pdc.example`](../../secrets/.env.pdc.example))

| Variable | Purpose |
|----------|---------|
| `GCLOUD_PDC_SIGNING_TOKEN` | PDC signing token from Grafana Cloud |
| `GCLOUD_PDC_CLUSTER` | PDC cluster (e.g. `prod-ca-east-0`) |
| `GCLOUD_HOSTED_GRAFANA_ID` | Hosted Grafana instance ID |

Generate these values in Grafana Cloud at **Connections > Private data source connect > Add new network**. The Docker command shown on that page contains all three values.

#### Database user

A read-only Postgres user `grafana_reader` is created by migration [`1756076400_grafana_reader_user.sql`](../../postgres/migrations/1756076400_grafana_reader_user.sql). It has `pg_read_all_data` — read access to all schemas and tables.

The password is set via `GRAFANA_READER_PASSWORD` in `secrets/.env.postgres`.

#### Grafana Cloud data source configuration

In Grafana Cloud, add a PostgreSQL data source with:

- **Host:** `postgres:5432`
- **Database:** the database name
- **User:** `grafana_reader`
- **Password:** value of `GRAFANA_READER_PASSWORD`
- **TLS/SSL Mode:** `disable`
- **Private data source connect:** enabled, select the PDC network

### Operations

#### Initial setup

1. Create `secrets/.env.alloy` from the example, fill in Loki credentials.
2. Create `secrets/.env.pdc` from the example, fill in PDC values from Grafana Cloud.
3. Set `GRAFANA_READER_PASSWORD` in `secrets/.env.postgres`.
4. Run the Grafana reader migration: `MIGRATIONS_ENV=prod make migrate ARGS="--only 1756076400_grafana_reader_user"`
5. Deploy: `make prod-up` (both `alloy` and `pdc-agent` start automatically).
6. Verify Alloy: check `docker logs alloy` for errors; visit `http://<server>:12345`.
7. Verify PDC: in Grafana Cloud, **Connections > Private data source connect** should show "1 agent connected."
8. Configure the PostgreSQL data source in Grafana Cloud and click **Save & test**.

#### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `405 Method Not Allowed` in alloy logs | Loki URL missing `/loki/api/v1/push` path | Add the full path to `GRAFANA_CLOUD_LOKI_URL` |
| `401 invalid scope requested` | API token has read-only scope | Create a new token with `logs:write` via **Access Policies** |
| PDC shows 0 agents | Env vars not interpolated in command | Ensure `entrypoint: ["sh", "-c"]` is set (see compose snippet above) |
| Postgres data source test fails | `grafana_reader` user not created or wrong password | Run the migration and verify `GRAFANA_READER_PASSWORD` matches |

### See also

- Overview: [`README.md`](README.md)
- Datadog setup (legacy): [`datadog.md`](datadog.md)
- Alloy config: [`alloy/config.alloy`](../../alloy/config.alloy)
- PDC secrets template: [`secrets/.env.pdc.example`](../../secrets/.env.pdc.example)
- Alloy secrets template: [`secrets/.env.alloy.example`](../../secrets/.env.alloy.example)
- Grafana reader migration: [`postgres/migrations/1756076400_grafana_reader_user.sql`](../../postgres/migrations/1756076400_grafana_reader_user.sql)

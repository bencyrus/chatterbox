## Datadog Setup (Legacy)

Status: current
Last verified: 2026-03-24

← Back to [`README.md`](README.md)

**This setup has been replaced by [Grafana Cloud](grafana-cloud.md).** Kept here for reference in case of rollback or comparison.

### How it worked

The Datadog agent ran as a Docker container under the `observability` Compose profile. It mounted the Docker socket and host paths to discover containers and tail their stdout.

Each service in `docker-compose.yaml` had a `com.datadoghq.ad.logs` label telling the agent which source and service name to assign:

```yaml
services:
  gateway:
    labels:
      - 'com.datadoghq.ad.logs=[{"source": "gateway", "service": "gateway"}]'
```

The agent container:

```yaml
datadog:
  image: gcr.io/datadoghq/agent:7
  container_name: dd-agent
  restart: unless-stopped
  profiles:
    - observability
  env_file:
    - ./secrets/.env.datadog
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - /proc/:/host/proc/:ro
    - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
    - /opt/datadog-agent/run:/opt/datadog-agent/run:rw
  pid: host
```

### Configuration

Secrets lived in `secrets/.env.datadog`:

| Variable | Purpose |
|----------|---------|
| `DD_API_KEY` | Datadog API key |
| `DD_SITE` | Datadog region (e.g. `us5.datadoghq.com`) |
| `DD_LOGS_ENABLED` | Enable log collection (`true`) |
| `DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL` | Collect from all containers (`true`) |
| `DD_CONTAINER_EXCLUDE_LOGS` | Exclude the agent's own logs (`name:dd-agent`) |
| `DD_DOCKER_LABELS_AS_TAGS` | Use Docker labels as Datadog tags (`true`) |
| `DD_PROCESS_AGENT_ENABLED` | Enable process monitoring (`true`) |

### Why it was replaced

- Cost: Datadog pricing scales with log volume and hosts; Grafana Cloud's free tier covers the current scale.
- Postgres querying: Grafana Cloud has a built-in PostgreSQL data source for business dashboards alongside logs. Datadog required separate integrations or Metabase for this.
- Consistency: consolidating logs and database dashboards in one platform simplifies operations.

### See also

- Current setup: [`grafana-cloud.md`](grafana-cloud.md)
- Overview: [`README.md`](README.md)

-- Read-only Postgres user for Grafana Cloud dashboards and queries.
-- Connects via PDC (Private Data Source Connect) tunnel.
create user grafana_reader with login password '{secrets.grafana_reader_password}';

grant pg_read_all_data to grafana_reader;

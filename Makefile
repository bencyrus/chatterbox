.PHONY: up fresh migrate local-up local-up-detached local-fresh local-fresh-detached prod-up prod-up-detached prod-fresh prod-fresh-detached prod-up-with-observability

LOCAL_COMPOSE := docker compose --progress=plain -f docker-compose.local.yaml
PROD_COMPOSE := docker compose --progress=plain -f docker-compose.yaml

# up: local default – build and start full stack using existing data
up: local-up

# fresh: local default – drop containers/volumes, apply migrations, start stack
fresh: local-fresh

# migrate: apply all Postgres migrations with secrets substitution (requires MIGRATIONS_ENV)
# Usage: MIGRATIONS_ENV=local make migrate [ARGS="--only some_migration"]
migrate:
	@if [ -z "$$MIGRATIONS_ENV" ]; then \
	  echo "Error: MIGRATIONS_ENV is required (local|prod)"; \
	  exit 2; \
	fi
	MIGRATIONS_ENV=$$MIGRATIONS_ENV VERBOSE=1 ./postgres/scripts/apply_migrations.sh $(ARGS)

## Local targets (dev)

local-up:
	$(LOCAL_COMPOSE) up --build

local-up-detached:
	$(LOCAL_COMPOSE) up --build -d

local-fresh:
	$(LOCAL_COMPOSE) down -v --remove-orphans || true
	$(LOCAL_COMPOSE) up -d postgres
	@echo "Waiting for postgres to be ready (local)..."
	@until $(LOCAL_COMPOSE) exec -T postgres pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB >/dev/null 2>&1; do sleep 2; done
	MIGRATIONS_ENV=local VERBOSE=1 ./postgres/scripts/apply_migrations.sh && echo "✓ Migrations complete"
	@echo ""
	@echo "Starting full stack..."
	@echo ""
	$(LOCAL_COMPOSE) up --build

local-fresh-detached:
	$(LOCAL_COMPOSE) down -v --remove-orphans || true
	$(LOCAL_COMPOSE) up -d postgres
	@echo "Waiting for postgres to be ready (local)..."
	@until $(LOCAL_COMPOSE) exec -T postgres pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB >/dev/null 2>&1; do sleep 2; done
	MIGRATIONS_ENV=local VERBOSE=1 ./postgres/scripts/apply_migrations.sh && echo "✓ Migrations complete"
	@echo ""
	@echo "Starting full stack (detached)..."
	@echo ""
	$(LOCAL_COMPOSE) up --build -d

## Server targets (prod/staging)

prod-up:
	$(PROD_COMPOSE) up --build

prod-up-detached:
	$(PROD_COMPOSE) up --build -d

prod-fresh:
	$(PROD_COMPOSE) down -v --remove-orphans || true
	$(PROD_COMPOSE) up -d postgres
	@echo "Waiting for postgres to be ready (prod)..."
	@until $(PROD_COMPOSE) exec -T postgres pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB >/dev/null 2>&1; do sleep 2; done
	MIGRATIONS_ENV=prod VERBOSE=1 ./postgres/scripts/apply_migrations.sh
	@echo ""
	@echo "Migrations complete. Starting full stack..."
	@echo ""
	$(PROD_COMPOSE) up --build

prod-fresh-detached:
	$(PROD_COMPOSE) down -v --remove-orphans || true
	$(PROD_COMPOSE) up -d postgres
	@echo "Waiting for postgres to be ready (prod)..."
	@until $(PROD_COMPOSE) exec -T postgres pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB >/dev/null 2>&1; do sleep 2; done
	MIGRATIONS_ENV=prod VERBOSE=1 ./postgres/scripts/apply_migrations.sh
	@echo ""
	@echo "Migrations complete. Starting full stack (detached)..."
	@echo ""
	$(PROD_COMPOSE) up --build -d

prod-up-with-observability:
	COMPOSE_PROFILES=observability $(PROD_COMPOSE) up --build

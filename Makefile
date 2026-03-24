.PHONY: up fresh migrate local-up local-up-detached local-fresh local-fresh-detached local-fresh-no-migrations download-db-latest download-db-backup local-restore-db-latest local-restore-db-backup prod-up prod-up-detached prod-fresh prod-fresh-detached prod-fresh-no-migrations prod-restore-db-latest prod-restore-db-backup prod-up-with-observability down down-volumes local-down local-down-volumes

LOCAL_COMPOSE := docker compose --progress=plain -f docker-compose.local.yaml
PROD_COMPOSE := docker compose --progress=plain -f docker-compose.yaml
GCS_BUCKET := chatterbox-bucket-main
GCS_BACKUP_PREFIX := backups/postgres

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

##
## BACKUP/RESTORE WORKFLOW (two-step process):
##   1. Download DB from GCS:  make download-db-{latest|backup}
##   2. Restore DB:            make {local|prod}-restore-db-{latest|backup}
##
## Examples:
##   - Restore latest to local:    make download-db-latest && make local-restore-db-latest
##   - Restore specific to local:  make download-db-backup BACKUP=cluster_xyz.sql.gz && make local-restore-db-backup BACKUP=cluster_xyz.sql.gz
##   - Disaster recovery (prod):   make download-db-latest && make prod-restore-db-latest
##   - List available backups:     gsutil ls gs://chatterbox-bucket-main/backups/postgres/
##

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

local-fresh-no-migrations:
	$(LOCAL_COMPOSE) down -v --remove-orphans || true
	@echo "Starting full stack with clean database (no migrations)..."
	@echo ""
	$(LOCAL_COMPOSE) up --build

## Backup download operations (from prod GCS to local disk)

download-db-latest:
	@echo "Downloading latest DB backup from GCS..."
	@LATEST=$$(gsutil ls gs://$(GCS_BUCKET)/$(GCS_BACKUP_PREFIX)/ | sort | tail -1 | xargs basename) && \
	  echo "Found latest backup: $$LATEST" && \
	  gsutil cp gs://$(GCS_BUCKET)/$(GCS_BACKUP_PREFIX)/$$LATEST ./postgres/backups/ && \
	  echo "" && \
	  echo "✓ Downloaded latest backup: $$LATEST"

download-db-backup:
	@if [ -z "$(BACKUP)" ]; then \
	  echo "Error: BACKUP is required"; \
	  echo "Usage: make download-db-backup BACKUP=cluster_20260208T060000Z.sql.gz"; \
	  exit 1; \
	fi
	@echo "Downloading DB backup $(BACKUP) from GCS..."
	@gsutil cp gs://$(GCS_BUCKET)/$(GCS_BACKUP_PREFIX)/$(BACKUP) ./postgres/backups/
	@echo "✓ Downloaded: $(BACKUP)"

## Local restore operations (restore downloaded backups to local DB)

local-restore-db-latest:
	@LATEST=$$(ls -t ./postgres/backups/cluster_*.sql.gz 2>/dev/null | head -1 | xargs basename) && \
	  if [ -z "$$LATEST" ]; then \
	    echo "Error: No DB backup files found in ./postgres/backups/"; \
	    echo "Run 'make download-db-latest' first"; \
	    exit 1; \
	  fi && \
	  echo "Restoring latest DB backup to local: $$LATEST" && \
	  ./postgres/run-db-restore.sh $$LATEST && \
	  echo "" && \
	  echo "✓ Restored to local: $$LATEST"

local-restore-db-backup:
	@if [ -z "$(BACKUP)" ]; then \
	  echo "Error: BACKUP is required"; \
	  echo "Usage: make local-restore-db-backup BACKUP=cluster_20260208T060000Z.sql.gz"; \
	  exit 1; \
	fi
	@if [ ! -f ./postgres/backups/$(BACKUP) ]; then \
	  echo "Error: DB backup file not found: ./postgres/backups/$(BACKUP)"; \
	  echo "Run 'make download-db-backup BACKUP=$(BACKUP)' first"; \
	  exit 1; \
	fi
	@echo "Restoring DB backup to local: $(BACKUP)"
	@./postgres/run-db-restore.sh $(BACKUP)
	@echo ""
	@echo "✓ Restored to local: $(BACKUP)"

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

prod-fresh-no-migrations:
	$(PROD_COMPOSE) down -v --remove-orphans || true
	@echo "Starting full prod stack with clean database (no migrations)..."
	@echo ""
	$(PROD_COMPOSE) up --build -d

## Prod restore operations (restore downloaded backups to prod DB)

prod-restore-db-latest:
	@LATEST=$$(ls -t ./postgres/backups/cluster_*.sql.gz 2>/dev/null | head -1 | xargs basename) && \
	  if [ -z "$$LATEST" ]; then \
	    echo "Error: No DB backup files found in ./postgres/backups/"; \
	    echo "Run 'make download-db-latest' first"; \
	    exit 1; \
	  fi && \
	  echo "Restoring latest DB backup to prod: $$LATEST" && \
	  ./postgres/run-db-restore.sh $$LATEST && \
	  echo "" && \
	  echo "✓ Restored to prod: $$LATEST"

prod-restore-db-backup:
	@if [ -z "$(BACKUP)" ]; then \
	  echo "Error: BACKUP is required"; \
	  echo "Usage: make prod-restore-db-backup BACKUP=cluster_20260208T060000Z.sql.gz"; \
	  exit 1; \
	fi
	@if [ ! -f ./postgres/backups/$(BACKUP) ]; then \
	  echo "Error: DB backup file not found: ./postgres/backups/$(BACKUP)"; \
	  echo "Run 'make download-db-backup BACKUP=$(BACKUP)' first"; \
	  exit 1; \
	fi
	@echo "Restoring DB backup to prod: $(BACKUP)"
	@./postgres/run-db-restore.sh $(BACKUP)
	@echo ""
	@echo "✓ Restored to prod: $(BACKUP)"

## Stop targets

down:
	$(PROD_COMPOSE) down

down-volumes:
	$(PROD_COMPOSE) down -v

local-down:
	$(LOCAL_COMPOSE) down

local-down-volumes:
	$(LOCAL_COMPOSE) down -v

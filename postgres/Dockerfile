# Purpose: Build a Postgres image that loads initialization SQL from this repo on first boot

FROM postgres:18-alpine

# Install pg_isready and timezone data (usually present, but ensure minimal tools)
RUN apk add --no-cache tzdata bash

# Provide a dedicated backups directory inside the container; mount a volume there in compose
VOLUME ["/backups"]

# Copy backup utility into container path and make it executable
COPY ./postgres/scripts/pg-backup.sh /usr/local/bin/pg-backup
RUN chmod +x /usr/local/bin/pg-backup

# Default exposes 5432 from base image
EXPOSE 5432

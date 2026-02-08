package config

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	// Postgres connection
	PGHost     string
	PGPort     string
	PGUser     string
	PGPassword string

	// GCS upload
	GCSBackupBucket             string
	GCSBackupPrefix             string
	GCSServiceAccountEmail      string
	GCSServiceAccountPrivateKey string

	// Schedule (cron expression, UTC) e.g. "0 2,14 * * *" for 2am and 2pm UTC
	BackupSchedule string

	// Local retention
	LocalRetentionDays int
}

const (
	EnvPGHost     = "PGHOST"
	EnvPGPort     = "PGPORT"
	EnvPGUser     = "PGUSER"
	EnvPGPassword = "PGPASSWORD"

	EnvGCSBackupBucket             = "GCS_BACKUP_BUCKET"
	EnvGCSBackupPrefix             = "GCS_BACKUP_PREFIX"
	EnvGCSServiceAccountEmail      = "GCS_SERVICE_ACCOUNT_EMAIL"
	EnvGCSServiceAccountPrivateKey = "GCS_SERVICE_ACCOUNT_PRIVATE_KEY"

	EnvBackupSchedule     = "BACKUP_SCHEDULE"
	EnvLocalRetentionDays = "LOCAL_RETENTION_DAYS"
)

func Load() Config {
	pgHost := strings.TrimSpace(os.Getenv(EnvPGHost))
	if pgHost == "" {
		panic("PGHOST is required for db-backup service")
	}

	pgPort := strings.TrimSpace(os.Getenv(EnvPGPort))
	if pgPort == "" {
		pgPort = "5432"
	}

	pgUser := strings.TrimSpace(os.Getenv(EnvPGUser))
	if pgUser == "" {
		panic("PGUSER is required for db-backup service")
	}

	pgPassword := strings.TrimSpace(os.Getenv(EnvPGPassword))
	if pgPassword == "" {
		panic("PGPASSWORD is required for db-backup service")
	}

	bucket := strings.TrimSpace(os.Getenv(EnvGCSBackupBucket))
	if bucket == "" {
		panic("GCS_BACKUP_BUCKET is required for db-backup service")
	}

	prefix := strings.TrimSpace(os.Getenv(EnvGCSBackupPrefix))
	if prefix == "" {
		prefix = "backups/postgres"
	}

	serviceAccountEmail := strings.TrimSpace(os.Getenv(EnvGCSServiceAccountEmail))
	if serviceAccountEmail == "" {
		panic("GCS_SERVICE_ACCOUNT_EMAIL is required for db-backup service")
	}

	privateKey := strings.TrimSpace(os.Getenv(EnvGCSServiceAccountPrivateKey))
	if privateKey == "" {
		panic("GCS_SERVICE_ACCOUNT_PRIVATE_KEY is required for db-backup service")
	}

	schedule := strings.TrimSpace(os.Getenv(EnvBackupSchedule))
	if schedule == "" {
		schedule = "0 2,14 * * *"
	}

	retentionStr := strings.TrimSpace(os.Getenv(EnvLocalRetentionDays))
	if retentionStr == "" {
		retentionStr = "3"
	}
	retentionDays, err := strconv.Atoi(retentionStr)
	if err != nil || retentionDays < 0 {
		panic("LOCAL_RETENTION_DAYS must be a non-negative integer")
	}

	return Config{
		PGHost:                      pgHost,
		PGPort:                      pgPort,
		PGUser:                      pgUser,
		PGPassword:                  pgPassword,
		GCSBackupBucket:             bucket,
		GCSBackupPrefix:             prefix,
		GCSServiceAccountEmail:      serviceAccountEmail,
		GCSServiceAccountPrivateKey: privateKey,
		BackupSchedule:              schedule,
		LocalRetentionDays:          retentionDays,
	}
}

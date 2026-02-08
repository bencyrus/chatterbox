package config

import (
	"fmt"
	"net/url"
	"os"
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
}

const (
	EnvDatabaseURL = "DATABASE_URL"

	EnvGCSBackupBucket             = "GCS_BACKUP_BUCKET"
	EnvGCSBackupPrefix             = "GCS_BACKUP_PREFIX"
	EnvGCSServiceAccountEmail      = "GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_EMAIL"
	EnvGCSServiceAccountPrivateKey = "GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_PRIVATE_KEY"

	EnvBackupSchedule = "BACKUP_SCHEDULE"
)

func Load() Config {
	// Parse DATABASE_URL (like worker/files services)
	dbURL := strings.TrimSpace(os.Getenv(EnvDatabaseURL))
	if dbURL == "" {
		panic("DATABASE_URL is required for db-backup service")
	}

	parsed, err := url.Parse(dbURL)
	if err != nil {
		panic(fmt.Sprintf("failed to parse DATABASE_URL: %v", err))
	}

	pgHost := parsed.Hostname()
	pgPort := parsed.Port()
	if pgPort == "" {
		pgPort = "5432"
	}

	pgUser := parsed.User.Username()
	pgPassword, _ := parsed.User.Password()

	if pgHost == "" || pgUser == "" || pgPassword == "" {
		panic("DATABASE_URL must include host, user, and password")
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
		panic("GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_EMAIL is required for db-backup service")
	}

	privateKey := strings.TrimSpace(os.Getenv(EnvGCSServiceAccountPrivateKey))
	if privateKey == "" {
		panic("GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_PRIVATE_KEY is required for db-backup service")
	}

	schedule := strings.TrimSpace(os.Getenv(EnvBackupSchedule))
	if schedule == "" {
		schedule = "0 2,14 * * *"
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
	}
}

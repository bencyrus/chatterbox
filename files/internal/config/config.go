package config

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port string

	// Database
	DatabaseURL string

	// GCS signing
	GCSSigningEmail        string
	GCSSigningPrivateKey   string
	GCSBucket              string
	GCSSignedURLTTLSeconds int

	// High-level environment mode: e.g. "local" or "prod".
	// We only talk to the GCS emulator when this is explicitly "local".
	Environment string

	// Optional: base URL of a GCS-compatible emulator for local development.
	// When set, signed URLs will have their host/scheme rewritten to point
	// at this emulator instead of storage.googleapis.com.
	GCSEmulatorURL string

	// Internal API key used to authenticate gateway calls
	FileServiceAPIKey string
}

const (
	Port           = "PORT"
	EnvDatabaseURL = "DATABASE_URL"

	// GCS service account credentials used for signing URLs
	EnvGCSSigningEmail      = "GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_EMAIL"
	EnvGCSSigningPrivateKey = "GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_PRIVATE_KEY"

	EnvGCSBucket       = "GCS_CHATTERBOX_BUCKET"
	EnvGCSSignedURLTTL = "GCS_CHATTERBOX_SIGNED_URL_TTL_SECONDS"

	EnvFileServiceAPIKey = "FILE_SERVICE_API_KEY"

	EnvEnvironment    = "FILES_ENVIRONMENT"
	EnvGCSEmulatorURL = "GCS_EMULATOR_URL"
)

func Load() Config {
	port := strings.TrimSpace(os.Getenv(Port))
	if port == "" {
		port = "8080"
	}

	dbURL := strings.TrimSpace(os.Getenv(EnvDatabaseURL))
	if dbURL == "" {
		panic("DATABASE_URL is required for files service")
	}

	signingEmail := strings.TrimSpace(os.Getenv(EnvGCSSigningEmail))
	if signingEmail == "" {
		panic("GCS_SIGNING_EMAIL is required for files service")
	}

	privateKey := strings.TrimSpace(os.Getenv(EnvGCSSigningPrivateKey))
	if privateKey == "" {
		panic("GCS_SIGNING_PRIVATE_KEY is required for files service")
	}

	bucket := strings.TrimSpace(os.Getenv(EnvGCSBucket))
	if bucket == "" {
		panic("GCS_BUCKET is required for files service")
	}

	ttlStr := strings.TrimSpace(os.Getenv(EnvGCSSignedURLTTL))
	if ttlStr == "" {
		ttlStr = "900"
	}
	ttlSeconds, err := strconv.Atoi(ttlStr)
	if err != nil || ttlSeconds <= 0 {
		panic("GCS_SIGNED_URL_TTL_SECONDS must be a positive integer")
	}

	apiKey := strings.TrimSpace(os.Getenv(EnvFileServiceAPIKey))
	if apiKey == "" {
		panic("FILE_SERVICE_API_KEY is required for files service")
	}

	environment := strings.TrimSpace(os.Getenv(EnvEnvironment))
	if environment == "" {
		environment = "prod"
	}

	emulatorURL := strings.TrimSpace(os.Getenv(EnvGCSEmulatorURL))

	return Config{
		Port:                   port,
		DatabaseURL:            dbURL,
		GCSSigningEmail:        signingEmail,
		GCSSigningPrivateKey:   privateKey,
		GCSBucket:              bucket,
		GCSSignedURLTTLSeconds: ttlSeconds,
		FileServiceAPIKey:      apiKey,
		Environment:            environment,
		GCSEmulatorURL:         emulatorURL,
	}
}

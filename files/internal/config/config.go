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

	return Config{
		Port:                   port,
		DatabaseURL:            dbURL,
		GCSSigningEmail:        signingEmail,
		GCSSigningPrivateKey:   privateKey,
		GCSBucket:              bucket,
		GCSSignedURLTTLSeconds: ttlSeconds,
		FileServiceAPIKey:      apiKey,
	}
}

package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	// Database
	DatabaseURL string

	// Services
	ResendAPIKey      string
	FileServiceURL    string
	FileServiceAPIKey string
	ElevenLabsAPIKey  string

	// Worker settings
	PollInterval time.Duration
	MaxIdleTime  time.Duration
	Concurrency  int

	// Logging
	LogLevel string
}

func Load() Config {
	cfg := Config{
		DatabaseURL:       getEnv("DATABASE_URL", ""),
		ResendAPIKey:      getEnv("RESEND_API_KEY", ""),
		FileServiceURL:    getEnv("FILE_SERVICE_URL", ""),
		FileServiceAPIKey: getEnv("FILE_SERVICE_API_KEY", ""),
		ElevenLabsAPIKey:  getEnv("ELEVENLABS_API_KEY", ""),
		LogLevel:          getEnv("LOG_LEVEL", "info"),
	}

	// Parse durations
	pollIntervalSeconds, err := strconv.Atoi(getEnv("WORKER_POLL_INTERVAL_SECONDS", "5"))
	if err != nil {
		panic(fmt.Sprintf("invalid WORKER_POLL_INTERVAL_SECONDS: %v", err))
	}
	cfg.PollInterval = time.Duration(pollIntervalSeconds) * time.Second

	maxIdleSeconds, err := strconv.Atoi(getEnv("WORKER_MAX_IDLE_TIME_SECONDS", "30"))
	if err != nil {
		panic(fmt.Sprintf("invalid WORKER_MAX_IDLE_TIME_SECONDS: %v", err))
	}
	cfg.MaxIdleTime = time.Duration(maxIdleSeconds) * time.Second

	// Concurrency
	concurrency, err := strconv.Atoi(getEnv("WORKER_CONCURRENCY", "2"))
	if err != nil || concurrency < 1 {
		panic(fmt.Sprintf("invalid WORKER_CONCURRENCY: %v", err))
	}
	cfg.Concurrency = concurrency

	// Validate required fields
	if cfg.DatabaseURL == "" {
		panic("DATABASE_URL is required")
	}

	if cfg.FileServiceURL == "" {
		panic("FILE_SERVICE_URL is required")
	}

	if cfg.FileServiceAPIKey == "" {
		panic("FILE_SERVICE_API_KEY is required")
	}

	return cfg
}

func getEnv(key, defaultValue string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return defaultValue
	}
	return value
}

package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port string
	// PostgREST
	PostgRESTURL            string
	JWTSecret               string
	RefreshTokensPath       string
	RefreshThresholdSeconds int
	// Auth headers
	RefreshTokenHeaderIn     string
	NewAccessTokenHeaderOut  string
	NewRefreshTokenHeaderOut string
	// File service
	FileServiceURL          string
	FileSignedURLPath       string
	FilesFieldName          string
	ProcessedFilesFieldName string
	FileServiceAPIKey       string
	// HTTP client
	HTTPClientTimeoutSeconds int
}

// Environment variable names used by the gateway
const (
	EnvPort                    = "PORT"
	EnvPostgRESTURL            = "POSTGREST_URL"
	EnvJWTSecret               = "JWT_SECRET"
	EnvRefreshTokensPath       = "REFRESH_TOKENS_PATH"
	EnvRefreshThresholdSeconds = "REFRESH_THRESHOLD_SECONDS"
	// Headers
	EnvRefreshTokenHeaderIn     = "REFRESH_TOKEN_HEADER_IN"
	EnvNewAccessTokenHeaderOut  = "NEW_ACCESS_TOKEN_HEADER_OUT"
	EnvNewRefreshTokenHeaderOut = "NEW_REFRESH_TOKEN_HEADER_OUT"
	// Files
	EnvFileServiceURL          = "FILE_SERVICE_URL"
	EnvFileSignedURLPath       = "FILE_SIGNED_URL_PATH"
	EnvFilesFieldName          = "FILES_FIELD_NAME"
	EnvProcessedFilesFieldName = "PROCESSED_FILES_FIELD_NAME"
	EnvFileServiceAPIKey       = "FILE_SERVICE_API_KEY"
	// HTTP
	EnvHTTPClientTimeoutSeconds = "HTTP_CLIENT_TIMEOUT_SECONDS"
)

// collectRequired reads the provided environment keys and returns a map of values
// alongside a slice of any missing keys (values that were empty/whitespace).
func collectRequired(keys []string) (map[string]string, []string) {
	missing := make([]string, 0)
	values := make(map[string]string, len(keys))
	for _, k := range keys {
		v := strings.TrimSpace(os.Getenv(k))
		if v == "" {
			missing = append(missing, k)
			continue
		}
		values[k] = v
	}
	return values, missing
}

// collectOptional reads optional env vars and applies defaults when empty/whitespace.
func collectOptional(defaults map[string]string) map[string]string {
	values := make(map[string]string, len(defaults))
	for k, def := range defaults {
		v := strings.TrimSpace(os.Getenv(k))
		if v == "" {
			v = def
		}
		values[k] = v
	}
	return values
}

func Load() Config {
	required := []string{
		EnvPostgRESTURL,
		EnvJWTSecret,
		EnvRefreshTokensPath,
		EnvRefreshThresholdSeconds,
		EnvFileServiceURL,
		EnvFileSignedURLPath,
		EnvFilesFieldName,
		EnvProcessedFilesFieldName,
		EnvFileServiceAPIKey,
	}
	requiredEnvVars, missingEnvVars := collectRequired(required)
	if len(missingEnvVars) > 0 {
		panic(fmt.Sprintf("missing required env vars: %s", strings.Join(missingEnvVars, ", ")))
	}

	threshold, err := strconv.Atoi(requiredEnvVars[EnvRefreshThresholdSeconds])
	if err != nil {
		panic("invalid REFRESH_THRESHOLD_SECONDS: must be integer seconds")
	}

	optionalEnvVars := collectOptional(map[string]string{
		EnvPort:                     "8080",
		EnvRefreshTokenHeaderIn:     "X-Refresh-Token",
		EnvNewAccessTokenHeaderOut:  "X-New-Access-Token",
		EnvNewRefreshTokenHeaderOut: "X-New-Refresh-Token",
		EnvHTTPClientTimeoutSeconds: "10",
	})

	httpTimeout, err := strconv.Atoi(optionalEnvVars[EnvHTTPClientTimeoutSeconds])
	if err != nil {
		panic("invalid HTTP_CLIENT_TIMEOUT_SECONDS: must be integer seconds")
	}

	return Config{
		Port:                     optionalEnvVars[EnvPort],
		PostgRESTURL:             requiredEnvVars[EnvPostgRESTURL],
		JWTSecret:                requiredEnvVars[EnvJWTSecret],
		RefreshTokensPath:        requiredEnvVars[EnvRefreshTokensPath],
		RefreshThresholdSeconds:  threshold,
		RefreshTokenHeaderIn:     optionalEnvVars[EnvRefreshTokenHeaderIn],
		NewAccessTokenHeaderOut:  optionalEnvVars[EnvNewAccessTokenHeaderOut],
		NewRefreshTokenHeaderOut: optionalEnvVars[EnvNewRefreshTokenHeaderOut],
		FileServiceURL:           requiredEnvVars[EnvFileServiceURL],
		FileSignedURLPath:        requiredEnvVars[EnvFileSignedURLPath],
		FilesFieldName:           requiredEnvVars[EnvFilesFieldName],
		ProcessedFilesFieldName:  requiredEnvVars[EnvProcessedFilesFieldName],
		FileServiceAPIKey:        requiredEnvVars[EnvFileServiceAPIKey],
		HTTPClientTimeoutSeconds: httpTimeout,
	}
}

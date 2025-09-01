package config

import (
	"os"
	"strings"
)

type Config struct {
	Port string
}

const (
	Port = "PORT"
)

func Load() Config {
	port := strings.TrimSpace(os.Getenv(Port))
	if port == "" {
		port = "8080"
	}
	return Config{Port: port}
}

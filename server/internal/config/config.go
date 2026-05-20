// Package config loads server configuration from the environment with sane
// local-development defaults.
package config

import (
	"os"
	"time"
)

// Config holds all runtime configuration.
type Config struct {
	HTTPAddr   string        // listen address, e.g. ":8080"
	PGDSN      string        // postgres connection string
	RedisAddr  string        // redis host:port
	SessionTTL time.Duration // guest session lifetime
	LogLevel   string        // zerolog level name
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// Load reads configuration from the process environment.
func Load() Config {
	ttl, err := time.ParseDuration(env("SESSION_TTL", "72h"))
	if err != nil {
		ttl = 72 * time.Hour
	}
	return Config{
		HTTPAddr:   env("HTTP_ADDR", ":8887"),
		PGDSN:      env("PG_DSN", "postgres://paidummy:paidummy@localhost:5440/paidummy?sslmode=disable"),
		RedisAddr:  env("REDIS_ADDR", "localhost:6390"),
		SessionTTL: ttl,
		LogLevel:   env("LOG_LEVEL", "debug"),
	}
}

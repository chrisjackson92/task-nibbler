package config

import (
	"fmt"
	"log"
	"os"
	"strconv"
)

// Config holds all application configuration loaded from environment variables.
// The application will panic on startup if any required variable is missing.
type Config struct {
	// Database
	DatabaseURL string

	// JWT
	JWTSecret        string
	JWTRefreshSecret string

	// AWS S3
	AWSAccessKeyID     string
	AWSSecretAccessKey string
	AWSS3Bucket        string
	AWSRegion          string

	// Resend Email
	ResendAPIKey    string
	ResendFromEmail string

	// Application
	AppBaseURL string
	Port       string
	AppEnv     string
	LogLevel   string

	// JWT token durations (in minutes)
	AccessTokenMinutes  int
	RefreshTokenDays    int
}

// Load reads all environment variables and returns a Config.
// Calls log.Fatal if any required variable is missing.
func Load() *Config {
	cfg := &Config{
		// Required
		DatabaseURL:        requireEnv("DATABASE_URL"),
		JWTSecret:          requireEnv("JWT_SECRET"),
		JWTRefreshSecret:   requireEnv("JWT_REFRESH_SECRET"),
		AWSAccessKeyID:     requireEnv("AWS_ACCESS_KEY_ID"),
		AWSSecretAccessKey: requireEnv("AWS_SECRET_ACCESS_KEY"),
		AWSS3Bucket:        requireEnv("AWS_S3_BUCKET"),
		ResendAPIKey:       requireEnv("RESEND_API_KEY"),
		ResendFromEmail:    requireEnv("RESEND_FROM_EMAIL"),
		AppBaseURL:         requireEnv("APP_BASE_URL"),

		// Optional with defaults
		AWSRegion: getEnvDefault("AWS_REGION", "us-east-1"),
		Port:      getEnvDefault("PORT", "8080"),
		AppEnv:    getEnvDefault("APP_ENV", "development"),
		LogLevel:  getEnvDefault("LOG_LEVEL", "info"),

		// Token lifetimes
		AccessTokenMinutes: 15,
		RefreshTokenDays:   30,
	}

	return cfg
}

func requireEnv(key string) string {
	val := os.Getenv(key)
	if val == "" {
		log.Fatalf("FATAL: required environment variable %s is not set", key)
	}
	return val
}

func getEnvDefault(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvIntDefault(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
		fmt.Printf("WARNING: env var %s is not a valid integer, using default %d\n", key, defaultVal)
	}
	return defaultVal
}

// IsDevelopment returns true when running in local development mode.
func (c *Config) IsDevelopment() bool {
	return c.AppEnv == "development"
}

// IsProduction returns true when running in production mode.
func (c *Config) IsProduction() bool {
	return c.AppEnv == "production"
}

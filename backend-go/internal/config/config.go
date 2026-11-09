package config

import (
	"os"
	"strconv"
	"strings"
)

// Config holds runtime configuration parameters for the Tashil Cloud Run service.
type Config struct {
	Port              string
	ProjectID         string
	BigQueryDataset   string
	FirestoreDatabase string
	GeminiAPIKey      string
	GeminiModel       string
	GeminiTier2Model  string
	JWTSecret         string
	Environment       string
	UseMockServices   bool
}

// Load reads configuration from environment variables with sensible production defaults.
func Load() *Config {
	port := getEnv("PORT", "8080")
	projectID := getEnv("PROJECT_ID", "tashil-data-sharing")
	dataset := getEnv("BIGQUERY_DATASET", "tashil_analytics")
	firestoreDB := getEnv("FIRESTORE_DATABASE", "(default)")
	// Secret Manager / Cloud Run secret mounts often append a trailing newline.
	// Go's net/http rejects header values with \n (x-goog-api-key), which made
	// Gemini calls fail before any network I/O and surfaced as empty /run batches.
	geminiKey := strings.TrimSpace(getEnv("GEMINI_API_KEY", ""))
	geminiModel := strings.TrimSpace(getEnv("GEMINI_MODEL", "gemini-pro-latest"))
	geminiTier2Model := strings.TrimSpace(getEnv("GEMINI_TIER2_MODEL", "gemini-pro-latest"))
	if geminiModel == "" {
		geminiModel = "gemini-pro-latest"
	}
	if geminiTier2Model == "" {
		geminiTier2Model = "gemini-pro-latest"
	}
	jwtSecret := getEnv("JWT_SECRET", "tashil-enterprise-secret-key-adeco-2026")
	env := getEnv("ENVIRONMENT", "development")

	// Default to mock services only in local development unless USE_MOCK_SERVICES is explicitly configured
	useMock := true
	if val, ok := os.LookupEnv("USE_MOCK_SERVICES"); ok {
		parsed, err := strconv.ParseBool(val)
		if err == nil {
			useMock = parsed
		}
	} else if env == "production" {
		useMock = false
	}

	return &Config{
		Port:              port,
		ProjectID:         projectID,
		BigQueryDataset:   dataset,
		FirestoreDatabase: firestoreDB,
		GeminiAPIKey:      geminiKey,
		GeminiModel:       geminiModel,
		GeminiTier2Model:  geminiTier2Model,
		JWTSecret:         jwtSecret,
		Environment:       env,
		UseMockServices:   useMock,
	}
}

func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return defaultVal
}

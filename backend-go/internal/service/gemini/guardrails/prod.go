package guardrails

import (
	"fmt"
	"os"
	"strings"
)

// ErrMockSamplesInProduction is returned when inventing fixed sample records would
// be required while ENVIRONMENT=production.
var ErrMockSamplesInProduction = fmt.Errorf("gemini analysis unavailable: refusing mock sample records in production")

// IsProduction reports whether ENVIRONMENT is production (case-insensitive).
func IsProduction() bool {
	return strings.EqualFold(strings.TrimSpace(os.Getenv("ENVIRONMENT")), "production")
}

// RefuseMockInProduction returns ErrMockSamplesInProduction when running in production.
func RefuseMockInProduction() error {
	if IsProduction() {
		return ErrMockSamplesInProduction
	}
	return nil
}

// AssertNoMockMappingSource rejects payloads that claim mapping_source=mock in production.
func AssertNoMockMappingSource(mappingSource string) error {
	if !IsProduction() {
		return nil
	}
	if strings.EqualFold(strings.TrimSpace(mappingSource), "mock") {
		return ErrMockSamplesInProduction
	}
	return nil
}

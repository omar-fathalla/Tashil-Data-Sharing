package config

import (
	"errors"
	"strings"
)

// ErrDemoTokensInProduction: ALLOW_DEMO_TOKENS=true makes any token-less request a vendor admin of the
// tenant named in X-Tenant-ID, so production must refuse to start with it.
var ErrDemoTokensInProduction = errors.New("refusing to start: ALLOW_DEMO_TOKENS=true is not allowed when ENVIRONMENT=production")

// DemoTokensAllowed parses ALLOW_DEMO_TOKENS ("true" only) and fails when it is on in production.
func DemoTokensAllowed(environment, allowDemoTokens string) (bool, error) {
	on := strings.TrimSpace(allowDemoTokens) == "true"
	if on && strings.EqualFold(strings.TrimSpace(environment), "production") {
		return false, ErrDemoTokensInProduction
	}
	return on, nil
}

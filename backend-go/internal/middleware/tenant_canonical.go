package middleware

import "strings"

// CanonicalTenant returns the comparison form of a tenant id: trimmed, lower-cased, with ONE leading
// "tenant-" or "tenant_" prefix removed. Tokens carry "adeco" while the web app and the storage layers use
// "tenant-adeco"; both are the same tenant.
//
// Exactly one prefix is stripped on purpose: "tenant-tenant_x" canonicalises to "tenant_x", not "x", so a
// stacked prefix can never collapse onto a different tenant. The result is for COMPARISON only; never store
// or route by it (callers keep using the token's own value, see SameTenant).
func CanonicalTenant(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	if strings.HasPrefix(s, "tenant-") {
		return strings.TrimPrefix(s, "tenant-")
	}
	return strings.TrimPrefix(s, "tenant_")
}

// SameTenant reports whether two tenant ids name the same tenant under CanonicalTenant. Empty never matches.
func SameTenant(a, b string) bool {
	ca, cb := CanonicalTenant(a), CanonicalTenant(b)
	return ca != "" && ca == cb
}

// IsSystemTenant reports whether a token tenant is the cross-tenant "system"/"all" scope that may pick a
// tenant via the ?tenant= / X-Tenant-ID override. It accepts exactly the legacy spellings "system", "all",
// "tenant-system" and "tenant-all" (case-sensitive, untrimmed) so the override rule does not widen.
func IsSystemTenant(t string) bool {
	c := CanonicalTenant(t)
	if c != "system" && c != "all" {
		return false
	}
	return t == c || t == "tenant-"+c
}

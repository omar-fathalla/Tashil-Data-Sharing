package middleware

import (
	"context"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestCanonicalTenant(t *testing.T) {
	cases := map[string]string{
		"adeco":           "adeco",
		"tenant-adeco":    "adeco",
		"tenant_adeco":    "adeco",
		"  TENANT-Adeco ": "adeco",
		"tenant-tenant_x": "tenant_x", // only ONE prefix is stripped
		"tenant_tenant-x": "tenant-x",
		"tenant-":         "",
		"":                "",
		"system":          "system",
	}
	for in, want := range cases {
		if got := CanonicalTenant(in); got != want {
			t.Errorf("CanonicalTenant(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSameTenant(t *testing.T) {
	same := [][2]string{{"adeco", "tenant-adeco"}, {"tenant-adeco", "adeco"}, {"adeco", "tenant_adeco"}, {"Adeco", " adeco "}}
	for _, p := range same {
		if !SameTenant(p[0], p[1]) {
			t.Errorf("SameTenant(%q,%q) = false", p[0], p[1])
		}
	}
	diff := [][2]string{{"x", "tenant-tenant_x"}, {"x", "tenant_tenant-x"}, {"adeco", "tenant-other"}, {"", ""}, {"", "tenant-"}, {"adeco", "adeco2"}}
	for _, p := range diff {
		if SameTenant(p[0], p[1]) {
			t.Errorf("SameTenant(%q,%q) = true", p[0], p[1])
		}
	}
}

// legacySystemCheck is the inline rule IsSystemTenant replaced in the upload/archive handlers.
func legacySystemCheck(t string) bool {
	return t == "system" || t == "all" || t == "tenant-system" || t == "tenant-all"
}

func TestIsSystemTenantMatchesLegacyRule(t *testing.T) {
	for _, in := range []string{"system", "all", "tenant-system", "tenant-all", "System", "SYSTEM", " system", "system ",
		"tenant_system", "tenant_all", "Tenant-System", "tenant-tenant-system", "adeco", "tenant-adeco", "", "allx", "systemx"} {
		if got, want := IsSystemTenant(in), legacySystemCheck(in); got != want {
			t.Errorf("IsSystemTenant(%q) = %v, legacy %v", in, got, want)
		}
	}
}

func legacyAssert(user, target string) bool {
	return strings.TrimPrefix(strings.ToLower(user), "tenant-") == strings.TrimPrefix(strings.ToLower(target), "tenant-")
}

// AssertTenantMatch keeps its behaviour for every tenant spelling in use ("x", "tenant-x", any case).
func TestAssertTenantMatchUnchanged(t *testing.T) {
	ids := []string{"adeco", "tenant-adeco", "ADECO", "Tenant-Adeco", "other", "tenant-other", "system"}
	for _, u := range ids {
		for _, tg := range ids {
			ctx := context.WithValue(context.Background(), UserClaimsContextKey, &domain.UserClaims{TenantID: u, Role: domain.RoleVendorAdmin})
			if got, want := AssertTenantMatch(ctx, tg) == nil, legacyAssert(u, tg); got != want {
				t.Errorf("AssertTenantMatch(user=%q,target=%q) = %v, legacy %v", u, tg, got, want)
			}
		}
	}
	ctx := context.WithValue(context.Background(), UserClaimsContextKey, &domain.UserClaims{TenantID: "adeco", Role: domain.RoleSuperAdmin})
	if err := AssertTenantMatch(ctx, "tenant-other"); err != nil {
		t.Fatalf("super_admin must reach any tenant: %v", err)
	}
	if err := AssertTenantMatch(context.Background(), "adeco"); err != ErrNoTenantContext {
		t.Fatalf("missing claims: %v", err)
	}
}

// L2: an empty/blank claims tenant must never match a target that also canonicalizes to "" (e.g. "tenant-").
func TestAssertTenantMatchRejectsEmptyCanonical(t *testing.T) {
	for _, pair := range [][2]string{{"", "tenant-"}, {"tenant-", ""}, {"tenant-", "tenant-"}, {"", ""}} {
		ctx := context.WithValue(context.Background(), UserClaimsContextKey, &domain.UserClaims{TenantID: pair[0], Role: domain.RoleVendorAdmin})
		if err := AssertTenantMatch(ctx, pair[1]); err == nil {
			t.Fatalf("claims %q vs target %q: expected error, got nil", pair[0], pair[1])
		}
	}
	ctx := context.WithValue(context.Background(), UserClaimsContextKey, &domain.UserClaims{TenantID: "adeco", Role: domain.RoleVendorAdmin})
	if err := AssertTenantMatch(ctx, "tenant-adeco"); err != nil {
		t.Fatalf("adeco vs tenant-adeco: %v", err)
	}
}

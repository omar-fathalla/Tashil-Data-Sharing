package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func claimsThrough(t *testing.T, mw *AuthMiddleware, c domain.UserClaims, hdr map[string]string) (eff, write *domain.UserClaims) {
	t.Helper()
	tok, err := mw.GenerateToken(c, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/sell-in", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	mw.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		eff, _ = GetUserClaims(r.Context())
		write, _ = WriteClaims(r.Context())
	})).ServeHTTP(httptest.NewRecorder(), req)
	if eff == nil || write == nil {
		t.Fatal("no claims in context")
	}
	return eff, write
}

// A chain-A KAM sending X-Assigned-Chain: B (and a simulated role / region) keeps chain A: headers are
// ignored for anyone but a verified super_admin, so the chain-scoped queries never see chain-B rows.
func TestHeadersIgnoredForNonSuperAdmin(t *testing.T) {
	mw := NewAuthMiddleware("s", false)
	kam := domain.UserClaims{UserID: "k", TenantID: "tenant-adeco", Role: domain.RoleChainKAM, AssignedChain: "chain-a", AssignedRegion: "ALX"}
	eff, write := claimsThrough(t, mw, kam, map[string]string{"X-Assigned-Chain": "chain-b", "X-Simulated-Role": "super_admin", "X-Assigned-Region": "CAI"})
	if eff.AssignedChain != "chain-a" || eff.Role != domain.RoleChainKAM || eff.AssignedRegion != "ALX" {
		t.Fatalf("headers widened a KAM: %+v", eff)
	}
	if write.Role != domain.RoleChainKAM {
		t.Fatalf("write claims escalated: %+v", write)
	}
}

// A verified super_admin may preview another role/chain, but writes still use the super_admin role.
func TestSuperAdminHeadersOnlyChangeReadView(t *testing.T) {
	mw := NewAuthMiddleware("s", false)
	su := domain.UserClaims{UserID: "s", TenantID: "system", Role: domain.RoleSuperAdmin}
	eff, write := claimsThrough(t, mw, su, map[string]string{"X-Simulated-Role": "chain_kam", "X-Assigned-Chain": "chain-b"})
	if eff.Role != domain.RoleChainKAM || eff.AssignedChain != "chain-b" {
		t.Fatalf("super_admin preview not applied: %+v", eff)
	}
	if write.Role != domain.RoleSuperAdmin {
		t.Fatalf("write claims must stay verified super_admin: %+v", write)
	}
}

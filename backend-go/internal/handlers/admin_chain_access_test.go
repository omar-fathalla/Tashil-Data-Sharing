package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

func chainReq(method, path, body string, claims *domain.UserClaims, headerTenant string) *http.Request {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	if headerTenant != "" {
		r.Header.Set("X-Tenant-ID", headerTenant)
	}
	if claims != nil {
		ctx := context.WithValue(r.Context(), middleware.UserClaimsContextKey, claims)
		r = r.WithContext(context.WithValue(ctx, middleware.VerifiedClaimsContextKey, claims))
	}
	return r
}

func adminClaims() *domain.UserClaims {
	return &domain.UserClaims{UserID: "u-admin", TenantID: "tenant-adeco", Email: "admin@adeco.test", Role: domain.RoleVendorAdmin}
}

func TestChainWritesRequireAdminClaims(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewAdminHandler(fs)
	code := fmt.Sprintf("zz%d", time.Now().UnixNano()%1e9)
	body := fmt.Sprintf(`{"display_name":"سلسلة اختبار","code":%q}`, code)

	cases := []struct {
		name   string
		claims *domain.UserClaims
		header string
		want   int
	}{
		{"no token", nil, "tenant-adeco", http.StatusUnauthorized},
		{"header alone grants nothing", nil, "adeco", http.StatusUnauthorized},
		{"non-admin", &domain.UserClaims{UserID: "u1", TenantID: "tenant-adeco", Email: "m@x", Role: domain.UserRole("merchandiser")}, "tenant-adeco", http.StatusForbidden},
		{"admin, header tenant mismatch", adminClaims(), "tenant-other", http.StatusForbidden},
		{"admin", adminClaims(), "tenant-adeco", http.StatusCreated},
		{"duplicate", adminClaims(), "", http.StatusConflict},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		h.HandleCreateChain(w, chainReq(http.MethodPost, "/admin/chains", body, c.claims, c.header))
		if w.Code != c.want && !(c.want == http.StatusCreated && w.Code == http.StatusOK) {
			t.Fatalf("%s: got %d want %d: %s", c.name, w.Code, c.want, w.Body.String())
		}
	}
	ch, err := fs.GetRetailChainByTenant(context.Background(), "adeco", code)
	if err != nil || ch == nil {
		t.Fatalf("chain not stored: %v", err)
	}
	if ch.CreatedBy != "admin@adeco.test" || ch.CreatedAt.IsZero() || ch.DisplayName != "سلسلة اختبار" || ch.ChainType != "supermarket" {
		t.Fatalf("created_by/at/type wrong: %+v", ch)
	}
	logs, _ := fs.GetAuditLogs(context.Background(), "tenant-adeco", "CREATE_CHAIN", 50)
	found := false
	for _, l := range logs {
		found = found || l.UserEmail == "admin@adeco.test" && strings.Contains(l.Details+l.Resource, code)
	}
	if !found {
		t.Fatalf("no CREATE_CHAIN audit entry by admin for %s: %+v", code, logs)
	}

	// Update/delete: non-admin 403, missing token 401.
	for _, m := range []string{http.MethodPut, http.MethodDelete} {
		w := httptest.NewRecorder()
		r := chainReq(m, "/admin/chains/"+code, `{"display_name":"x"}`, &domain.UserClaims{UserID: "u1", TenantID: "tenant-adeco", Role: domain.UserRole("viewer")}, "")
		r.SetPathValue("id", code)
		if m == http.MethodPut {
			h.HandleUpdateChain(w, r)
		} else {
			h.HandleDeleteChain(w, r)
		}
		if w.Code != http.StatusForbidden {
			t.Fatalf("%s non-admin: got %d", m, w.Code)
		}
		w = httptest.NewRecorder()
		r = chainReq(m, "/admin/chains/"+code, `{"display_name":"x"}`, nil, "tenant-adeco")
		r.SetPathValue("id", code)
		if m == http.MethodPut {
			h.HandleUpdateChain(w, r)
		} else {
			h.HandleDeleteChain(w, r)
		}
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("%s no token: got %d", m, w.Code)
		}
	}
	// Cleanup in the mock store (admin delete must be allowed).
	w := httptest.NewRecorder()
	r := chainReq(http.MethodDelete, "/admin/chains/"+code, "", adminClaims(), "")
	r.SetPathValue("id", code)
	h.HandleDeleteChain(w, r)
	if w.Code >= 300 {
		t.Fatalf("admin delete: %d %s", w.Code, w.Body.String())
	}
}

func TestListChainsIncludeReferenced(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewAdminHandler(fs).WithReferencedChains(func(string) []string { return []string{"zahran_ref_test", "fathalla"} })
	w := httptest.NewRecorder()
	h.HandleListChains(w, chainReq(http.MethodGet, "/admin/chains?include_referenced=1", "", adminClaims(), "tenant-adeco"))
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"code":"zahran_ref_test"`) || !strings.Contains(w.Body.String(), `"registered":false`) {
		t.Fatalf("referenced chain missing: %d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	h.HandleListChains(w, chainReq(http.MethodGet, "/admin/chains", "", adminClaims(), "tenant-adeco"))
	if strings.Contains(w.Body.String(), "zahran_ref_test") {
		t.Fatalf("default list must stay unchanged")
	}
}

// Through the real middleware: a non-admin token plus X-Simulated-Role: vendor_admin must still be 403,
// and no token at all is 401.
func TestChainWritesIgnoreSimulatedRoleHeader(t *testing.T) {
	secret := "test-secret-chain-access"
	am := middleware.NewAuthMiddleware(secret, false)
	h := NewAdminHandler(firestore.NewClient("test-db", true))
	srv := am.Handler(http.HandlerFunc(h.HandleCreateChain))
	tok, err := am.GenerateToken(domain.UserClaims{UserID: "u1", TenantID: "tenant-adeco", Email: "m@x", Role: domain.UserRole("merchandiser")}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest(http.MethodPost, "/admin/chains", strings.NewReader(`{"display_name":"x","code":"zzsim"}`))
	r.Header.Set("Authorization", "Bearer "+tok)
	r.Header.Set("X-Simulated-Role", "vendor_admin")
	r.Header.Set("X-Tenant-ID", "tenant-adeco")
	w := httptest.NewRecorder()
	srv.ServeHTTP(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatalf("simulated role must not grant chain writes: %d %s", w.Code, w.Body.String())
	}
	r = httptest.NewRequest(http.MethodPost, "/admin/chains", strings.NewReader(`{}`))
	r.Header.Set("Authorization", "Bearer garbage")
	w = httptest.NewRecorder()
	srv.ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized && w.Code != http.StatusForbidden {
		t.Fatalf("invalid token: %d", w.Code)
	}
}

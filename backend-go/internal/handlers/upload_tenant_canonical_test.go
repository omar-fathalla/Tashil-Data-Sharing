package handlers

import (
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

// Hotfix (prod 2477d63): the web app sends tenant_id=tenant-adeco while the prod token carries "adeco".
// A raw string compare turned every own-tenant upload into a 403.

const siCSV = "x,y\n1,2\n" // not a valid plan: once the tenant gate passes it fails with a non-403 parse error

func TestUploadTenantCanonicalMatrix(t *testing.T) {
	type tc struct {
		name      string
		role      domain.UserRole
		token     string
		requested string
		want      int
	}
	cases := []tc{
		{"own prefixed, bare token (prod)", domain.RoleVendorAdmin, "adeco", "tenant-adeco", 200},
		{"own bare, bare token", domain.RoleVendorAdmin, "adeco", "adeco", 200},
		{"empty", domain.RoleVendorAdmin, "adeco", "", 200},
		{"own bare, prefixed token", domain.RoleVendorAdmin, "tenant-adeco", "adeco", 200},
		{"own underscore", domain.RoleVendorAdmin, "adeco", "tenant_adeco", 200},
		{"own case/space", domain.RoleVendorAdmin, "adeco", "  TENANT-ADECO ", 200},
		{"foreign prefixed", domain.RoleVendorAdmin, "adeco", "tenant-other", 403},
		{"foreign bare", domain.RoleVendorAdmin, "adeco", "other", 403},
		{"super_admin foreign", domain.RoleSuperAdmin, "adeco", "tenant-other", 200},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e := newScopeEnv(t)
			tok := e.token(t, c.role, c.token)
			q := "&tenant_id=" + strings.ReplaceAll(c.requested, " ", "%20")
			// Product Master: real upload and dry run.
			for _, dry := range []string{"", "&dry_run=true"} {
				rec := e.post("/api/v1/product-master/upload?filename=pm.csv"+q+dry, tok, pmCSVv1)
				if rec.Code != c.want {
					t.Fatalf("product master%s: want %d, got %d %s", dry, c.want, rec.Code, rec.Body.String())
				}
			}
			// Sell-In: the tenant gate decides 403 vs not-403 (the body itself is not a valid plan).
			rec := e.post("/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=qa_test"+q, tok, siCSV)
			if (rec.Code == http.StatusForbidden) != (c.want == 403) {
				t.Fatalf("sell-in: want 403=%v, got %d %s", c.want == 403, rec.Code, rec.Body.String())
			}
			if c.want == 403 {
				for _, ft := range []string{"product_master", "sell_in"} {
					for _, tn := range []string{"tenant-other", "other"} {
						if n := e.archiveCount(tn, ft); n != 0 {
							t.Fatalf("refused upload wrote %d %s archives to %s", n, ft, tn)
						}
					}
				}
			}
		})
	}
}

// The resolved tenant for a non-super_admin is always the token's own value, never the requested spelling.
func TestResolveUploadTenantReturnsTokenValue(t *testing.T) {
	vendor := &domain.UserClaims{Role: domain.RoleVendorAdmin}
	for _, c := range []struct{ token, requested, want string }{
		{"adeco", "tenant-adeco", "adeco"},
		{"adeco", "tenant_adeco", "adeco"},
		{"tenant-adeco", "adeco", "tenant-adeco"},
		{"x", "tenant_x", "x"},
		{"adeco", "", "adeco"},
	} {
		rec := httptest.NewRecorder()
		got, ok := resolveUploadTenant(rec, vendor, c.token, c.requested)
		if !ok || got != c.want {
			t.Fatalf("token=%q requested=%q: got %q ok=%v, want %q", c.token, c.requested, got, ok, c.want)
		}
	}
	super := &domain.UserClaims{Role: domain.RoleSuperAdmin}
	if got, ok := resolveUploadTenant(httptest.NewRecorder(), super, "adeco", "tenant-other"); !ok || got != "tenant-other" {
		t.Fatalf("super_admin foreign: got %q ok=%v", got, ok)
	}
}

// (a) Collision: a non-super_admin with token tenant "x" can never be routed to a separate real tenant
// whose id is spelled "tenant_x" (or stacked "tenant-tenant_x"). Own spellings write to "x" itself; a
// stacked prefix is a different tenant and is refused.
func TestUploadTenantCollisionStaysOnTokenTenant(t *testing.T) {
	e := newScopeEnv(t)
	tok := e.token(t, domain.RoleVendorAdmin, "x")
	rec := e.post("/api/v1/product-master/upload?filename=pm.csv&tenant_id=tenant_x", tok, pmCSVv1)
	if rec.Code != http.StatusOK {
		t.Fatalf("own underscore spelling: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	var res ingestion.IngestionResult
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if a, _, err := e.proc.GetArchivedFile(context.Background(), "x", res.ArchiveID); err != nil || a == nil || !middleware.SameTenant(a.TenantID, "x") {
		t.Fatalf("archive not stored under the token tenant x: %+v %v", a, err)
	}
	for _, stacked := range []string{"tenant-tenant_x", "tenant_tenant-x", "tenant-tenant-x"} {
		for _, path := range []string{
			"/api/v1/product-master/upload?filename=pm.csv&tenant_id=" + stacked,
			"/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=qa_test&tenant_id=" + stacked,
		} {
			if rec := e.post(path, tok, pmCSVv1); rec.Code != http.StatusForbidden {
				t.Fatalf("%s: want 403, got %d %s", path, rec.Code, rec.Body.String())
			}
		}
	}
}

// The web app sends tenant_id as a multipart form field too; the same canonical rule applies there.
func TestUploadTenantCanonicalFormField(t *testing.T) {
	e := newScopeEnv(t)
	tok := e.token(t, domain.RoleVendorAdmin, "adeco")
	send := func(path, tenant string) int {
		var b strings.Builder
		mw := multipart.NewWriter(&b)
		_ = mw.WriteField("tenant_id", tenant)
		fw, _ := mw.CreateFormFile("file", "pm.csv")
		_, _ = fw.Write([]byte(pmCSVv1))
		_ = mw.Close()
		req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(b.String()))
		req.Header.Set("Authorization", "Bearer "+tok)
		req.Header.Set("Content-Type", mw.FormDataContentType())
		rec := httptest.NewRecorder()
		e.h.ServeHTTP(rec, req)
		return rec.Code
	}
	if c := send("/api/v1/product-master/upload?filename=pm.csv", "tenant-adeco"); c != http.StatusOK {
		t.Fatalf("form own tenant: want 200, got %d", c)
	}
	if c := send("/api/v1/product-master/upload?filename=pm.csv", "tenant-other"); c != http.StatusForbidden {
		t.Fatalf("form foreign tenant: want 403, got %d", c)
	}
	if c := send("/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=qa_test", "tenant-adeco"); c == http.StatusForbidden {
		t.Fatalf("sell-in form own tenant: got 403")
	}
	if c := send("/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=qa_test", "tenant-other"); c != http.StatusForbidden {
		t.Fatalf("sell-in form foreign tenant: want 403, got %d", c)
	}
}

// (b) The system/all override in archive list and download now goes through middleware.IsSystemTenant.
// Behaviour is unchanged: exactly "system", "all", "tenant-system", "tenant-all" may pick ?tenant= /
// X-Tenant-ID; any other token (including near-spellings like "System" or "tenant_system") stays on its own.
func TestArchiveSystemOverrideUnchanged(t *testing.T) {
	e := newScopeEnv(t)
	mux := http.NewServeMux()
	up := NewUploadHandler(e.proc)
	mux.HandleFunc("GET /api/v1/ingest/archive", up.HandleListArchive)
	mux.HandleFunc("GET /api/v1/ingest/archive/{id}/download", up.HandleDownloadArchivedFile)
	h := e.mw.Handler(mux)

	superTok := e.token(t, domain.RoleSuperAdmin, "system")
	rec := e.post("/api/v1/product-master/upload?filename=pm_other.csv&tenant_id=tenant-other", superTok, pmCSVv1)
	if rec.Code != http.StatusOK {
		t.Fatalf("seed: %d %s", rec.Code, rec.Body.String())
	}
	var res ingestion.IngestionResult
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	otherID := res.ArchiveID

	get := func(tok, path string, header bool) *httptest.ResponseRecorder {
		if !header {
			path += "&tenant=tenant-other"
		}
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		if header {
			req.Header.Set("X-Tenant-ID", "tenant-other")
		}
		r := httptest.NewRecorder()
		h.ServeHTTP(r, req)
		return r
	}
	for _, c := range []struct {
		token string
		role  domain.UserRole
		sees  bool
	}{
		{"system", domain.RoleSuperAdmin, true},
		{"all", domain.RoleSuperAdmin, true},
		{"tenant-system", domain.RoleSuperAdmin, true},
		{"tenant-all", domain.RoleSuperAdmin, true},
		{"System", domain.RoleSuperAdmin, false},
		{"tenant_system", domain.RoleSuperAdmin, false},
		{"adeco", domain.RoleVendorAdmin, false},
		{"tenant-adeco", domain.RoleVendorAdmin, false},
	} {
		tok := e.token(t, c.role, c.token)
		for _, header := range []bool{false, true} {
			// The auth middleware separately lets any verified super_admin switch via X-Tenant-ID
			// (unchanged, outside this predicate), so a super_admin header request always sees the target.
			want := c.sees || (header && c.role == domain.RoleSuperAdmin)
			list := get(tok, "/api/v1/ingest/archive?file_type=product_master", header)
			if got := strings.Contains(list.Body.String(), otherID); got != want {
				t.Errorf("list token=%q header=%v: sees other=%v, want %v", c.token, header, got, want)
			}
			dl := get(tok, "/api/v1/ingest/archive/"+otherID+"/download?x=1", header)
			if got := dl.Code == http.StatusOK; got != want {
				t.Errorf("download token=%q header=%v: code %d, want ok=%v", c.token, header, dl.Code, want)
			}
		}
	}
}

// (b) applySystemTenantOverride (general upload, commit, archive list/download) is identical to the
// inline rule it replaced for every token/override combination.
func TestApplySystemTenantOverrideMatchesLegacy(t *testing.T) {
	legacy := func(tenantID, override string) string {
		if override != "" && (tenantID == "system" || tenantID == "all" || tenantID == "tenant-system" || tenantID == "tenant-all") {
			return override
		}
		return tenantID
	}
	tokens := []string{"system", "all", "tenant-system", "tenant-all", "System", " system", "tenant_system", "adeco", "tenant-adeco", "x", ""}
	overrides := []string{"", "tenant-other", "other", "tenant-adeco", " adeco "}
	for _, tk := range tokens {
		for _, ov := range overrides {
			if got, want := applySystemTenantOverride(tk, ov), legacy(tk, ov); got != want {
				t.Errorf("applySystemTenantOverride(%q,%q) = %q, legacy %q", tk, ov, got, want)
			}
		}
	}
}

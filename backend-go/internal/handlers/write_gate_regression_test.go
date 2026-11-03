package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

// writeGateMux wires every write route of cmd/server/main.go behind the real AuthMiddleware with demo
// tokens OFF (production behaviour).
func writeGateMux(t *testing.T) (http.Handler, *middleware.AuthMiddleware) {
	t.Helper()
	setupIsolatedProductMasterDir(t)
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	fs := firestore.NewClient("test-db", true)
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true), bq, fs).WithArchiveDir(t.TempDir())
	mw := middleware.NewAuthMiddleware("test-secret", false)

	admin := NewAdminHandler(fs)
	up := NewUploadHandler(proc)
	an := NewAnalyticsHandler(bq)
	cd := NewChainDiscountHandler(fs, fs, nil)
	cr := NewCustomerRegistryHandler(proc, fs)
	dq := NewDataQualityHandler(nil, fs)
	tm := NewTradeMarketingHandler(fs, fs)
	comp := NewCompetitorHandler(fs, fs)

	mux := http.NewServeMux()
	for pattern, h := range map[string]http.HandlerFunc{
		"GET /api/v1/admin/tenants":                      admin.HandleListTenants,
		"POST /api/v1/admin/tenants":                     admin.HandleCreateTenant,
		"PUT /api/v1/admin/tenants/{id}":                 admin.HandleUpdateTenant,
		"DELETE /api/v1/admin/tenants/{id}":              admin.HandleDeleteTenant,
		"POST /api/v1/admin/tenants/{id}/reset-password": admin.HandleResetTenantPassword,
		"POST /api/v1/admin/chains":                      admin.HandleCreateChain,
		"PUT /api/v1/admin/chains/{id}":                  admin.HandleUpdateChain,
		"DELETE /api/v1/admin/chains/{id}":               admin.HandleDeleteChain,
		"POST /api/v1/ingest/upload":                     up.HandleUpload,
		"POST /api/v1/ingest/commit":                     up.HandleCommit,
		"POST /api/v1/ingest/discard":                    up.HandleDiscard,
		"POST /api/v1/ingest/clear":                      up.HandleClearData,
		"DELETE /api/v1/ingest/clear":                    up.HandleClearData,
		"POST /api/v1/ingest/load-default-excel":         up.HandleLoadLocalExcel,
		"POST /api/v1/ingest/load-sell-in-plan":          up.HandleLoadSellInPlan,
		"DELETE /api/v1/ingest/archive/{id}":             up.HandleDeleteArchive,
		"DELETE /api/v1/ingest/archive":                  up.HandleDeleteArchive,
		"PUT /api/v1/product-master/item":                an.HandleUpdateProductMasterItem,
		"POST /api/v1/product-master/item":               an.HandleUpdateProductMasterItem,
		"POST /api/v1/product-master/upload":             up.HandleUploadProductMaster,
		"PUT /api/v1/product-master/chain-discounts":     cd.HandlePut,
		"POST /api/v1/analytics/targets":                 an.HandleTargets,
		"DELETE /api/v1/analytics/targets":               an.HandleTargets,
		"POST /api/v1/analytics/targets/upload":          an.HandleUploadTargetsFile,
		"PATCH /api/v1/data-quality/issues/{id}":         dq.HandlePatchStatus,
		"POST /api/v1/customers/registry/approve":        cr.HandleApprove,
		"POST /api/v1/customers/registry/reject":         cr.HandleReject,
		"POST /api/v1/customers/registry/unmerge":        cr.HandleUnmerge,
		"POST /api/v1/trade-marketing/expenses":          tm.HandleCreateExpense,
		"POST /api/v1/trade-marketing/expenses/upload":   tm.HandleUploadExpenses,
		"PUT /api/v1/trade-marketing/expenses/{id}":      tm.HandleUpdateExpense,
		"DELETE /api/v1/trade-marketing/expenses/{id}":   tm.HandleDeleteExpense,
		"POST /api/v1/competitors/custom-skus":           comp.HandleSaveCustomSku,
		"DELETE /api/v1/competitors/custom-skus/{id}":    comp.HandleDeleteCustomSku,
	} {
		mux.HandleFunc(pattern, h)
	}
	return mw.Handler(mux), mw
}

func tokenFor(t *testing.T, mw *middleware.AuthMiddleware, role domain.UserRole) string {
	t.Helper()
	tok, err := mw.GenerateToken(domain.UserClaims{UserID: "u-" + string(role), Email: "u@example.test", TenantID: "tenant-adeco", Role: role, AssignedChain: "chain-a"}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

func hit(h http.Handler, method, path, tok string, hdr map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(`{"name":"x","code":"x","names":["x"],"status":"fixed"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

var writeRoutes = [][2]string{
	{"POST", "/api/v1/admin/tenants"}, {"PUT", "/api/v1/admin/tenants/t1"}, {"DELETE", "/api/v1/admin/tenants/t1"},
	{"POST", "/api/v1/admin/tenants/t1/reset-password"},
	{"POST", "/api/v1/admin/chains"}, {"PUT", "/api/v1/admin/chains/c1"}, {"DELETE", "/api/v1/admin/chains/c1"},
	{"POST", "/api/v1/ingest/upload"}, {"POST", "/api/v1/ingest/commit"}, {"POST", "/api/v1/ingest/discard"},
	{"POST", "/api/v1/ingest/clear"}, {"DELETE", "/api/v1/ingest/clear"},
	{"POST", "/api/v1/ingest/load-default-excel"}, {"POST", "/api/v1/ingest/load-sell-in-plan"},
	{"DELETE", "/api/v1/ingest/archive/a1"}, {"DELETE", "/api/v1/ingest/archive"},
	{"PUT", "/api/v1/product-master/item"}, {"POST", "/api/v1/product-master/item"}, {"POST", "/api/v1/product-master/upload"},
	{"PUT", "/api/v1/product-master/chain-discounts"},
	{"POST", "/api/v1/analytics/targets"}, {"DELETE", "/api/v1/analytics/targets"}, {"POST", "/api/v1/analytics/targets/upload"},
	{"PATCH", "/api/v1/data-quality/issues/i1"},
	{"POST", "/api/v1/customers/registry/approve"}, {"POST", "/api/v1/customers/registry/reject"}, {"POST", "/api/v1/customers/registry/unmerge"},
	{"POST", "/api/v1/trade-marketing/expenses"}, {"POST", "/api/v1/trade-marketing/expenses/upload"},
	{"PUT", "/api/v1/trade-marketing/expenses/e1"}, {"DELETE", "/api/v1/trade-marketing/expenses/e1"},
	{"POST", "/api/v1/competitors/custom-skus"}, {"DELETE", "/api/v1/competitors/custom-skus/s1"},
}

// A role-less user is refused on every write route, and no header can escalate it.
func TestEveryWriteRouteRefusesRolelessUserEvenWithHeaders(t *testing.T) {
	h, mw := writeGateMux(t)
	tok := tokenFor(t, mw, "")
	for _, hdr := range []map[string]string{
		nil,
		{"X-Simulated-Role": "super_admin"},
		{"X-Simulated-Role": "vendor_admin"},
		{"X-Simulated-Role": "admin", "X-Assigned-Chain": "chain-b", "X-Tenant-ID": "system"},
	} {
		for _, rt := range writeRoutes {
			if rec := hit(h, rt[0], rt[1], tok, hdr); rec.Code != http.StatusForbidden {
				t.Errorf("%s %s headers=%v: want 403, got %d %s", rt[0], rt[1], hdr, rec.Code, rec.Body.String())
			}
		}
	}
}

// A normal (vendor_admin) user with X-Simulated-Role: super_admin gets 403 on every admin/tenants route.
func TestAdminTenantRoutesIgnoreSimulatedSuperAdmin(t *testing.T) {
	h, mw := writeGateMux(t)
	for _, role := range []domain.UserRole{domain.RoleVendorAdmin, domain.RoleNationalSalesManager, "admin"} {
		tok := tokenFor(t, mw, role)
		for _, rt := range [][2]string{{"GET", "/api/v1/admin/tenants"}, {"POST", "/api/v1/admin/tenants"},
			{"PUT", "/api/v1/admin/tenants/t1"}, {"DELETE", "/api/v1/admin/tenants/t1"}, {"POST", "/api/v1/admin/tenants/t1/reset-password"}} {
			if rec := hit(h, rt[0], rt[1], tok, map[string]string{"X-Simulated-Role": "super_admin", "X-Tenant-ID": "system"}); rec.Code != http.StatusForbidden {
				t.Errorf("%s %s %s: want 403, got %d", role, rt[0], rt[1], rec.Code)
			}
		}
	}
}

// A non-admin with X-Simulated-Role: vendor_admin is refused on customer decide and chain writes, and the
// legacy "admin" role can no longer write chains.
func TestSimulatedVendorAdminCannotDecideOrWriteChains(t *testing.T) {
	h, mw := writeGateMux(t)
	routes := [][2]string{{"POST", "/api/v1/customers/registry/approve"}, {"POST", "/api/v1/customers/registry/reject"},
		{"POST", "/api/v1/customers/registry/unmerge"}, {"POST", "/api/v1/admin/chains"}, {"PUT", "/api/v1/admin/chains/c1"}, {"DELETE", "/api/v1/admin/chains/c1"}}
	for _, role := range []domain.UserRole{domain.RoleChainKAM, domain.RoleFieldSupervisor, domain.RoleSalesUser, domain.RoleViewer} {
		tok := tokenFor(t, mw, role)
		for _, rt := range routes {
			if rec := hit(h, rt[0], rt[1], tok, map[string]string{"X-Simulated-Role": "vendor_admin"}); rec.Code != http.StatusForbidden {
				t.Errorf("%s %s %s: want 403, got %d", role, rt[0], rt[1], rec.Code)
			}
		}
	}
	tok := tokenFor(t, mw, "admin")
	for _, rt := range routes[3:] {
		if rec := hit(h, rt[0], rt[1], tok, nil); rec.Code != http.StatusForbidden {
			t.Errorf("legacy admin %s %s: want 403, got %d", rt[0], rt[1], rec.Code)
		}
	}
}

// Clear (any scope) and archive delete are super_admin only, even for a vendor_admin.
func TestClearAndArchiveDeleteAreSuperAdminOnly(t *testing.T) {
	h, mw := writeGateMux(t)
	tok := tokenFor(t, mw, domain.RoleVendorAdmin)
	for _, rt := range [][2]string{{"POST", "/api/v1/ingest/clear"}, {"POST", "/api/v1/ingest/clear?scope=sell_in"},
		{"DELETE", "/api/v1/ingest/clear"}, {"DELETE", "/api/v1/ingest/archive/a1"}, {"DELETE", "/api/v1/ingest/archive"}} {
		if rec := hit(h, rt[0], rt[1], tok, map[string]string{"X-Simulated-Role": "super_admin"}); rec.Code != http.StatusForbidden {
			t.Errorf("vendor_admin %s %s: want 403, got %d", rt[0], rt[1], rec.Code)
		}
	}
	su := tokenFor(t, mw, domain.RoleSuperAdmin)
	if rec := hit(h, "DELETE", "/api/v1/ingest/archive/does-not-exist", su, nil); rec.Code == http.StatusForbidden || rec.Code == http.StatusUnauthorized {
		t.Errorf("super_admin archive delete must pass the gate, got %d", rec.Code)
	}
}

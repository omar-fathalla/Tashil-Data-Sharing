package handlers

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

type recordingApplier struct {
	tenant   string
	profiles []domain.ChainDiscountProfile
	calls    int
}

func (a *recordingApplier) SetChainDiscountProfiles(tenantID string, p []domain.ChainDiscountProfile) {
	a.tenant, a.profiles, a.calls = tenantID, p, a.calls+1
}

func cdMux(h *ChainDiscountHandler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/product-master/chain-discounts", h.HandleGet)
	mux.HandleFunc("PUT /api/v1/product-master/chain-discounts", h.HandlePut)
	return mux
}

func TestChainDiscountProfilesCRUDAuditAndTenantIsolation(t *testing.T) {
	fs := firestore.NewClient("", true)
	app := &recordingApplier{}
	mux := cdMux(NewChainDiscountHandler(fs, fs, app))
	admin := &domain.UserClaims{UserID: "u1", Email: "admin@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleAdmin}
	other := &domain.UserClaims{UserID: "u2", Email: "x@pepsi.test", TenantID: "tenant-pepsi", Role: domain.RoleAdmin}
	kam := &domain.UserClaims{UserID: "u3", Email: "kam@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleChainKAM, AssignedChain: "fathalla"}

	// Empty by default, with the 10% / 0% defaults reported.
	rec, out := tmDo(t, mux, admin, "GET", "/api/v1/product-master/chain-discounts", nil)
	if rec.Code != 200 || len(out["profiles"].([]interface{})) != 0 || out["default_invoice_discount_pct"].(float64) != 10 || out["default_additional_discount_pct"].(float64) != 0 {
		t.Fatalf("unexpected empty GET: %d %v", rec.Code, out)
	}

	// Add two.
	body := map[string]interface{}{"profiles": []map[string]interface{}{
		{"chain": "Kazyon", "invoice_discount_pct": 12, "additional_discount_pct": 2},
		{"chain": "fathalla", "invoice_discount_pct": 10, "additional_discount_pct": 0},
	}}
	rec, out = tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", body)
	if rec.Code != 200 || len(out["profiles"].([]interface{})) != 2 {
		t.Fatalf("PUT failed: %d %v", rec.Code, out)
	}
	if app.calls == 0 || len(app.profiles) != 2 {
		t.Fatalf("profiles must be applied to CPFR cost")
	}

	// Edit one, delete the other.
	body = map[string]interface{}{"profiles": []map[string]interface{}{{"chain": "kazyon", "invoice_discount_pct": 15, "additional_discount_pct": 2}}}
	rec, out = tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", body)
	ps := out["profiles"].([]interface{})
	if rec.Code != 200 || len(ps) != 1 || ps[0].(map[string]interface{})["invoice_discount_pct"].(float64) != 15 {
		t.Fatalf("edit/delete failed: %d %v", rec.Code, out)
	}

	// Validation.
	for _, bad := range []interface{}{
		[]map[string]interface{}{{"chain": "", "invoice_discount_pct": 5}},
		[]map[string]interface{}{{"chain": "a", "invoice_discount_pct": 100}},
		[]map[string]interface{}{{"chain": "a", "additional_discount_pct": -1}},
		[]map[string]interface{}{{"chain": "a"}, {"chain": " A "}},
	} {
		if rec, _ := tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", map[string]interface{}{"profiles": bad}); rec.Code != 400 {
			t.Fatalf("expected 400 for %v, got %d", bad, rec.Code)
		}
	}

	// RBAC: KAM can read but not write; no claims -> 401.
	if rec, _ := tmDo(t, mux, kam, "GET", "/api/v1/product-master/chain-discounts", nil); rec.Code != 200 {
		t.Fatalf("KAM read: %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, kam, "PUT", "/api/v1/product-master/chain-discounts", body); rec.Code != 403 {
		t.Fatalf("KAM write must be 403, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, nil, "GET", "/api/v1/product-master/chain-discounts", nil); rec.Code != 401 {
		t.Fatalf("no claims must be 401, got %d", rec.Code)
	}

	// Tenant isolation.
	_, out = tmDo(t, mux, other, "GET", "/api/v1/product-master/chain-discounts", nil)
	if len(out["profiles"].([]interface{})) != 0 {
		t.Fatalf("other tenant must not see adeco profiles: %v", out)
	}

	// Audit log entries.
	logs, _ := fs.GetAuditLogs(context.Background(), "tenant-adeco", "chain_discounts_update", 10)
	if len(logs) < 2 {
		t.Fatalf("expected audit entries, got %d", len(logs))
	}
	joined := ""
	for _, l := range logs {
		joined += l.Details + "\n"
	}
	if !strings.Contains(joined, "added Kazyon") || !strings.Contains(joined, "deleted fathalla") || !strings.Contains(joined, "updated kazyon invoice 12.00%→15.00%") {
		t.Fatalf("audit details missing changes:\n%s", joined)
	}
}

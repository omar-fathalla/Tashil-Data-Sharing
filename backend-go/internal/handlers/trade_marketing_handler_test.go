package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

func tmMux(h *TradeMarketingHandler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/trade-marketing/expenses", h.HandleListExpenses)
	mux.HandleFunc("POST /api/v1/trade-marketing/expenses", h.HandleCreateExpense)
	mux.HandleFunc("PUT /api/v1/trade-marketing/expenses/{id}", h.HandleUpdateExpense)
	mux.HandleFunc("DELETE /api/v1/trade-marketing/expenses/{id}", h.HandleDeleteExpense)
	return mux
}

func tmDo(t *testing.T, mux *http.ServeMux, claims *domain.UserClaims, method, path string, body interface{}) (*httptest.ResponseRecorder, map[string]interface{}) {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	if claims != nil {
		req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims))
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	out := map[string]interface{}{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec, out
}

func validExpense(chain string) map[string]interface{} {
	return map[string]interface{}{"year": 2026, "month": 2, "chain_name": chain, "category": "promotions",
		"brand_name": "Adeco", "campaign_title": "Ramadan", "amount_egp": 15000}
}

func TestTradeMarketingCRUDAndTenantIsolation(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := tmMux(NewTradeMarketingHandler(fs, fs))
	adeco := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	other := &domain.UserClaims{UserID: "u2", TenantID: "unilever", Email: "b@uni.com", Role: domain.RoleVendorAdmin}

	rec, _ := tmDo(t, mux, nil, "GET", "/api/v1/trade-marketing/expenses", nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("no claims: want 401, got %d", rec.Code)
	}

	rec, out := tmDo(t, mux, adeco, "POST", "/api/v1/trade-marketing/expenses", validExpense("carrefour"))
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: want 201, got %d %s", rec.Code, rec.Body.String())
	}
	id := out["expense"].(map[string]interface{})["id"].(string)

	_, out = tmDo(t, mux, adeco, "GET", "/api/v1/trade-marketing/expenses?year=2026&month=2", nil)
	if out["count"].(float64) != 1 || out["total_amount_egp"].(float64) != 15000 {
		t.Fatalf("list: unexpected %v", out)
	}
	_, out = tmDo(t, mux, other, "GET", "/api/v1/trade-marketing/expenses", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("tenant leak: other tenant sees %v", out)
	}

	upd := validExpense("carrefour")
	upd["amount_egp"] = 20000
	if rec, _ = tmDo(t, mux, other, "PUT", "/api/v1/trade-marketing/expenses/"+id, upd); rec.Code != http.StatusNotFound {
		t.Fatalf("cross-tenant update: want 404, got %d", rec.Code)
	}
	if rec, _ = tmDo(t, mux, adeco, "PUT", "/api/v1/trade-marketing/expenses/"+id, upd); rec.Code != http.StatusOK {
		t.Fatalf("update: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	if rec, _ = tmDo(t, mux, other, "DELETE", "/api/v1/trade-marketing/expenses/"+id, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("cross-tenant delete: want 404, got %d", rec.Code)
	}
	if rec, _ = tmDo(t, mux, adeco, "DELETE", "/api/v1/trade-marketing/expenses/"+id, nil); rec.Code != http.StatusOK {
		t.Fatalf("delete: want 200, got %d", rec.Code)
	}
	_, out = tmDo(t, mux, adeco, "GET", "/api/v1/trade-marketing/expenses", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("after delete: %v", out)
	}

	logs, _ := fs.GetAuditLogs(context.Background(), "adeco", "CREATE_MARKETING_EXPENSE", 10)
	if len(logs) == 0 {
		t.Fatalf("expected audit log for create")
	}
}

func TestTradeMarketingValidationAndRoles(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := tmMux(NewTradeMarketingHandler(fs, fs))
	viewer := &domain.UserClaims{TenantID: "adeco", Role: domain.RoleViewer}
	kam := &domain.UserClaims{TenantID: "adeco", Role: domain.RoleChainKAM, AssignedChain: "spinneys"}
	admin := &domain.UserClaims{TenantID: "adeco", Role: domain.RoleVendorAdmin}

	if rec, _ := tmDo(t, mux, viewer, "POST", "/api/v1/trade-marketing/expenses", validExpense("carrefour")); rec.Code != http.StatusForbidden {
		t.Fatalf("viewer write: want 403, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, kam, "POST", "/api/v1/trade-marketing/expenses", validExpense("carrefour")); rec.Code != http.StatusForbidden {
		t.Fatalf("kam other chain: want 403, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, kam, "POST", "/api/v1/trade-marketing/expenses", validExpense("spinneys")); rec.Code != http.StatusCreated {
		t.Fatalf("kam own chain: want 201, got %d", rec.Code)
	}
	tmDo(t, mux, admin, "POST", "/api/v1/trade-marketing/expenses", validExpense("carrefour"))
	_, out := tmDo(t, mux, kam, "GET", "/api/v1/trade-marketing/expenses", nil)
	if out["count"].(float64) != 1 {
		t.Fatalf("kam should only see own chain, got %v", out)
	}
	for name, mutate := range map[string]func(m map[string]interface{}){
		"bad month":    func(m map[string]interface{}) { m["month"] = 13 },
		"bad category": func(m map[string]interface{}) { m["category"] = "x" },
		"zero amount":  func(m map[string]interface{}) { m["amount_egp"] = 0 },
		"no chain":     func(m map[string]interface{}) { m["chain_name"] = "" },
	} {
		p := validExpense("carrefour")
		mutate(p)
		if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/trade-marketing/expenses", p); rec.Code != http.StatusBadRequest {
			t.Fatalf("%s: want 400, got %d", name, rec.Code)
		}
	}
}

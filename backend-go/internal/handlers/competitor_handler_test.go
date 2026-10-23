package handlers

import (
	"context"
	"net/http"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

func ccMux(h *CompetitorHandler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/competitors/custom-skus", h.HandleListCustomSkus)
	mux.HandleFunc("POST /api/v1/competitors/custom-skus", h.HandleSaveCustomSku)
	mux.HandleFunc("DELETE /api/v1/competitors/custom-skus/{id}", h.HandleDeleteCustomSku)
	return mux
}

func validCustomSku(chain string) map[string]interface{} {
	return map[string]interface{}{
		"own_barcode": "6223000239438", "own_sku_name": "فيبا 3 كجم", "own_unit_price": 184.67,
		"own_volume_units": 3, "own_volume_unit_label": "كجم", "competitor_sku_name": "بريل 4 كجم",
		"competitor_brand": "Pril", "competitor_supplier": "Henkel", "category": "صابون سائل اطباق",
		"pack_size_label": "4 كجم", "pack_volume_units": 4, "competitor_price": 150.85,
		"retailer_chain": chain, "estimated_monthly_units": 400, "is_promo_active": true,
	}
}

func TestCustomCompetitorSkuCRUDDedupeAndTenantIsolation(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := ccMux(NewCompetitorHandler(fs, fs))
	adeco := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	other := &domain.UserClaims{UserID: "u2", TenantID: "unilever", Email: "b@uni.com", Role: domain.RoleVendorAdmin}

	if rec, _ := tmDo(t, mux, nil, "GET", "/api/v1/competitors/custom-skus", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no claims: want 401, got %d", rec.Code)
	}
	rec, out := tmDo(t, mux, adeco, "POST", "/api/v1/competitors/custom-skus", validCustomSku("fathalla"))
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: want 201, got %d %s", rec.Code, rec.Body.String())
	}
	sku := out["custom_sku"].(map[string]interface{})
	id := sku["id"].(string)
	if sku["estimated_monthly_units"].(float64) != 400 || sku["is_promo_active"] != true {
		t.Fatalf("fields not persisted: %v", sku)
	}

	// Same key (case/space differences) updates instead of duplicating.
	dup := validCustomSku("Fathalla ")
	dup["competitor_sku_name"] = "  بريل   4 كجم"
	dup["competitor_price"] = 160.0
	rec, out = tmDo(t, mux, adeco, "POST", "/api/v1/competitors/custom-skus", dup)
	if rec.Code != http.StatusOK || out["updated"] != true || out["custom_sku"].(map[string]interface{})["id"] != id {
		t.Fatalf("dedupe update: got %d %v", rec.Code, out)
	}
	_, out = tmDo(t, mux, adeco, "GET", "/api/v1/competitors/custom-skus?chain=fathalla", nil)
	if out["count"].(float64) != 1 {
		t.Fatalf("dedupe: want 1 record, got %v", out)
	}
	if p := out["custom_skus"].([]interface{})[0].(map[string]interface{})["competitor_price"].(float64); p != 160 {
		t.Fatalf("update not applied, price=%v", p)
	}
	_, out = tmDo(t, mux, adeco, "GET", "/api/v1/competitors/custom-skus?category=other", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("category filter: %v", out)
	}

	// Same SKU in another tenant is a separate record and invisible across tenants.
	_, out = tmDo(t, mux, other, "GET", "/api/v1/competitors/custom-skus", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("tenant leak: %v", out)
	}
	if rec, _ = tmDo(t, mux, other, "DELETE", "/api/v1/competitors/custom-skus/"+id, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("cross-tenant delete: want 404, got %d", rec.Code)
	}
	rec, out = tmDo(t, mux, other, "POST", "/api/v1/competitors/custom-skus", validCustomSku("fathalla"))
	if rec.Code != http.StatusCreated || out["custom_sku"].(map[string]interface{})["id"] == id {
		t.Fatalf("other tenant create should be distinct: %d %v", rec.Code, out)
	}

	if rec, _ = tmDo(t, mux, adeco, "DELETE", "/api/v1/competitors/custom-skus/"+id, nil); rec.Code != http.StatusOK {
		t.Fatalf("delete: want 200, got %d", rec.Code)
	}
	if rec, _ = tmDo(t, mux, adeco, "DELETE", "/api/v1/competitors/custom-skus/"+id, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("second delete: want 404, got %d", rec.Code)
	}
	_, out = tmDo(t, mux, adeco, "GET", "/api/v1/competitors/custom-skus", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("after delete: %v", out)
	}
	for _, action := range []string{"CREATE_CUSTOM_COMPETITOR_SKU", "UPDATE_CUSTOM_COMPETITOR_SKU", "DELETE_CUSTOM_COMPETITOR_SKU"} {
		if logs, _ := fs.GetAuditLogs(context.Background(), "adeco", action, 10); len(logs) == 0 {
			t.Fatalf("expected audit log %s", action)
		}
	}
}

func TestCustomCompetitorSkuValidationAndRoles(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := ccMux(NewCompetitorHandler(fs, fs))
	viewer := &domain.UserClaims{TenantID: "adeco", Role: domain.RoleViewer}
	kam := &domain.UserClaims{TenantID: "adeco", Role: domain.RoleChainKAM, AssignedChain: "spinneys"}
	admin := &domain.UserClaims{TenantID: "adeco", Role: domain.RoleVendorAdmin}

	if rec, _ := tmDo(t, mux, viewer, "POST", "/api/v1/competitors/custom-skus", validCustomSku("fathalla")); rec.Code != http.StatusForbidden {
		t.Fatalf("viewer write: want 403, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, kam, "POST", "/api/v1/competitors/custom-skus", validCustomSku("fathalla")); rec.Code != http.StatusForbidden {
		t.Fatalf("kam other chain: want 403, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, kam, "POST", "/api/v1/competitors/custom-skus", validCustomSku("spinneys")); rec.Code != http.StatusCreated {
		t.Fatalf("kam own chain: want 201, got %d", rec.Code)
	}
	_, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/custom-skus", validCustomSku("fathalla"))
	adminID := out["custom_sku"].(map[string]interface{})["id"].(string)
	_, out = tmDo(t, mux, kam, "GET", "/api/v1/competitors/custom-skus?chain=fathalla", nil)
	if out["count"].(float64) != 1 {
		t.Fatalf("kam should only see own chain, got %v", out)
	}
	if rec, _ := tmDo(t, mux, kam, "DELETE", "/api/v1/competitors/custom-skus/"+adminID, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("kam delete other chain: want 404, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, viewer, "DELETE", "/api/v1/competitors/custom-skus/"+adminID, nil); rec.Code != http.StatusForbidden {
		t.Fatalf("viewer delete: want 403, got %d", rec.Code)
	}
	for name, mutate := range map[string]func(m map[string]interface{}){
		"no own key":      func(m map[string]interface{}) { m["own_barcode"] = ""; m["own_sku_name"] = " " },
		"no competitor":   func(m map[string]interface{}) { m["competitor_sku_name"] = "" },
		"no chain":        func(m map[string]interface{}) { m["retailer_chain"] = "" },
		"zero price":      func(m map[string]interface{}) { m["competitor_price"] = 0 },
		"negative volume": func(m map[string]interface{}) { m["pack_volume_units"] = -1 },
		"negative units":  func(m map[string]interface{}) { m["estimated_monthly_units"] = -5 },
	} {
		p := validCustomSku("fathalla")
		mutate(p)
		if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/custom-skus", p); rec.Code != http.StatusBadRequest {
			t.Fatalf("%s: want 400, got %d", name, rec.Code)
		}
	}
	// Own SKU name is the dedupe key when the barcode is empty.
	p := validCustomSku("fathalla")
	p["own_barcode"] = ""
	if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/custom-skus", p); rec.Code != http.StatusCreated {
		t.Fatalf("name-keyed create: want 201, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/custom-skus", p); rec.Code != http.StatusOK {
		t.Fatalf("name-keyed dedupe: want 200, got %d", rec.Code)
	}
}

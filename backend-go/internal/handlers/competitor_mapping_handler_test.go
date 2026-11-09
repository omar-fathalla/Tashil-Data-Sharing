package handlers

import (
	"net/http"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

func cmapMux(h *CompetitorHandler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/competitors/mappings", h.HandleListCompetitorMappings)
	mux.HandleFunc("POST /api/v1/competitors/mappings", h.HandleSaveCompetitorMapping)
	mux.HandleFunc("DELETE /api/v1/competitors/mappings/{id}", h.HandleDeleteCompetitorMapping)
	return mux
}

func validMapping(chain string) map[string]interface{} {
	return map[string]interface{}{
		"own_barcode":         "6223000999001",
		"competitor_barcode":  "6221143099674",
		"competitor_sku_name": "بريل",
		"competitor_brand":    "بريل (Pril)",
		"competitor_supplier": "هنكل",
		"retailer_chain":      chain,
	}
}

func TestCompetitorMappingsEmptyUntilOwnerSaves(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := cmapMux(NewCompetitorHandler(fs, fs))
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	_, out := tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings?chain=fathalla", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("expected empty mappings (no seed backfill), got %v", out)
	}

	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/mappings", validMapping("fathalla"))
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: want 201, got %d %s", rec.Code, rec.Body.String())
	}
	id := out["mapping"].(map[string]interface{})["id"].(string)
	if id == "" {
		t.Fatal("missing mapping id")
	}

	_, out = tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings?chain=fathalla", nil)
	if out["count"].(float64) != 1 {
		t.Fatalf("after save: %v", out)
	}

	if rec, _ = tmDo(t, mux, admin, "DELETE", "/api/v1/competitors/mappings/"+id, nil); rec.Code != http.StatusOK {
		t.Fatalf("delete: want 200, got %d", rec.Code)
	}
	_, out = tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings", nil)
	if out["count"].(float64) != 0 {
		t.Fatalf("after delete: %v", out)
	}
}

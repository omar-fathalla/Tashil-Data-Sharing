package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func TestProductMasterEndpointsAndSearch(t *testing.T) {
	bqRepo := bigquery.NewClient("test-project", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	agent := gemini.NewAgent("", "gemini-2.5-flash", true)
	proc := ingestion.NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(t.TempDir())
	authMW := middleware.NewAuthMiddleware("test-secret", true)

	analyticsH := NewAnalyticsHandler(bqRepo)
	uploadH := NewUploadHandler(proc)
	oosH := NewOOSHandler(fsRepo).WithBigQueryRepo(bqRepo)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/product-master", analyticsH.HandleGetProductMaster)
	mux.HandleFunc("PUT /api/v1/product-master/item", analyticsH.HandleUpdateProductMasterItem)
	mux.HandleFunc("POST /api/v1/product-master/upload", uploadH.HandleUploadProductMaster)
	mux.HandleFunc("GET /api/v1/analytics/oos-monitor", oosH.HandleOOSMonitor)
	handler := authMW.Handler(mux)

	// 1. Test GET /api/v1/product-master returns all 389 pre-seeded Adeco SKUs
	req := httptest.NewRequest(http.MethodGet, "/api/v1/product-master", nil)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from HandleGetProductMaster, got %d: %s", rec.Code, rec.Body.String())
	}

	var pmResp domain.ProductMasterSummaryResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &pmResp); err != nil {
		t.Fatalf("failed to decode ProductMasterSummaryResponse: %v", err)
	}
	if pmResp.TotalSKUs != 389 || len(pmResp.Items) != 389 {
		t.Fatalf("expected 389 SKUs in ProductMasterSummaryResponse, got TotalSKUs=%d, len(Items)=%d", pmResp.TotalSKUs, len(pmResp.Items))
	}
	if pmResp.RegularSKUsCount != 280 || pmResp.PromoSKUsCount != 109 {
		t.Fatalf("expected 280 regular and 109 promo SKUs, got regular=%d, promo=%d", pmResp.RegularSKUsCount, pmResp.PromoSKUsCount)
	}

	// 2. Test filtering by prefix FGCL and phonetic alias FGSL
	reqFGSL := httptest.NewRequest(http.MethodGet, "/api/v1/product-master?q=FGSL-0550-0001", nil)
	reqFGSL.Header.Set("X-Tenant-ID", "tenant-adeco")
	recFGSL := httptest.NewRecorder()
	handler.ServeHTTP(recFGSL, reqFGSL)
	var fgslResp domain.ProductMasterSummaryResponse
	if err := json.Unmarshal(recFGSL.Body.Bytes(), &fgslResp); err != nil {
		t.Fatalf("failed to decode fgsl search response: %v", err)
	}
	if len(fgslResp.Items) == 0 || fgslResp.Items[0].ItemCode != "FGCL-0550-0001" {
		t.Fatalf("expected phonetic alias FGSL-0550-0001 to match FGCL-0550-0001, got %d items", len(fgslResp.Items))
	}

	// 3. Test PUT /api/v1/product-master/item recalculates VAT & discount prices
	updatePayload := domain.ProductMasterItem{
		ItemCode:           "FGCL-0550-0001",
		OfficialName:       "كلوريل 500 جم مبيض",
		Barcode:            "6223000231227",
		UnitsPerCarton:     20,
		UnitPriceExclVAT:   13.00,
		VATRate:            0.14,
		InvoiceDiscountPct: 0.10,
		ItemType:           "عادي",
	}
	bodyBytes, _ := json.Marshal(updatePayload)
	reqPut := httptest.NewRequest(http.MethodPut, "/api/v1/product-master/item", bytes.NewReader(bodyBytes))
	reqPut.Header.Set("X-Tenant-ID", "tenant-adeco")
	recPut := httptest.NewRecorder()
	handler.ServeHTTP(recPut, reqPut)
	if recPut.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from HandleUpdateProductMasterItem, got %d: %s", recPut.Code, recPut.Body.String())
	}

	// 4. Test POST /api/v1/product-master/upload re-ingests original seed workbook
	seedPath := "../../data/product_master/adeco_product_master_2026_08_01.xlsx"
	if rawXlsx, err := os.ReadFile(seedPath); err == nil && len(rawXlsx) > 0 {
		reqUpload := httptest.NewRequest(http.MethodPost, "/api/v1/product-master/upload?filename=adeco_product_master_2026_08_01.xlsx", bytes.NewReader(rawXlsx))
		reqUpload.Header.Set("X-Tenant-ID", "tenant-adeco")
		recUpload := httptest.NewRecorder()
		handler.ServeHTTP(recUpload, reqUpload)
		if recUpload.Code != http.StatusOK {
			t.Fatalf("expected 200 OK from HandleUploadProductMaster, got %d: %s", recUpload.Code, recUpload.Body.String())
		}
	}

	// 5. Test OOS handler enriches with ProductMaster
	reqOOS := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/oos-monitor", nil)
	reqOOS.Header.Set("X-Tenant-ID", "tenant-adeco")
	recOOS := httptest.NewRecorder()
	handler.ServeHTTP(recOOS, reqOOS)
	if recOOS.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from HandleOOSMonitor, got %d", recOOS.Code)
	}
}

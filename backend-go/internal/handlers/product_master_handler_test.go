package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func setupIsolatedProductMasterDir(t *testing.T) string {
	t.Helper()
	tmpDir := t.TempDir()
	if raw, err := os.ReadFile("../../data/product_master/tenant-adeco.json"); err == nil && len(raw) > 0 {
		_ = os.WriteFile(filepath.Join(tmpDir, "tenant-adeco.json"), raw, 0o644)
	}
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", tmpDir)
	return tmpDir
}

func TestProductMasterEndpointsAndSearch(t *testing.T) {
	setupIsolatedProductMasterDir(t)
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

func TestProductMasterSheetUploadDiffAndDeleteRollback(t *testing.T) {
	setupIsolatedProductMasterDir(t)
	bqRepo := bigquery.NewClient("test-project", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	agent := gemini.NewAgent("", "gemini-2.5-flash", true)
	proc := ingestion.NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(t.TempDir())
	authMW := middleware.NewAuthMiddleware("test-secret", true)

	analyticsH := NewAnalyticsHandler(bqRepo)
	uploadH := NewUploadHandler(proc)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/product-master", analyticsH.HandleGetProductMaster)
	mux.HandleFunc("POST /api/v1/product-master/upload", uploadH.HandleUploadProductMaster)
	mux.HandleFunc("GET /api/v1/ingest/archive", uploadH.HandleListArchive)
	mux.HandleFunc("DELETE /api/v1/ingest/archive/{id}", uploadH.HandleDeleteArchive)
	handler := authMW.Handler(mux)

	csvSheet1 := "م,كود الصنف,اسم الصنف,الباركود,التعبئة,عدد الوحدات بالكرتونة,سعر الوحدة قبل الضريبة,قيمة الضريبة,سعر الوحدة شامل الضريبة,سعر الكرتونة شامل الضريبة\n" +
		"1,FGCL-0550-0001,كلوريل أبيض 550 جم,6223000231227,عبوة,20,10.00,14%,11.40,228.00\n" +
		"2,FGDG-0600-0002,فيبا أطباق 600 مل,6223000231228,عبوة,12,20.00,14%,22.80,273.60\n"

	reqUp1 := httptest.NewRequest(http.MethodPost, "/api/v1/product-master/upload?filename=sheet_v1.csv", bytes.NewReader([]byte(csvSheet1)))
	reqUp1.Header.Set("X-Tenant-ID", "tenant-rollback")
	recUp1 := httptest.NewRecorder()
	handler.ServeHTTP(recUp1, reqUp1)
	if recUp1.Code != http.StatusOK {
		t.Fatalf("expected 200 OK uploading sheet_v1.csv, got %d: %s", recUp1.Code, recUp1.Body.String())
	}

	var up1Res ingestion.IngestionResult
	_ = json.Unmarshal(recUp1.Body.Bytes(), &up1Res)
	if up1Res.ProductMasterSummary == nil || len(up1Res.ProductMasterSummary.Items) != 2 {
		t.Fatalf("expected 2 items in sheet_v1.csv summary")
	}
	if up1Res.ProductMasterSummary.Items[0].PackagingType != "عبوة" {
		t.Fatalf("expected PackagingType='عبوة' on 10-column CSV, got %q", up1Res.ProductMasterSummary.Items[0].PackagingType)
	}

	// Upload Sheet 2 with price increase on FGCL-0550-0001 (11.40 -> 15.96), a new SKU FGDW-0900-0003,
	// and a new promo SKU PRCL-0550-0099 sharing barcode 6223000231227 with FGCL-0550-0001
	csvSheet2 := "م,كود الصنف,اسم الصنف,الباركود,التعبئة,عدد الوحدات بالكرتونة,سعر الوحدة قبل الضريبة,قيمة الضريبة,سعر الوحدة شامل الضريبة,سعر الكرتونة شامل الضريبة\n" +
		"1,FGCL-0550-0001,كلوريل أبيض 550 جم,6223000231227,عبوة,20,14.00,14%,15.96,319.20\n" +
		"2,FGDG-0600-0002,فيبا أطباق 600 مل,6223000231228,عبوة,12,20.00,14%,22.80,273.60\n" +
		"3,FGDW-0900-0003,أقراص غسالات أطباق جديد,6223000231229,علبة,6,100.00,14%,114.00,684.00\n" +
		"4,PRCL-0550-0099,* عرض كلوريل أبيض 550 جم 2+1,6223000231227,شرنك,6,28.00,14%,31.92,191.52\n"

	reqUp2 := httptest.NewRequest(http.MethodPost, "/api/v1/product-master/upload?filename=sheet_v2.csv", bytes.NewReader([]byte(csvSheet2)))
	reqUp2.Header.Set("X-Tenant-ID", "tenant-rollback")
	recUp2 := httptest.NewRecorder()
	handler.ServeHTTP(recUp2, reqUp2)
	if recUp2.Code != http.StatusOK {
		t.Fatalf("expected 200 OK uploading sheet_v2.csv, got %d: %s", recUp2.Code, recUp2.Body.String())
	}

	var up2Res ingestion.IngestionResult
	if err := json.Unmarshal(recUp2.Body.Bytes(), &up2Res); err != nil {
		t.Fatalf("failed to decode upload 2 response: %v", err)
	}
	if up2Res.ProductMasterSummary == nil || up2Res.ProductMasterSummary.DiffSummary == nil {
		t.Fatalf("expected ProductMasterSummary with DiffSummary in upload response")
	}
	if up2Res.ProductMasterSummary.DiffSummary.PriceIncreasedCount != 1 || up2Res.ProductMasterSummary.DiffSummary.NewSKUsCount != 2 {
		t.Fatalf("expected 1 price increase and 2 new SKUs in DiffSummary, got %+v", up2Res.ProductMasterSummary.DiffSummary)
	}

	// Verify GET /api/v1/product-master?price_change=up returns only FGCL-0550-0001
	reqFilterUp := httptest.NewRequest(http.MethodGet, "/api/v1/product-master?price_change=up", nil)
	reqFilterUp.Header.Set("X-Tenant-ID", "tenant-rollback")
	recFilterUp := httptest.NewRecorder()
	handler.ServeHTTP(recFilterUp, reqFilterUp)
	var upFilterResp domain.ProductMasterSummaryResponse
	_ = json.Unmarshal(recFilterUp.Body.Bytes(), &upFilterResp)
	if len(upFilterResp.Items) != 1 || upFilterResp.Items[0].ItemCode != "FGCL-0550-0001" {
		t.Fatalf("expected price_change=up to return FGCL-0550-0001, got %+v", upFilterResp.Items)
	}

	// Delete sheet_v2.csv from archive and verify rollback to sheet_v1.csv (2 SKUs, price back to 11.40)
	reqDel := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+up2Res.ArchiveID, nil)
	reqDel.Header.Set("X-Tenant-ID", "tenant-rollback")
	// Company manager (vendor_admin) may delete archives inside its tenant.
	mgrTok, err := authMW.GenerateToken(domain.UserClaims{UserID: "va", TenantID: "tenant-rollback", Role: domain.RoleVendorAdmin}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	reqDel.Header.Set("Authorization", "Bearer "+mgrTok)
	recDel := httptest.NewRecorder()
	handler.ServeHTTP(recDel, reqDel)
	if recDel.Code != http.StatusOK {
		t.Fatalf("expected 200 OK deleting sheet_v2 archive, got %d: %s", recDel.Code, recDel.Body.String())
	}

	reqAfterRollback := httptest.NewRequest(http.MethodGet, "/api/v1/product-master", nil)
	reqAfterRollback.Header.Set("X-Tenant-ID", "tenant-rollback")
	recAfterRollback := httptest.NewRecorder()
	handler.ServeHTTP(recAfterRollback, reqAfterRollback)
	var rbResp domain.ProductMasterSummaryResponse
	_ = json.Unmarshal(recAfterRollback.Body.Bytes(), &rbResp)
	if rbResp.TotalSKUs != 2 || len(rbResp.Items) != 2 {
		t.Fatalf("expected rollback to 2 SKUs from sheet_v1.csv, got TotalSKUs=%d", rbResp.TotalSKUs)
	}
	if rbResp.Items[0].UnitPriceInclVAT != 11.40 {
		t.Fatalf("expected FGCL-0550-0001 price to roll back to 11.40, got %.2f", rbResp.Items[0].UnitPriceInclVAT)
	}

	// Test uploading an updated version with the SAME filename (sheet_v1.csv) and rolling back
	csvSheet1Updated := "م,كود الصنف,اسم الصنف,الباركود,التعبئة,عدد الوحدات بالكرتونة,سعر الوحدة قبل الضريبة,قيمة الضريبة,سعر الوحدة شامل الضريبة,سعر الكرتونة شامل الضريبة\n" +
		"1,FGCL-0550-0001,كلوريل أبيض 550 جم,6223000231227,عبوة,20,10.00,14%,11.40,228.00\n" +
		"2,FGDG-0600-0002,فيبا أطباق 600 مل,6223000231228,عبوة,12,15.00,14%,17.10,205.20\n"

	reqUpSameName := httptest.NewRequest(http.MethodPost, "/api/v1/product-master/upload?filename=sheet_v1.csv", bytes.NewReader([]byte(csvSheet1Updated)))
	reqUpSameName.Header.Set("X-Tenant-ID", "tenant-rollback")
	recUpSameName := httptest.NewRecorder()
	handler.ServeHTTP(recUpSameName, reqUpSameName)
	var upSameRes ingestion.IngestionResult
	_ = json.Unmarshal(recUpSameName.Body.Bytes(), &upSameRes)
	if upSameRes.ProductMasterSummary == nil || upSameRes.ProductMasterSummary.DiffSummary == nil || upSameRes.ProductMasterSummary.DiffSummary.PriceDecreasedCount != 1 {
		t.Fatalf("expected 1 price decrease when uploading modified sheet_v1.csv, got %+v", upSameRes.ProductMasterSummary)
	}

	// Delete the newer sheet_v1.csv and verify the original sheet_v1.csv remains active and visible in archive
	reqDelSame := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+upSameRes.ArchiveID, nil)
	reqDelSame.Header.Set("Authorization", "Bearer "+mgrTok)
	reqDelSame.Header.Set("X-Tenant-ID", "tenant-rollback")
	recDelSame := httptest.NewRecorder()
	handler.ServeHTTP(recDelSame, reqDelSame)
	if recDelSame.Code != http.StatusOK {
		t.Fatalf("expected 200 OK deleting newer sheet_v1.csv, got %d", recDelSame.Code)
	}

	reqListArch := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive?type=product_master", nil)
	reqListArch.Header.Set("X-Tenant-ID", "tenant-rollback")
	recListArch := httptest.NewRecorder()
	handler.ServeHTTP(recListArch, reqListArch)
	var archListResp ingestion.ArchiveListResponse
	_ = json.Unmarshal(recListArch.Body.Bytes(), &archListResp)
	if len(archListResp.Files) != 1 || archListResp.Files[0].ID != up1Res.ArchiveID {
		t.Fatalf("expected original sheet_v1.csv to remain in archive after deleting newer same-named version, got %+v", archListResp.Files)
	}

	// Test baseline restoration on tenant-adeco when custom uploaded sheet is deleted
	reqUpCustomAdeco := httptest.NewRequest(http.MethodPost, "/api/v1/product-master/upload?filename=custom_adeco.csv", bytes.NewReader([]byte(csvSheet1)))
	reqUpCustomAdeco.Header.Set("X-Tenant-ID", "tenant-adeco")
	recUpCustomAdeco := httptest.NewRecorder()
	handler.ServeHTTP(recUpCustomAdeco, reqUpCustomAdeco)
	var upCustomAdecoRes ingestion.IngestionResult
	_ = json.Unmarshal(recUpCustomAdeco.Body.Bytes(), &upCustomAdecoRes)

	adecoMgrTok, err := authMW.GenerateToken(domain.UserClaims{UserID: "va-adeco", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	reqDelCustomAdeco := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+upCustomAdecoRes.ArchiveID, nil)
	reqDelCustomAdeco.Header.Set("Authorization", "Bearer "+adecoMgrTok)
	reqDelCustomAdeco.Header.Set("X-Tenant-ID", "tenant-adeco")
	recDelCustomAdeco := httptest.NewRecorder()
	handler.ServeHTTP(recDelCustomAdeco, reqDelCustomAdeco)
	if recDelCustomAdeco.Code != http.StatusOK {
		t.Fatalf("expected 200 OK deleting custom_adeco.csv, got %d", recDelCustomAdeco.Code)
	}

	reqAdecoRestored := httptest.NewRequest(http.MethodGet, "/api/v1/product-master", nil)
	reqAdecoRestored.Header.Set("X-Tenant-ID", "tenant-adeco")
	recAdecoRestored := httptest.NewRecorder()
	handler.ServeHTTP(recAdecoRestored, reqAdecoRestored)
	var adecoRestoredResp domain.ProductMasterSummaryResponse
	_ = json.Unmarshal(recAdecoRestored.Body.Bytes(), &adecoRestoredResp)
	if adecoRestoredResp.TotalSKUs != 389 {
		t.Fatalf("expected tenant-adeco to roll back to 389 baseline SKUs after deleting custom_adeco.csv, got %d", adecoRestoredResp.TotalSKUs)
	}
}


package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func TestCPFRAndSellInPlanEndToEnd(t *testing.T) {
	cleanBytes, err := os.ReadFile(DefaultAdcoSellInCleanPath)
	if err != nil {
		t.Skipf("Clean sell-in plan workbook not present at %s: %v", DefaultAdcoSellInCleanPath, err)
	}

	if !gemini.IsSellInPlanWorkbook(cleanBytes) {
		t.Fatalf("expected IsSellInPlanWorkbook to return true for clean workbook")
	}

	bqRepo := bigquery.NewClient("tashil-test", "retail", true)
	_ = bqRepo.ClearTenantData(context.Background(), "all")
	fsRepo := firestore.NewClient("tashil-db", true)
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	proc := ingestion.NewProcessor(agent, bqRepo, fsRepo)

	res, err := proc.ProcessSellInPlan(context.Background(), "tenant-adeco", "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", cleanBytes, false, "fathalla")
	if err != nil {
		t.Fatalf("ProcessSellInPlan failed: %v", err)
	}
	if res.ValidRows < 7800 {
		t.Fatalf("expected >= 7800 valid sell-in rows, got %d", res.ValidRows)
	}

	analyticsHandler := NewAnalyticsHandler(bqRepo)
	req := authenticatedRequest(http.MethodGet, "/api/v1/analytics/cpfr?lead_time_days=4&safety_stock_days=7", "tenant-adeco")
	w := httptest.NewRecorder()
	analyticsHandler.HandleCPFRDashboard(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 from /api/v1/analytics/cpfr, got %d: %s", w.Code, w.Body.String())
	}

	var payload domain.CPFRDashboardPayload
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to decode CPFRDashboardPayload: %v", err)
	}

	// Verify cumulative Sell-In and Remaining Stock when no Sell-Out is uploaded yet
	if payload.Jan2026SellInEGP < 10000000 {
		t.Errorf("expected Jan2026SellInEGP >= 10,000,000, got %.2f", payload.Jan2026SellInEGP)
	}
	if payload.Jan2026SellOutEGP != 0 || payload.Jan2026SellThroughPct != 0 {
		t.Errorf("expected 0 Sell-Out and 0%% Sell-Through when no Sell-Out file is uploaded, got %.2f (%.2f%%)", payload.Jan2026SellOutEGP, payload.Jan2026SellThroughPct)
	}
	if len(payload.MonthlyReconciliation) != 10 {
		t.Errorf("expected 10 months of reconciliation (Jan-Oct 2026), got %d", len(payload.MonthlyReconciliation))
	}
	if len(payload.InventoryAndPOItems) == 0 {
		t.Errorf("expected non-empty InventoryAndPOItems with Suggested PO")
	}
	if len(payload.SalesRepScorecards) < 14 {
		t.Errorf("expected at least 14 sales rep scorecards, got %d", len(payload.SalesRepScorecards))
	}
	if payload.PromoAndReturns.PromoRecordsCount != 813 || payload.PromoAndReturns.ReturnRecordsCount != 605 {
		t.Errorf("expected 813 promo records and 605 return records, got %d promo and %d return",
			payload.PromoAndReturns.PromoRecordsCount, payload.PromoAndReturns.ReturnRecordsCount)
	}

	// Verify Sell-In file is listed in Sell-In archive and can be deleted cleanly
	sellInArchive := proc.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in")
	if sellInArchive.TotalCount != 1 {
		t.Errorf("expected 1 sell-in archived file, got %d", sellInArchive.TotalCount)
	}
	if _, err := proc.DeleteArchivedFile(context.Background(), "tenant-adeco", res.ArchiveID); err != nil {
		t.Fatalf("DeleteArchivedFile for sell-in failed: %v", err)
	}
	afterDelArchive := proc.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in")
	if afterDelArchive.TotalCount != 0 {
		t.Errorf("expected 0 sell-in archived files after delete, got %d", afterDelArchive.TotalCount)
	}
}

func TestComprehensiveSellInTargetBreakdown(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())

	bqRepo := bigquery.NewClient("tashil-test", "retail", true)
	cleanBytes, err := os.ReadFile(DefaultAdcoSellInCleanPath)
	if err == nil && len(cleanBytes) > 0 {
		fsRepo := firestore.NewClient("tashil-db", true)
		agent := gemini.NewAgent("", "gemini-3.8-flash", true)
		proc := ingestion.NewProcessor(agent, bqRepo, fsRepo)
		_, _ = proc.ProcessSellInPlan(context.Background(), "tenant-adeco", "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", cleanBytes, false, "fathalla")
	}

	// User enters only Chain + Year + Target Revenue (leaving Branch, Category, and Units open)
	_, err = bqRepo.UpsertTarget(context.Background(), "tenant-adeco", domain.TargetRecord{
		TargetType:       "sell_in",
		RetailerChain:    "fathalla",
		Year:             2026,
		Month:            0, // Full year
		TargetRevenueEGP: 150000000,
	})
	if err != nil {
		t.Fatalf("UpsertTarget failed: %v", err)
	}

	summary, err := bqRepo.GetTargetsSummary(context.Background(), "tenant-adeco", "sell_in", "fathalla", 2026)
	if err != nil {
		t.Fatalf("GetTargetsSummary failed: %v", err)
	}
	if len(summary.Items) != 1 {
		t.Fatalf("expected 1 target item, got %d", len(summary.Items))
	}

	item := summary.Items[0]
	if item.TargetUnits <= 0 || item.TargetWeightTons <= 0 {
		t.Errorf("expected auto-calculated TargetUnits and TargetWeightTons > 0, got units=%.2f tons=%.2f", item.TargetUnits, item.TargetWeightTons)
	}
	if len(item.Branches) != 34 {
		t.Errorf("expected 34 Fathalla branches in breakdown, got %d", len(item.Branches))
	}
	if len(item.MonthlyPhasing) != 12 {
		t.Errorf("expected 12 months in annual phasing, got %d", len(item.MonthlyPhasing))
	}
	if len(item.SalesRepQuotas) == 0 {
		t.Errorf("expected non-empty SalesRepQuotas")
	}

	var sumBranchRev, sumBranchUnits float64
	for _, b := range item.Branches {
		sumBranchRev += b.TargetRevenueEGP
		sumBranchUnits += b.TargetUnits
		if len(b.SKUs) == 0 && len(item.ChainSKUTotals) > 0 {
			t.Errorf("expected SKUs inside branch %s", b.BranchName)
		}
	}
	if diff := sumBranchRev - item.TargetRevenueEGP; diff > 1.0 || diff < -1.0 {
		t.Errorf("expected sum of branch targets (%.2f) to equal chain target (%.2f)", sumBranchRev, item.TargetRevenueEGP)
	}
	if diff := sumBranchUnits - item.TargetUnits; diff > 1.0 || diff < -1.0 {
		t.Errorf("expected sum of branch target units (%.2f) to equal chain target units (%.2f)", sumBranchUnits, item.TargetUnits)
	}

	// Verify Product Master 3-way linkage on ChainSKUTotals and Sell-In Explorer Waterfall
	matchedTargetSkus := 0
	for _, s := range item.ChainSKUTotals {
		if s.ItemCode != "" {
			matchedTargetSkus++
		}
		if s.UnitsPerCarton <= 0 {
			t.Errorf("expected UnitsPerCarton > 0 for SKU %s", s.SKUName)
		}
	}
	if len(item.ChainSKUTotals) > 0 && matchedTargetSkus < 130 {
		t.Errorf("expected >= 130 Sell-In SKUs matched to Product Master ItemCode, got %d / %d", matchedTargetSkus, len(item.ChainSKUTotals))
	}

	analyticsHandler := NewAnalyticsHandler(bqRepo)
	reqRecs := authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-records?chain=fathalla&year=2026&limit=50", "tenant-adeco")
	wRecs := httptest.NewRecorder()
	analyticsHandler.HandleSellInRecords(wRecs, reqRecs)
	if wRecs.Code != http.StatusOK {
		t.Fatalf("expected 200 from /api/v1/analytics/sell-in-records, got %d", wRecs.Code)
	}
	var recResp PaginatedSellInRecordsResponse
	if err := json.Unmarshal(wRecs.Body.Bytes(), &recResp); err != nil {
		t.Fatalf("failed to decode PaginatedSellInRecordsResponse: %v", err)
	}
	if recResp.TotalGrossInclVATEGP <= recResp.TotalValueEGP || recResp.TotalVAT14EGP <= 0 || recResp.TotalUnitsPieces <= 0 {
		t.Errorf("expected populated Tax & Discount Waterfall in Sell-In records response, got Net=%.2f VAT=%.2f Gross=%.2f Pieces=%d MatchedSKUs=%d",
			recResp.TotalValueEGP, recResp.TotalVAT14EGP, recResp.TotalGrossInclVATEGP, recResp.TotalUnitsPieces, recResp.MatchedCatalogSKUsCount)
	}
}

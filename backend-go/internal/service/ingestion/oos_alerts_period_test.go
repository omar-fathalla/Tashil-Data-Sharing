package ingestion

import (
	"context"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func TestShouldReplaceOOSAlerts(t *testing.T) {
	cases := []struct {
		name   string
		upload string
		stored string
		want   bool
	}{
		{"first upload", "2026-03", "", true},
		{"newer than stored", "2026-03", "2025-04", true},
		{"same as stored", "2026-03", "2026-03", true},
		{"older than stored", "2025-04", "2026-03", false},
		{"older month same year", "2026-01", "2026-10", false},
		{"unknown upload keeps stored", "", "2026-03", false},
		{"both empty", "", "", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := shouldReplaceOOSAlerts(tc.upload, tc.stored); got != tc.want {
				t.Fatalf("shouldReplaceOOSAlerts(%q,%q)=%v want %v", tc.upload, tc.stored, got, tc.want)
			}
		})
	}
}

func TestMaxPeriodYM(t *testing.T) {
	facts := []domain.SellOutFact{
		{RetailerChain: "fathalla", TransactionDate: "2025-01-15"},
		{RetailerChain: "fathalla", TransactionDate: "2025-04-30"},
		{RetailerChain: "gomla", TransactionDate: "2026-10-01"},
		{RetailerChain: "fathalla", TransactionDate: "bad"},
	}
	if got := maxPeriodYM(facts, "fathalla"); got != "2025-04" {
		t.Fatalf("fathalla max=%q want 2025-04", got)
	}
	if got := maxPeriodYM(facts, "gomla"); got != "2026-10" {
		t.Fatalf("gomla max=%q want 2026-10", got)
	}
	if got := maxPeriodYM(facts, ""); got != "2026-10" {
		t.Fatalf("all-chains max=%q want 2026-10", got)
	}
}

func fact(tenant, chain, date, barcode string, rev float64) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID:         "fact_" + barcode + "_" + date,
		TenantID:         tenant,
		RetailerChain:    chain,
		StoreID:          chain + "_smouha",
		StoreName:        "سموحة",
		Barcode:          barcode,
		SKUName:          "SKU " + barcode,
		Supplier:         "",
		IsOwnBrand:       true,
		QuantitySold:     10,
		NetRevenue:       rev,
		TransactionDate:  date,
		IngestionBatchID: "batch_test",
	}
}

func alert(id, chain, barcode string) domain.OOSAlert {
	return domain.OOSAlert{
		AlertID:                id,
		RetailerChain:          chain,
		StoreID:                chain + "_smouha",
		StoreName:              "سموحة",
		Barcode:                barcode,
		SKUName:                "SKU " + barcode,
		Category:               "منظفات",
		EstimatedLostDailyCost: 200,
		ConsecutiveDaysOOS:     4,
		Severity:               "high",
		DetectedAt:             time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC),
	}
}

func injectWideMatrixStaged(p *Processor, tenant, batchID, filename, chain string, facts []domain.SellOutFact, alerts []domain.OOSAlert) {
	p.stagedMu.Lock()
	defer p.stagedMu.Unlock()
	p.staged[batchID] = &StagedUpload{
		BatchID:      batchID,
		TenantID:     tenant,
		Filename:     filename,
		TargetChain:  chain,
		ValidFacts:   facts,
		OOSAlerts:    alerts,
		IsWideMatrix: true,
		CreatedAt:    time.Now(),
		Result: &IngestionResult{
			BatchID:          batchID,
			Filename:         filename,
			RetailerDetected: chain,
			TotalRows:        len(facts),
			ValidRows:        len(facts),
			TotalRevenue:     1,
			TotalQuantity:    1,
			ConfidenceScore:  1,
			IsStaged:         true,
		},
	}
}

// TestOlderPeriodWideMatrixCommitKeepsNewerOOSAlerts covers the bug: committing a
// historical Sell-Out wide-matrix file (e.g. 2025 out.xlsx) must not replace OOS
// alerts that came from a newer period already stored for the tenant/chain.
func TestOlderPeriodWideMatrixCommitKeepsNewerOOSAlerts(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	p := NewProcessor(agent, bqRepo, fsRepo)

	tenant := "tenant-oos-period-empty"
	chain := "fathalla"
	_ = bqRepo.ClearTenantData(ctx, tenant)
	_ = fsRepo.ClearTenantData(ctx, tenant)

	newerAlerts := []domain.OOSAlert{
		alert("oos_2026_001", chain, "6223000260001"),
		alert("oos_2026_002", chain, "6223000260002"),
	}
	injectWideMatrixStaged(p, tenant, "batch_2026", "out26.xlsx", chain,
		[]domain.SellOutFact{
			fact(tenant, chain, "2026-03-15", "6223000260001", 5000),
			fact(tenant, chain, "2026-02-15", "6223000260001", 4000),
		},
		newerAlerts,
	)
	if _, err := p.CommitStagedUpload(ctx, tenant, "batch_2026", chain); err != nil {
		t.Fatalf("commit newer period: %v", err)
	}

	got, err := fsRepo.GetOOSAlerts(ctx, tenant)
	if err != nil {
		t.Fatalf("GetOOSAlerts after newer commit: %v", err)
	}
	if len(got) != 2 || got[0].AlertID != "oos_2026_001" {
		t.Fatalf("expected 2026 alerts after first commit, got %+v", got)
	}

	staleAlerts := []domain.OOSAlert{
		alert("oos_2025_stale", chain, "6223000250099"),
	}
	injectWideMatrixStaged(p, tenant, "batch_2025", "2025 out.xlsx", chain,
		[]domain.SellOutFact{
			fact(tenant, chain, "2025-01-15", "6223000250001", 1000),
			fact(tenant, chain, "2025-04-15", "6223000250001", 1200),
		},
		staleAlerts,
	)
	if _, err := p.CommitStagedUpload(ctx, tenant, "batch_2025", chain); err != nil {
		t.Fatalf("commit older period: %v", err)
	}

	got, err = fsRepo.GetOOSAlerts(ctx, tenant)
	if err != nil {
		t.Fatalf("GetOOSAlerts after older commit: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("older upload must leave newer alerts intact, got %d alerts: %+v", len(got), got)
	}
	for _, a := range got {
		if a.AlertID == "oos_2025_stale" {
			t.Fatalf("stale 2025 alert replaced current alerts: %+v", got)
		}
		if !stringsHasPrefix2026(a.AlertID) {
			t.Fatalf("expected 2026 alert ids preserved, got %q", a.AlertID)
		}
	}

	// Facts from both periods must still coexist (natural period merge unchanged).
	recs, total, err := bqRepo.GetSellOutRecords(ctx, tenant, bigquery.RecordFilter{RetailerChain: chain, Limit: 50})
	if err != nil {
		t.Fatalf("GetSellOutRecords: %v", err)
	}
	if total < 4 {
		t.Fatalf("expected both 2025 and 2026 facts kept, got total=%d recs=%d", total, len(recs))
	}
}

func stringsHasPrefix2026(id string) bool {
	return len(id) >= 8 && id[:8] == "oos_2026"
}

// TestEqualOrNewerPeriodWideMatrixCommitReplacesOOSAlerts ensures re-uploading the
// current (or a newer) period still refreshes alerts.
func TestEqualOrNewerPeriodWideMatrixCommitReplacesOOSAlerts(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	p := NewProcessor(agent, bqRepo, fsRepo)

	tenant := "tenant-oos-period-refresh-empty"
	chain := "fathalla"
	_ = bqRepo.ClearTenantData(ctx, tenant)
	_ = fsRepo.ClearTenantData(ctx, tenant)

	injectWideMatrixStaged(p, tenant, "batch_a", "out26.xlsx", chain,
		[]domain.SellOutFact{fact(tenant, chain, "2026-03-15", "6223000260001", 5000)},
		[]domain.OOSAlert{alert("oos_old", chain, "6223000260001")},
	)
	if _, err := p.CommitStagedUpload(ctx, tenant, "batch_a", chain); err != nil {
		t.Fatalf("first commit: %v", err)
	}

	injectWideMatrixStaged(p, tenant, "batch_b", "out26-refresh.xlsx", chain,
		[]domain.SellOutFact{fact(tenant, chain, "2026-03-20", "6223000260001", 5500)},
		[]domain.OOSAlert{alert("oos_refreshed", chain, "6223000260099")},
	)
	if _, err := p.CommitStagedUpload(ctx, tenant, "batch_b", chain); err != nil {
		t.Fatalf("same-period refresh commit: %v", err)
	}

	got, err := fsRepo.GetOOSAlerts(ctx, tenant)
	if err != nil {
		t.Fatalf("GetOOSAlerts: %v", err)
	}
	if len(got) != 1 || got[0].AlertID != "oos_refreshed" {
		t.Fatalf("same/newer period must replace alerts, got %+v", got)
	}
}

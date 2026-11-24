package bigquery

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const planFile = "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx"

// planRow is a row of the Plan workbook (clean 30-column layout: the branch column holds the Regional placeholder).
func planRow(id, code string, cases, value float64) domain.SellInRecord {
	r := realSellIn(id, "مجمع الإقليم (Regional)", "ALX", "الاسكندرية", code, cases, value)
	r.SourceFilename = planFile
	r.SourceKind = domain.SellInSourceKindPlan
	return r
}

func realRow(id, branchCode, code string, cases, value float64) domain.SellInRecord {
	r := realSellIn(id, branchCode, "ALX", "الاسكندرية", code, cases, value)
	r.SourceFilename = "in26.xlsx"
	return r
}

// The Plan workbook is not Sell-In actuals: its rows never reach the Sell-In store, so the target's
// achieved header and every branch/SKU line stay exactly what the real Sell-In files say.
func TestPlanRowsAreNotSellInActuals(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	ctx := context.Background()

	if err := c.SetSellInRecords(ctx, dsiTenant, planFile, []domain.SellInRecord{
		planRow("pl1", "FGCL-0001", 5000, 600000),
		planRow("pl2", "FGCL-0003", 2000, 240000),
	}); err != nil {
		t.Fatal(err)
	}
	if got := c.SellInRecordsSnapshot(dsiTenant); len(got) != 0 {
		t.Fatalf("Plan rows must not be Sell-In records, got %d", len(got))
	}
	it := derivedSummary(t, c).Items[0]
	if it.HasActuals || it.ActualUnits != 0 || it.ActualRevenueEGP != 0 {
		t.Fatalf("a Plan upload alone gives no Sell-In achieved: %+v", it)
	}
	if plan := c.SellInPlanRecordsSnapshot(dsiTenant); len(plan) != 2 {
		t.Fatalf("Plan rows stay available to the Brand Master, got %d", len(plan))
	}

	if err := c.SetSellInRecords(ctx, dsiTenant, "in26.xlsx", []domain.SellInRecord{
		realRow("r1", "311350147", "FGCL-0001", 10, 1200),
		realRow("r2", "311350147", "FGCL-0003", 1, 120),
	}); err != nil {
		t.Fatal(err)
	}
	it = derivedSummary(t, c).Items[0]
	if !it.HasActuals || !near(it.ActualUnits, 126) || !near(it.ActualRevenueEGP, 1320) {
		t.Fatalf("achieved = real Sell-In only (120+6 pieces, 1320 EGP), got units=%v rev=%v", it.ActualUnits, it.ActualRevenueEGP)
	}
	smouha := branchByCode(it.Branches, "fat_smouha")
	if smouha == nil || !near(smouha.ActualUnits, 126) {
		t.Fatalf("real rows are attributed to their branch (ERP code 311350147 = سموحة): %+v", smouha)
	}
	if none := branchByCode(it.Branches, DerivedUnassignedBranchCode); none != nil {
		t.Fatalf("no Plan row may create or fill «غير محدد الفرع»: %+v", none)
	}
	assertBranchesAddUp(t, it)
}

// A Plan upload and a real upload for the same chain and month never replace each other.
func TestPlanUploadDoesNotDisplaceRealRows(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	ctx := context.Background()
	if err := c.SetSellInRecords(ctx, dsiTenant, "in26.xlsx", []domain.SellInRecord{realRow("r1", "311350147", "FGCL-0001", 10, 1200)}); err != nil {
		t.Fatal(err)
	}
	if err := c.SetSellInRecords(ctx, dsiTenant, planFile, []domain.SellInRecord{planRow("pl1", "FGCL-0001", 5000, 600000)}); err != nil {
		t.Fatal(err)
	}
	if got := c.SellInRecordsSnapshot(dsiTenant); len(got) != 1 || got[0].RecordID != "r1" {
		t.Fatalf("the real row must survive a Plan upload for the same month: %+v", got)
	}
	if it := derivedSummary(t, c).Items[0]; !near(it.ActualUnits, 120) {
		t.Fatalf("achieved stays 120 pieces, got %v", it.ActualUnits)
	}
	if err := c.SetSellInRecords(ctx, dsiTenant, "in26.xlsx", []domain.SellInRecord{realRow("r2", "311350148", "FGCL-0001", 2, 240)}); err != nil {
		t.Fatal(err)
	}
	if plan := c.SellInPlanRecordsSnapshot(dsiTenant); len(plan) != 1 {
		t.Fatalf("a real upload must not remove the Plan rows: %d", len(plan))
	}
}

// The marker alone decides: a Plan file name excludes its rows even when the parser did not stamp them
// (rows stored before the stamp existed), and it never looks at values.
func TestPlanRowsAreRecognisedByFileNameOnly(t *testing.T) {
	c := newBranchAttributionFixture(t)
	legacy := realSellIn("old", "مجمع الإقليم (Regional)", "ALX", "الاسكندرية", "FGCL-0001", 7, 840)
	legacy.SourceFilename = planFile
	c.ReplaceSellInRecords(dsiTenant, []domain.SellInRecord{legacy, realRow("r1", "", "FGCL-0001", 1, 120)})
	got := c.SellInRecordsSnapshot(dsiTenant)
	if len(got) != 1 || got[0].RecordID != "r1" {
		t.Fatalf("legacy Plan row loaded from the durable store must be diverted, got %+v", got)
	}
	if plan := c.SellInPlanRecordsSnapshot(dsiTenant); len(plan) != 1 || plan[0].RecordID != "old" || plan[0].SourceKind != domain.SellInSourceKindPlan {
		t.Fatalf("diverted Plan row: %+v", plan)
	}

	// Same values in a file that is not a Plan stay Sell-In.
	same := realSellIn("same", "مجمع الإقليم (Regional)", "ALX", "الاسكندرية", "FGCL-0001", 7, 840)
	same.SourceFilename = "SOP_Sell_In_2026.xlsx"
	c.ReplaceSellInRecords(dsiTenant, []domain.SellInRecord{same})
	if got := c.SellInRecordsSnapshot(dsiTenant); len(got) != 1 {
		t.Fatalf("a real Sell-In file is never excluded by its values: %+v", got)
	}
}

// A snapshot written before the split may hold Plan rows among the Sell-In rows; loading it diverts them.
func TestSnapshotImportDivertsLegacyPlanRows(t *testing.T) {
	src := newBranchAttributionFixture(t)
	src.mu.Lock()
	legacy := realSellIn("old", "مجمع الإقليم (Regional)", "ALX", "الاسكندرية", "FGCL-0001", 7, 840)
	legacy.SourceFilename = planFile
	src.sellInRecords[dsiTenant] = []domain.SellInRecord{legacy, realRow("r1", "311350147", "FGCL-0001", 1, 120)}
	src.mu.Unlock()
	raw, err := src.ExportSnapshot()
	if err != nil {
		t.Fatal(err)
	}

	dst := newBranchAttributionFixture(t)
	if err := dst.ImportSnapshot(raw); err != nil {
		t.Fatal(err)
	}
	if got := dst.SellInRecordsSnapshot(dsiTenant); len(got) != 1 || got[0].RecordID != "r1" {
		t.Fatalf("restored Sell-In rows exclude the Plan row: %+v", got)
	}
	if plan := dst.SellInPlanRecordsSnapshot(dsiTenant); len(plan) != 1 {
		t.Fatalf("restored Plan rows: %+v", plan)
	}
	raw2, err := dst.ExportSnapshot()
	if err != nil {
		t.Fatal(err)
	}
	third := newBranchAttributionFixture(t)
	if err := third.ImportSnapshot(raw2); err != nil {
		t.Fatal(err)
	}
	if len(third.SellInPlanRecordsSnapshot(dsiTenant)) != 1 || len(third.SellInRecordsSnapshot(dsiTenant)) != 1 {
		t.Fatal("Plan rows survive a snapshot round trip in their own store")
	}
}

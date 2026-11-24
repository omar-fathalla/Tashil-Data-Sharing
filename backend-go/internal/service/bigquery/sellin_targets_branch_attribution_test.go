package bigquery

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const dsiLegalEntity = "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م"

// newBranchAttributionFixture mirrors production keys: Sell-Out stores are store ids (fat_smouha …) with
// display names, while Sell-In plan rows name the chain's legal entity with an ERP branch code
// (311350147 = سموحة in the Fathalla catalog) or the regional bucket.
func newBranchAttributionFixture(t *testing.T) *Client {
	t.Helper()
	c := newDerivedFixture(t)
	c.mu.Lock()
	c.records = nil
	c.mu.Unlock()
	if err := c.InsertSellOutFacts(context.Background(), []domain.SellOutFact{
		dsiFact("b1", "fat_smouha", "فرع فتح الله - سموحة", "FGCL-0001", "صنف 1", "2025-03-10", 60, 600),
		dsiFact("b2", "fat_smouha", "فرع فتح الله - سموحة", "FGCL-0003", "صنف 3", "2025-03-11", 20, 400),
		dsiFact("b3", "fat_stanley", "فرع فتح الله - ستانلى", "FGCL-0001", "صنف 1", "2025-03-12", 20, 200),
		dsiFact("b4", "fat_tanta", "فرع فتح الله - طنطا", "FGCL-0001", "صنف 1", "2025-03-13", 20, 200),
	}); err != nil {
		t.Fatal(err)
	}
	return c
}

func planSellIn(id, branchCode, region, gov, code string, cases, value float64) domain.SellInRecord {
	return domain.SellInRecord{
		RecordID: id, TenantID: dsiTenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
		RegionCode: region, Governorate: gov, CustomerName: dsiLegalEntity, CustomerBranchCode: branchCode,
		ItemCode: code, NetQtyCases: cases, NetValueEGP: value,
	}
}

func branchByCode(rows []domain.TargetBranchBreakdown, code string) *domain.TargetBranchBreakdown {
	for i := range rows {
		if rows[i].BranchCode == code {
			return &rows[i]
		}
	}
	return nil
}

// Regression: the branch drill-down showed «—» for every branch although the target had 1.62M achieved
// pieces, because Sell-In rows (ERP codes / regional buckets under the legal-entity name) never matched
// a Sell-Out store id.
func TestDerivedSellInBranchAchievementWithPlanFileKeys(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "plan.xlsx", []domain.SellInRecord{
		planSellIn("p1", "311350147", "ALX", "الاسكندرية", "FGCL-0001", 10, 1200),             // سموحة: 120 pieces
		planSellIn("p2", "مجمع الإقليم (Regional)", "ALX", "الاسكندرية", "FGCL-0001", 4, 480), // 48 pieces, ALX
		planSellIn("p3", "مجمع الإقليم (Regional)", "TNT", "الغربية", "FGCL-0001", 2, 240),    // 24 pieces, TNT
		planSellIn("p4", "مجمع الإقليم (Regional)", "ALX", "الاسكندرية", "FGCL-0003", 1, 120), // 6 pieces, ALX
	}); err != nil {
		t.Fatal(err)
	}

	it := derivedSummary(t, c).Items[0]
	if !it.HasActuals || !near(it.ActualUnits, 198) {
		t.Fatalf("header actual = 120+48+24+6 pieces, got %v (has=%v)", it.ActualUnits, it.HasActuals)
	}
	smouha := branchByCode(it.Branches, "fat_smouha")
	stanley := branchByCode(it.Branches, "fat_stanley")
	tanta := branchByCode(it.Branches, "fat_tanta")
	if smouha == nil || stanley == nil || tanta == nil {
		t.Fatalf("expected the three Sell-Out branches: %+v", it.Branches)
	}
	// Targets (pieces): smouha P1 600 + P3 200, stanley P1 200, tanta P1 200.
	// ALX P1 bucket (48) splits 600:200 → smouha 36, stanley 12; ALX P3 bucket (6) → smouha; TNT → tanta.
	if !near(smouha.ActualUnits, 162) || !near(smouha.ActualAllocatedUnits, 42) {
		t.Fatalf("smouha: direct 120 + allocated 42, got actual=%v allocated=%v", smouha.ActualUnits, smouha.ActualAllocatedUnits)
	}
	if !near(stanley.ActualUnits, 12) || !near(stanley.ActualAllocatedUnits, 12) {
		t.Fatalf("stanley: allocated 12, got %+v", stanley)
	}
	if !near(tanta.ActualUnits, 24) || tanta.RegionCode != "TNT" {
		t.Fatalf("tanta: TNT bucket 24 pieces, got actual=%v region=%q", tanta.ActualUnits, tanta.RegionCode)
	}
	if smouha.RegionCode != "ALX" {
		t.Fatalf("smouha region from the chain catalog, got %q", smouha.RegionCode)
	}
	var branchSum float64
	for _, b := range it.Branches {
		branchSum += b.ActualUnits
		if b.AchievementUnitsPct <= 0 || b.Status == "no_data" {
			t.Fatalf("branch %s must show achievement: %+v", b.BranchName, b)
		}
		var skuSum float64
		for _, s := range b.SKUs {
			skuSum += s.ActualUnits
		}
		if !near(skuSum, b.ActualUnits) {
			t.Fatalf("branch %s SKU actuals %v must add up to the branch actual %v", b.BranchName, skuSum, b.ActualUnits)
		}
	}
	if !near(branchSum, it.ActualUnits) {
		t.Fatalf("branch actuals %v must add up to the target actual %v", branchSum, it.ActualUnits)
	}
	p1 := skuByCode(smouha.SKUs, "FGCL-0001")
	if p1 == nil || !near(p1.ActualUnits, 156) || !near(p1.AchievementPct, 26) {
		t.Fatalf("smouha P1: 120 direct + 36 allocated over a 600 target, got %+v", p1)
	}
	if smouha.SKUs[0].TargetUnits < smouha.SKUs[len(smouha.SKUs)-1].TargetUnits {
		t.Fatalf("branch SKUs sorted by target pieces desc: %+v", smouha.SKUs)
	}
}

func TestDerivedSellInBranchMatchesStoreIDAndCustomerBranchLabel(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	gp := planSellIn("g1", "fat_auto_1234abcd", "ALX", "", "FGCL-0001", 1, 100) // GP SOP: id from the full name
	gp.CustomerName = "فتح الله -  ستانلى"
	byID := planSellIn("g2", "fat_tanta", "TNT", "", "FGCL-0001", 2, 200)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "gp.xlsx", []domain.SellInRecord{gp, byID}); err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c).Items[0]
	stanley := branchByCode(it.Branches, "fat_stanley")
	tanta := branchByCode(it.Branches, "fat_tanta")
	smouha := branchByCode(it.Branches, "fat_smouha")
	if !near(stanley.ActualUnits, 12) || stanley.ActualAllocatedUnits != 0 {
		t.Fatalf("customer branch label «ستانلى» is a direct match: %+v", stanley)
	}
	if !near(tanta.ActualUnits, 24) || tanta.ActualAllocatedUnits != 0 {
		t.Fatalf("store id fat_tanta is a direct match: %+v", tanta)
	}
	if smouha.ActualUnits != 0 || smouha.Status != "no_data" {
		t.Fatalf("smouha has no Sell-In rows: %+v", smouha)
	}
}

func TestDerivedSellInRegionWithoutBranchesSpreadsOverTheChain(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "plan.xlsx", []domain.SellInRecord{
		planSellIn("c1", "مجمع الإقليم (Regional)", "CIR", "القاهرة", "FGCL-0001", 10, 1000), // 120 pieces, no CIR branch
	}); err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c).Items[0]
	// P1 targets: smouha 600, stanley 200, tanta 200 → 72 / 24 / 24.
	want := map[string]float64{"fat_smouha": 72, "fat_stanley": 24, "fat_tanta": 24}
	for code, units := range want {
		b := branchByCode(it.Branches, code)
		if b == nil || !near(b.ActualUnits, units) || !near(b.ActualAllocatedUnits, units) {
			t.Fatalf("%s: want %v allocated pieces, got %+v", code, units, b)
		}
	}
}

func TestDerivedSellInBranchAttributionRespectsBrandFilter(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "plan.xlsx", []domain.SellInRecord{
		planSellIn("f1", "311350147", "ALX", "الاسكندرية", "FGCL-0001", 10, 1200),
		planSellIn("f2", "311350147", "ALX", "الاسكندرية", "FGCL-0003", 1, 120),
	}); err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c, NoBrandLabelAr).Items[0]
	smouha := branchByCode(it.Branches, "fat_smouha")
	if smouha == nil || !near(smouha.ActualUnits, 6) || len(smouha.SKUs) != 1 || smouha.SKUs[0].ItemCode != "FGCL-0003" {
		t.Fatalf("only the unbranded SKU (6 pieces) under «%s»: %+v", NoBrandLabelAr, smouha)
	}
}

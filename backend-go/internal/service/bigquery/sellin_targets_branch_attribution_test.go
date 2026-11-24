package bigquery

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

const dsiLegalEntity = "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م"

// newBranchAttributionFixture mirrors production keys: Sell-Out stores are store ids (fat_smouha …) with
// display names, while Sell-In rows name the chain's legal entity with an ERP branch code (311350147 =
// سموحة in the Fathalla catalog), or — GP SOP exports — «عائله فتح الله ماركت - <branch>».
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

// realSellIn is a row of a real Sell-In export (not a Plan workbook).
func realSellIn(id, branchCode, region, gov, code string, cases, value float64) domain.SellInRecord {
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

func assertBranchesAddUp(t *testing.T, it domain.TargetComparisonItem) {
	t.Helper()
	var branchSum float64
	for _, b := range it.Branches {
		branchSum += b.ActualUnits
		var skuSum float64
		for _, s := range b.SKUs {
			skuSum += s.ActualUnits
		}
		if !near(skuSum, b.ActualUnits) {
			t.Fatalf("branch %s SKU actuals %v must add up to the branch actual %v", b.BranchName, skuSum, b.ActualUnits)
		}
	}
	if !near(branchSum, it.ActualUnits) {
		t.Fatalf("branch lines (incl. «غير محدد الفرع») %v must add up to the target actual %v", branchSum, it.ActualUnits)
	}
}

// Regression: the branch drill-down showed «—» for every branch although the target had achieved
// pieces, because Sell-In rows (ERP branch codes under the legal-entity name) never matched a Sell-Out
// store id. Rows without a branch are never spread over the branches: they stay in «غير محدد الفرع».
func TestDerivedSellInBranchAchievementByERPCodeAndUnassignedLine(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "in26.xlsx", []domain.SellInRecord{
		realSellIn("p1", "311350147", "ALX", "الاسكندرية", "FGCL-0001", 10, 1200),                    // سموحة: 120 pieces
		realSellIn("p2", gemini.SellInNoBranchPlaceholder, "ALX", "الاسكندرية", "FGCL-0001", 4, 480), // 48 pieces, no branch
		realSellIn("p3", gemini.SellInNoBranchPlaceholder, "TNT", "الغربية", "FGCL-0001", 2, 240),    // 24 pieces, no branch
		realSellIn("p4", "", "ALX", "الاسكندرية", "FGCL-0003", 1, 120),                               // 6 pieces, no branch
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
	none := branchByCode(it.Branches, DerivedUnassignedBranchCode)
	if smouha == nil || stanley == nil || tanta == nil || none == nil {
		t.Fatalf("expected the three Sell-Out branches and «غير محدد الفرع»: %+v", it.Branches)
	}
	if !near(smouha.ActualUnits, 120) || !near(smouha.AchievementUnitsPct, 15) || smouha.Status == "no_data" {
		t.Fatalf("smouha: ERP code 311350147 → 120 of 800 target pieces, got %+v", smouha)
	}
	if stanley.ActualUnits != 0 || stanley.Status != "no_data" || tanta.ActualUnits != 0 || tanta.Status != "no_data" {
		t.Fatalf("branches without their own Sell-In rows get nothing (no distribution): stanley=%+v tanta=%+v", stanley, tanta)
	}
	if !none.Unassigned || none.BranchName != DerivedUnassignedBranchName || !near(none.ActualUnits, 78) || none.TargetUnits != 0 {
		t.Fatalf("«غير محدد الفرع» = 48+24+6 pieces with no target, got %+v", none)
	}
	if last := it.Branches[len(it.Branches)-1]; !last.Unassigned {
		t.Fatalf("«غير محدد الفرع» is the last line, got %+v", last)
	}
	if it.BranchesCount != 3 {
		t.Fatalf("BranchesCount counts real branches only, got %d", it.BranchesCount)
	}
	assertBranchesAddUp(t, it)
	p1 := skuByCode(smouha.SKUs, "FGCL-0001")
	if p1 == nil || !near(p1.ActualUnits, 120) || !near(p1.AchievementPct, 20) {
		t.Fatalf("smouha P1: 120 of a 600 target, got %+v", p1)
	}
	if smouha.SKUs[0].TargetUnits < smouha.SKUs[len(smouha.SKUs)-1].TargetUnits {
		t.Fatalf("branch SKUs sorted by target pieces desc: %+v", smouha.SKUs)
	}
}

// GP SOP exports keep the store in Customer Name («عائله فتح الله ماركت - ستانلى») while the stored
// customer branch code is an id of the full name (fat_auto_…); the branch part maps to the store.
func TestDerivedSellInBranchFromGPSOPCustomerNameAndStoreID(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	gp := realSellIn("g1", "fat_auto_e47e193d", "ALX", "", "FGCL-0001", 1, 100)
	gp.CustomerName = "عائله فتح الله ماركت -  ستانلى"
	care := realSellIn("g2", "fat_auto_70b8ed04", "TNT", "", "FGCL-0001", 1, 100)
	care.CustomerName = "عائله فتح الله ماركت مواد عناية - طنطا"
	byID := realSellIn("g3", "fat_tanta", "TNT", "", "FGCL-0001", 1, 100)
	mini := realSellIn("g4", "fat_auto_121d9fe2", "ALX", "", "FGCL-0001", 1, 100)
	mini.CustomerName = dsiLegalEntity + " - ميني"
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "in25.xlsx", []domain.SellInRecord{gp, care, byID, mini}); err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c).Items[0]
	if b := branchByCode(it.Branches, "fat_stanley"); b == nil || !near(b.ActualUnits, 12) {
		t.Fatalf("«… - ستانلى» → fat_stanley, got %+v", b)
	}
	if b := branchByCode(it.Branches, "fat_tanta"); b == nil || !near(b.ActualUnits, 24) {
		t.Fatalf("«… مواد عناية - طنطا» and store id fat_tanta → fat_tanta, got %+v", b)
	}
	if b := branchByCode(it.Branches, DerivedUnassignedBranchCode); b == nil || !near(b.ActualUnits, 12) {
		t.Fatalf("«… ش م م - ميني» is no known store → «غير محدد الفرع», got %+v", b)
	}
	if b := branchByCode(it.Branches, "fat_smouha"); b == nil || b.ActualUnits != 0 {
		t.Fatalf("smouha has no Sell-In rows: %+v", b)
	}
	assertBranchesAddUp(t, it)
}

// A Sell-In row naming a real store that has no Sell-Out target is its own branch line (target 0), not
// «غير محدد الفرع» and not another branch.
func TestDerivedSellInKnownStoreWithoutTargetGetsItsOwnLine(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	byCode := realSellIn("k1", "311350954", "BHR", "البحيرة", "FGCL-0001", 1, 100) // catalog: دمنهور الأندلس
	byName := realSellIn("k2", "fat_auto_x", "BHR", "", "FGCL-0001", 1, 100)
	byName.CustomerName = "عائله فتح الله ماركت - دمنهور الأندلس"
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "in25.xlsx", []domain.SellInRecord{byCode, byName}); err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c).Items[0]
	b := branchByCode(it.Branches, "fat_damanhour_andalus")
	if b == nil || b.Unassigned || b.TargetUnits != 0 || !near(b.ActualUnits, 24) {
		t.Fatalf("دمنهور الأندلس: one line with both rows (24 pieces) and no target, got %+v (all %+v)", b, it.Branches)
	}
	if branchByCode(it.Branches, DerivedUnassignedBranchCode) != nil {
		t.Fatalf("no «غير محدد الفرع» line when every row names a store: %+v", it.Branches)
	}
	if it.BranchesCount != 4 {
		t.Fatalf("BranchesCount = 3 target branches + 1 Sell-In-only branch, got %d", it.BranchesCount)
	}
	assertBranchesAddUp(t, it)
}

func TestDerivedSellInBranchAttributionRespectsBrandFilter(t *testing.T) {
	c := newBranchAttributionFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 0)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "in26.xlsx", []domain.SellInRecord{
		realSellIn("f1", "311350147", "ALX", "الاسكندرية", "FGCL-0001", 10, 1200),
		realSellIn("f2", "311350147", "ALX", "الاسكندرية", "FGCL-0003", 1, 120),
	}); err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c, NoBrandLabelAr).Items[0]
	smouha := branchByCode(it.Branches, "fat_smouha")
	if smouha == nil || !near(smouha.ActualUnits, 6) || len(smouha.SKUs) != 1 || smouha.SKUs[0].ItemCode != "FGCL-0003" {
		t.Fatalf("only the unbranded SKU (6 pieces) under «%s»: %+v", NoBrandLabelAr, smouha)
	}
}

package bigquery

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const (
	dsiTenant = "tenant-dsi"
	dsiBrandA = "ديفا (Diva)"
	dsiBrandB = "فلفيتا"
)

func dsiFact(id, store, storeName, code, name, date string, units int, rev float64) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID: id, TenantID: dsiTenant, RetailerChain: "fathalla", StoreID: store, StoreName: storeName,
		ItemCode: code, SKUName: name, Category: "عناية", UnitsPerCarton: 12,
		QuantitySold: units, NetRevenue: rev, TransactionDate: date,
	}
}

// newDerivedFixture seeds a Product Master (P1 brand A pack 12 cost 10, P2 brand B no pack size cost 5,
// P3 no brand pack 6 cost 20) and 2025 Sell-Out history across two branches.
func newDerivedFixture(t *testing.T) *Client {
	t.Helper()
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	c := NewClient("tashil-test", "retail", true)
	ctx := context.Background()
	if _, err := c.SetProductMaster(ctx, dsiTenant, &domain.ProductMasterSummaryResponse{
		TenantID: dsiTenant,
		Items: []domain.ProductMasterItem{
			{SerialNo: 1, ItemCode: "FGCL-0001", ItemCodePrefix: "FGCL", Barcode: "6220000000011", OfficialName: "صنف 1", Brand: dsiBrandA, UnitsPerCarton: 12, NetUnitInvoiceCost: 10},
			{SerialNo: 2, ItemCode: "FGCL-0002", ItemCodePrefix: "FGCL", Barcode: "6220000000028", OfficialName: "صنف 2", Brand: dsiBrandB, UnitsPerCarton: 0, NetUnitInvoiceCost: 5},
			{SerialNo: 3, ItemCode: "FGCL-0003", ItemCodePrefix: "FGCL", Barcode: "6220000000035", OfficialName: "صنف 3", Brand: "", UnitsPerCarton: 6, NetUnitInvoiceCost: 20},
		},
	}); err != nil {
		t.Fatal(err)
	}
	if err := c.InsertSellOutFacts(ctx, []domain.SellOutFact{
		dsiFact("a1", "s1", "فتح الله - الرحاب", "FGCL-0001", "صنف 1", "2025-03-10", 60, 600),
		dsiFact("a2", "s1", "فتح الله - الرحاب", "FGCL-0003", "صنف 3", "2025-03-11", 20, 400),
		dsiFact("a3", "s2", "فتح الله - سموحة", "FGCL-0001", "صنف 1", "2025-03-12", 20, 200),
		dsiFact("a4", "s2", "فتح الله - سموحة", "FGCL-0002", "صنف 2", "2025-03-13", 20, 200),
	}); err != nil {
		t.Fatal(err)
	}
	return c
}

func dsiSellOutTarget(t *testing.T, c *Client, year, month int, units, rev float64) *domain.TargetRecord {
	t.Helper()
	tr, err := c.UpsertTarget(context.Background(), dsiTenant, domain.TargetRecord{
		TargetType: "sell_out", RetailerChain: "fathalla", Year: year, Month: month,
		TargetUnits: units, TargetRevenueEGP: rev,
	})
	if err != nil {
		t.Fatal(err)
	}
	return tr
}

func dsiSellIn(id, code, name string, month int, cases, value float64) domain.SellInRecord {
	return domain.SellInRecord{
		RecordID: id, TenantID: dsiTenant, RetailerChain: "fathalla", Year: 2026, MonthNum: month,
		CustomerName: "فتح الله - الرحاب", CustomerBranchCode: "s1",
		ItemCode: code, ItemName: name, NetQtyCases: cases, NetValueEGP: value,
	}
}

func derivedSummary(t *testing.T, c *Client, brands ...string) *domain.TargetsSummaryResponse {
	t.Helper()
	s, err := c.GetDerivedSellInTargetsSummary(context.Background(), dsiTenant, DerivedSellInOptions{Chain: "fathalla", Year: 2026, Brands: brands})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func skuByCode(rows []domain.TargetSKUBreakdown, code string) *domain.TargetSKUBreakdown {
	for i := range rows {
		if rows[i].ItemCode == code {
			return &rows[i]
		}
	}
	return nil
}

func TestDerivedSellInQuantityIsOneToOneWithSellOut(t *testing.T) {
	c := newDerivedFixture(t)
	so := dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)

	s := derivedSummary(t, c)
	if !s.Derived || s.TargetType != "sell_in" || s.QuantityUnit != "pieces" {
		t.Fatalf("unexpected summary header: %+v", s)
	}
	if len(s.Items) != 1 {
		t.Fatalf("want 1 derived item, got %d", len(s.Items))
	}
	it := s.Items[0]
	if it.ID != "derived_si_from_"+so.ID || it.SourceTargetID != so.ID || !it.Derived || it.TargetType != "sell_in" {
		t.Fatalf("identity: %+v", it)
	}
	if it.TargetUnits != 1000 || s.TotalTargetUnits != 1000 {
		t.Fatalf("quantity must equal the Sell-Out target 1:1: item=%v total=%v", it.TargetUnits, s.TotalTargetUnits)
	}
	var sku, branch float64
	for _, r := range it.ChainSKUTotals {
		sku += r.TargetUnits
	}
	for _, b := range it.Branches {
		branch += b.TargetUnits
	}
	if sku != 1000 || branch != 1000 {
		t.Fatalf("SKU and branch pieces must add up to the Sell-Out quantity: sku=%v branch=%v", sku, branch)
	}
	if it.Branches[0].BranchCode == "" || len(it.Branches) != 2 {
		t.Fatalf("expected the two Sell-Out branches, got %+v", it.Branches)
	}
}

func TestDerivedSellInCasesAndMissingPackSize(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	it := derivedSummary(t, c).Items[0]

	p1 := skuByCode(it.ChainSKUTotals, "FGCL-0001")
	p2 := skuByCode(it.ChainSKUTotals, "FGCL-0002")
	if p1 == nil || p2 == nil {
		t.Fatalf("expected P1 and P2 rows: %+v", it.ChainSKUTotals)
	}
	if p1.TargetCases == nil || math.Abs(*p1.TargetCases-p1.TargetUnits/12) > 0.01 {
		t.Fatalf("cases = pieces / pack size: %+v", p1)
	}
	if p2.TargetCases != nil || !p2.PackSizeMissing || p2.TargetUnits <= 0 {
		t.Fatalf("missing pack size keeps pieces and hides cases: %+v", p2)
	}
	if it.TargetCases == nil || it.PackSizeMissingSKUs != 1 {
		t.Fatalf("item cases are the sum over known packs and the gap is flagged: cases=%v missing=%d", it.TargetCases, it.PackSizeMissingSKUs)
	}
}

func TestDerivedSellInValueIsQuantityTimesCost(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	it := derivedSummary(t, c).Items[0]

	want := map[string]float64{"FGCL-0001": 10, "FGCL-0002": 5, "FGCL-0003": 20}
	var total float64
	for code, cost := range want {
		r := skuByCode(it.ChainSKUTotals, code)
		if r == nil {
			t.Fatalf("missing %s", code)
		}
		if got := round2(r.TargetUnits * cost); r.TargetRevenueEGP != got {
			t.Fatalf("%s value %v != pieces %v x cost %v", code, r.TargetRevenueEGP, r.TargetUnits, cost)
		}
		total += r.TargetRevenueEGP
	}
	if math.Abs(it.TargetRevenueEGP-total) > 0.05 {
		t.Fatalf("item value %v != sum of SKU values %v", it.TargetRevenueEGP, total)
	}
}

func TestDerivedSellInExplicitPriceOverridesCost(t *testing.T) {
	c := newDerivedFixture(t)
	tr, err := c.UpsertTarget(context.Background(), dsiTenant, domain.TargetRecord{
		TargetType: "sell_out", RetailerChain: "fathalla", Year: 2026,
		TargetUnits: 1000, TargetRevenueEGP: 14000, ExplicitUnitPriceEGP: 2,
	})
	if err != nil {
		t.Fatal(err)
	}
	it := derivedSummary(t, c).Items[0]
	if it.SourceTargetID != tr.ID || it.TargetRevenueEGP != 2000 {
		t.Fatalf("explicit price 2 x 1000 pieces = 2000, got %v", it.TargetRevenueEGP)
	}
}

func TestDerivedSellInMissingCostIsFlaggedNotGuessed(t *testing.T) {
	c := newDerivedFixture(t)
	// Unknown SKU: no Product Master row, so no cost and no brand.
	if err := c.InsertSellOutFacts(context.Background(), []domain.SellOutFact{
		dsiFact("z1", "s1", "فتح الله - الرحاب", "UNKNOWN-1", "صنف مجهول", "2025-03-14", 100, 5000),
	}); err != nil {
		t.Fatal(err)
	}
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	it := derivedSummary(t, c).Items[0]
	r := skuByCode(it.ChainSKUTotals, "")
	if r == nil || r.Brand != NoBrandLabelAr || !r.CostMissing || r.TargetRevenueEGP != 0 || r.TargetUnits <= 0 {
		t.Fatalf("unmatched SKU: quantity kept, value not guessed, brand «بدون براند»: %+v", r)
	}
	if it.CostMissingSKUs != 1 {
		t.Fatalf("cost_missing_skus=%d", it.CostMissingSKUs)
	}
}

func TestDerivedSellInAchievementQuantityFirstThenValue(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "si.xlsx", []domain.SellInRecord{
		dsiSellIn("r1", "FGCL-0001", "صنف 1", 3, 10, 1500), // 10 cases x 12 = 120 pieces
	}); err != nil {
		t.Fatal(err)
	}
	s := derivedSummary(t, c)
	it := s.Items[0]
	if !it.HasActuals || it.ActualUnits != 120 || it.ActualCases == nil || *it.ActualCases != 10 {
		t.Fatalf("actual quantity (pieces then cases): %+v cases=%v", it.ActualUnits, it.ActualCases)
	}
	if it.AchievementUnitsPct != 12 {
		t.Fatalf("achievement is quantity-based: got %v", it.AchievementUnitsPct)
	}
	if it.ActualRevenueEGP != 1500 || it.AchievementRevPct <= 0 {
		t.Fatalf("value achievement is secondary but present: %+v", it)
	}
	if s.OverallAchievementPct != 12 {
		t.Fatalf("overall achievement follows quantity: %v", s.OverallAchievementPct)
	}
	if it.Status != "at_risk" {
		t.Fatalf("status from quantity: %s", it.Status)
	}
	p1 := skuByCode(it.ChainSKUTotals, "FGCL-0001")
	if p1.ActualUnits != 120 || p1.AchievementPct <= 0 {
		t.Fatalf("SKU actual: %+v", p1)
	}
	var branchActual float64
	for _, b := range it.Branches {
		branchActual += b.ActualUnits
	}
	if branchActual != 120 {
		t.Fatalf("branch actual (matched by branch code): %v", branchActual)
	}
}

func TestDerivedSellInNoActualsIsNotZeroPercent(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	s := derivedSummary(t, c)
	it := s.Items[0]
	if it.HasActuals || it.Status != "no_data" || it.AchievementUnitsPct != 0 || s.NoDataTargetsCount != 1 || s.ComparableTargetsCount != 0 {
		t.Fatalf("a target without Sell-In rows is not comparable: %+v", it)
	}
}

func TestDerivedSellInBrandFilter(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "si.xlsx", []domain.SellInRecord{
		dsiSellIn("r1", "FGCL-0001", "صنف 1", 3, 10, 1500),
		dsiSellIn("r2", "FGCL-0003", "صنف 3", 3, 5, 900), // no brand: 5 cases x 6 = 30 pieces
	}); err != nil {
		t.Fatal(err)
	}

	all := derivedSummary(t, c)
	wantBrands := []string{dsiBrandA, dsiBrandB, NoBrandLabelAr}
	if len(all.AvailableBrands) != 3 || all.AvailableBrands[0] != wantBrands[0] && all.AvailableBrands[1] != wantBrands[0] || all.AvailableBrands[2] != NoBrandLabelAr {
		t.Fatalf("available brands (no-brand last): %v", all.AvailableBrands)
	}

	a := derivedSummary(t, c, dsiBrandA)
	nb := derivedSummary(t, c, NoBrandLabelAr)
	both := derivedSummary(t, c, dsiBrandA, NoBrandLabelAr)
	if len(a.Items) != 1 || len(nb.Items) != 1 || len(both.Items) != 1 {
		t.Fatalf("items: %d %d %d", len(a.Items), len(nb.Items), len(both.Items))
	}
	if a.TotalTargetUnits+nb.TotalTargetUnits != both.TotalTargetUnits || both.TotalTargetUnits >= all.TotalTargetUnits {
		t.Fatalf("filtered totals must add up: a=%v nb=%v both=%v all=%v", a.TotalTargetUnits, nb.TotalTargetUnits, both.TotalTargetUnits, all.TotalTargetUnits)
	}
	if a.TotalActualUnits != 120 || nb.TotalActualUnits != 30 || both.TotalActualUnits != 150 {
		t.Fatalf("actuals follow the brand filter: a=%v nb=%v both=%v", a.TotalActualUnits, nb.TotalActualUnits, both.TotalActualUnits)
	}
	for _, r := range a.Items[0].ChainSKUTotals {
		if r.Brand != dsiBrandA {
			t.Fatalf("only brand A rows expected: %+v", r)
		}
	}
	if len(nb.Items[0].Brands) != 1 || nb.Items[0].Brands[0].Brand != NoBrandLabelAr {
		t.Fatalf("brand rollup: %+v", nb.Items[0].Brands)
	}
	if a.AvailableBrands == nil || len(a.AvailableBrands) != len(all.AvailableBrands) {
		t.Fatalf("available brands stay the full list while filtering: %v", a.AvailableBrands)
	}
	if len(a.AppliedBrands) != 1 {
		t.Fatalf("applied brands echoed: %v", a.AppliedBrands)
	}
	none := derivedSummary(t, c, "علامة غير موجودة")
	if len(none.Items) != 0 || none.SellOutTargetsCount != 1 {
		t.Fatalf("filter with no match keeps Sell-Out count for the empty state: %+v", none)
	}
}

func TestDerivedSellInAnnualAndMonthlyAreNotDoubleCounted(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1200, 16800)
	dsiSellOutTarget(t, c, 2026, 3, 100, 1400)
	dsiSellOutTarget(t, c, 2026, 4, 100, 1400)

	s := derivedSummary(t, c)
	if len(s.Items) != 3 {
		t.Fatalf("all Sell-Out targets are listed: %d", len(s.Items))
	}
	var excluded int
	for _, it := range s.Items {
		if it.Month == 0 {
			if !it.ExcludedFromTotals || it.ExcludedReason != "superseded_by_monthly" || it.TargetUnits != 1200 {
				t.Fatalf("annual row stays 1:1 but is excluded from totals: %+v", it)
			}
			excluded++
		}
	}
	if excluded != 1 || s.ExcludedFromTotalsCount != 1 {
		t.Fatalf("excluded=%d count=%d", excluded, s.ExcludedFromTotalsCount)
	}
	if s.TotalTargetUnits != 200 {
		t.Fatalf("totals count only the monthly targets: %v", s.TotalTargetUnits)
	}

	// Without monthly targets the annual target counts.
	c2 := newDerivedFixture(t)
	dsiSellOutTarget(t, c2, 2026, 0, 1200, 16800)
	if s2 := derivedSummary(t, c2); s2.TotalTargetUnits != 1200 || s2.ExcludedFromTotalsCount != 0 {
		t.Fatalf("annual alone: %+v", s2)
	}
}

func TestDerivedSellInIgnoresLegacyManualRecordsWithoutDeletingThem(t *testing.T) {
	c := newDerivedFixture(t)
	dir := os.Getenv("TASHIL_TARGETS_DIR")
	legacy := domain.TargetRecord{ID: "legacy_si_1", TenantID: dsiTenant, TargetType: "sell_in", RetailerChain: "fathalla", Year: 2026, TargetUnits: 777, TargetRevenueEGP: 99999}
	c.mu.Lock()
	c.targets[dsiTenant] = append(c.targets[dsiTenant], legacy)
	c.mu.Unlock()

	if s := derivedSummary(t, c); len(s.Items) != 0 || s.TotalTargetUnits != 0 || s.SellOutTargetsCount != 0 {
		t.Fatalf("legacy manual Sell-In records are ignored on read: %+v", s)
	}
	if s, _ := c.GetTargetsSummary(context.Background(), dsiTenant, "sell_in", "fathalla", 2026); len(s.Items) != 0 {
		t.Fatalf("GetTargetsSummary(sell_in) must derive too: %+v", s.Items)
	}

	if err := c.DeleteTarget(context.Background(), dsiTenant, "legacy_si_1"); !errors.Is(err, ErrSellInTargetsDerived) {
		t.Fatalf("deleting a legacy Sell-In record is refused: %v", err)
	}
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000) // persists the tenant file
	raw, err := os.ReadFile(filepath.Join(dir, dsiTenant+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var persisted []domain.TargetRecord
	if err := json.Unmarshal(raw, &persisted); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, p := range persisted {
		if p.ID == "legacy_si_1" && p.TargetUnits == 777 {
			found = true
		}
	}
	if !found {
		t.Fatalf("legacy record must survive untouched in the tenant JSON: %+v", persisted)
	}
	if s := derivedSummary(t, c); len(s.Items) != 1 || s.Items[0].TargetUnits != 1000 {
		t.Fatalf("only the Sell-Out target is derived: %+v", s.Items)
	}
}

func TestSellInTargetWritesAreRejectedAtTheService(t *testing.T) {
	c := newDerivedFixture(t)
	if _, err := c.UpsertTarget(context.Background(), dsiTenant, domain.TargetRecord{TargetType: "sell_in", Year: 2026, TargetUnits: 1}); !errors.Is(err, ErrSellInTargetsDerived) {
		t.Fatalf("upsert sell_in: %v", err)
	}
	so := dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	if err := c.DeleteTarget(context.Background(), dsiTenant, DerivedSellInTargetID(so.ID)); !errors.Is(err, ErrSellInTargetsDerived) {
		t.Fatalf("delete derived id: %v", err)
	}
	if got := derivedSummary(t, c); len(got.Items) != 1 {
		t.Fatalf("the Sell-Out target is untouched: %+v", got.Items)
	}
}

func TestDerivedSellInChainAndYearFilters(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	dsiSellOutTarget(t, c, 2027, 0, 500, 7000)
	s, err := c.GetDerivedSellInTargetsSummary(context.Background(), dsiTenant, DerivedSellInOptions{Year: 2027})
	if err != nil || len(s.Items) != 1 || s.Items[0].Year != 2027 || s.TotalTargetUnits != 500 {
		t.Fatalf("year filter: %+v %v", s, err)
	}
	other, err := c.GetDerivedSellInTargetsSummary(context.Background(), dsiTenant, DerivedSellInOptions{Chain: "gomla"})
	if err != nil || len(other.Items) != 0 {
		t.Fatalf("chain filter: %+v %v", other, err)
	}
	empty, err := c.GetDerivedSellInTargetsSummary(context.Background(), "tenant-nothing", DerivedSellInOptions{})
	if err != nil || len(empty.Items) != 0 || empty.SellOutTargetsCount != 0 || !empty.Derived {
		t.Fatalf("no Sell-Out target at all: %+v %v", empty, err)
	}
}

func TestDerivedSellInWithoutHistoryKeepsFullQuantityUnallocated(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	c := NewClient("tashil-test", "retail", true)
	if _, err := c.UpsertTarget(context.Background(), "tenant-nohist", domain.TargetRecord{
		TargetType: "sell_out", RetailerChain: "fathalla", Year: 2026, TargetUnits: 400, TargetRevenueEGP: 4000,
	}); err != nil {
		t.Fatal(err)
	}
	s, err := c.GetDerivedSellInTargetsSummary(context.Background(), "tenant-nohist", DerivedSellInOptions{})
	if err != nil || len(s.Items) != 1 {
		t.Fatalf("%+v %v", s, err)
	}
	it := s.Items[0]
	if it.TargetUnits != 400 || len(it.Branches) != 0 || len(it.ChainSKUTotals) != 1 || it.Brands[0].Brand != NoBrandLabelAr {
		t.Fatalf("full Sell-Out quantity kept without a SKU split: %+v", it)
	}
}

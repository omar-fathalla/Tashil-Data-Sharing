package bigquery

import (
	"context"
	"math"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func f64(v float64) *float64 { return &v }

func near(a, b float64) bool { return math.Abs(a-b) < 0.011 }

func TestChainVATRatePrecedence(t *testing.T) {
	pm14 := domain.ProductMasterItem{VATRate: 0.14}
	pm10 := domain.ProductMasterItem{VATRate: 0.10}
	withVAT := domain.ChainDiscountProfile{Chain: "x", VATRatePct: f64(5)}
	noVAT := domain.ChainDiscountProfile{Chain: "x"}
	zeroVAT := domain.ChainDiscountProfile{Chain: "x", VATRatePct: f64(0)}

	cases := []struct {
		name    string
		prof    domain.ChainDiscountProfile
		hasProf bool
		pm      domain.ProductMasterItem
		pmOk    bool
		want    float64
	}{
		{"chain setting wins over product master", withVAT, true, pm10, true, 0.05},
		{"chain setting works without a master match", withVAT, true, domain.ProductMasterItem{}, false, 0.05},
		{"an explicit 0% VAT is respected", zeroVAT, true, pm14, true, 0},
		{"profile without VAT falls back to the master column", noVAT, true, pm10, true, 0.10},
		{"no profile: master column", domain.ChainDiscountProfile{}, false, pm10, true, 0.10},
		{"nothing set: 14%", domain.ChainDiscountProfile{}, false, domain.ProductMasterItem{}, false, 0.14},
		{"master column stored as 14 (percent) is normalised", domain.ChainDiscountProfile{}, false, domain.ProductMasterItem{VATRate: 14}, true, 0.14},
	}
	for _, tc := range cases {
		if got := chainVATRate(tc.prof, tc.hasProf, tc.pm, tc.pmOk); math.Abs(got-tc.want) > 1e-12 {
			t.Errorf("%s: got %v want %v", tc.name, got, tc.want)
		}
	}
}

func TestResolveFactoryUnitCostForChainUsesChainVAT(t *testing.T) {
	// List incl 14% = 114 (excl 100). Chain VAT 5%, invoice 10%, extra 20%.
	pm := domain.ProductMasterItem{VATRate: 0.14, UnitPriceInclVAT: 114, UnitPriceExclVAT: 100, NetUnitInvoiceCost: 102.6}
	prof := domain.ChainDiscountProfile{Chain: "x", InvoiceDiscountPct: 10, AdditionalDiscountPct: 20, VATRatePct: f64(5)}
	got, src, _ := resolveFactoryUnitCostForChain(0, pm, true, prof, true)
	if want := 100 * 1.05 * 0.9 * 0.8; math.Abs(got-want) > 1e-9 || src != costSourceMasterListChainProfile {
		t.Fatalf("cost incl chain VAT: got %v (%s) want %v", got, src, want)
	}
	// Same VAT as the master: identical to the old formula (no float drift).
	prof.VATRatePct = nil
	got, _, _ = resolveFactoryUnitCostForChain(0, pm, true, prof, true)
	if want := 114 * 0.9 * 0.8; math.Abs(got-want) > 1e-12 {
		t.Fatalf("got %v want %v", got, want)
	}
}

type chainTermsFixture struct {
	c   *Client
	ctx context.Context
}

const ctTenant = "tenant-ctest"

// newChainTermsFixture: one product (list 100 excl / 114 incl, 12 pcs per carton), Fathalla sell-out
// and sell-in for Jan 2026 AND Jan 2025 (so the previous year overlaps the same month).
func newChainTermsFixture(t *testing.T) chainTermsFixture {
	t.Helper()
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	c := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()
	if _, err := c.UpsertProductMasterItem(ctx, ctTenant, domain.ProductMasterItem{
		ItemCode: "FGCL-0550-0001", OfficialName: "Test SKU", UnitsPerCarton: 12, VATRate: 0.14,
		UnitPriceExclVAT: 100, InvoiceDiscountPct: 0.10,
	}); err != nil {
		t.Fatal(err)
	}
	fact := func(id, date string, qty int, rev float64) domain.SellOutFact {
		return domain.SellOutFact{
			RecordID: id, TenantID: ctTenant, RetailerChain: "fathalla", StoreID: "s1", StoreName: "فرع 1",
			ItemCode: "FGCL-0550-0001", SKUName: "Test SKU", IsOwnBrand: true, QuantitySold: qty, NetRevenue: rev,
			TransactionDate: date, IngestionBatchID: "batch_real_1",
		}
	}
	if err := c.InsertSellOutFacts(ctx, []domain.SellOutFact{
		fact("so-2026-01", "2026-01-10", 100, 12000),
		fact("so-2025-01", "2025-01-10", 50, 5000),
	}); err != nil {
		t.Fatal(err)
	}
	si := func(id string, year int, val float64) domain.SellInRecord {
		return domain.SellInRecord{
			RecordID: id, TenantID: ctTenant, RetailerChain: "fathalla", Year: year, MonthNum: 1,
			CustomerName: "Fathalla", ItemCode: "FGCL-0550-0001", ItemName: "Test SKU", UnitsPerCarton: 12,
			NetQtyCases: 10, NetValueEGP: val, TransactionType: "مسحوبات بيع (Sale)",
		}
	}
	if err := c.SetSellInRecords(ctx, ctTenant, "ct.xlsx", []domain.SellInRecord{si("si-2026", 2026, 12000), si("si-2025", 2025, 4000)}); err != nil {
		t.Fatal(err)
	}
	return chainTermsFixture{c: c, ctx: ctx}
}

func (f chainTermsFixture) dash(t *testing.T, year int) *domain.CPFRDashboardPayload {
	t.Helper()
	p, err := f.c.GetCPFRDashboard(f.ctx, ctTenant, CPFRFilter{RetailerChain: "fathalla", Year: year})
	if err != nil {
		t.Fatal(err)
	}
	return p
}

// Item 4: with no year filter the matched card summed Jan of 2025 AND Jan of 2026 under a "2026" label.
func TestMatchedWindowIsASingleYear(t *testing.T) {
	f := newChainTermsFixture(t)
	p := f.dash(t, 0)
	if p.MatchedMonthsCount != 1 {
		t.Fatalf("matched window must hold one month of one year, got %d", p.MatchedMonthsCount)
	}
	if !near(p.MatchedSellInValueExclVATEGP, 12000) {
		t.Fatalf("matched Sell-In must be the 2026 net (12000), got %.2f", p.MatchedSellInValueExclVATEGP)
	}
	if !near(p.MatchedSellOutPOSValueEGP, 12000) {
		t.Fatalf("matched POS must be the 2026 value (12000), got %.2f", p.MatchedSellOutPOSValueEGP)
	}
	// The monthly table still lists both years.
	if len(p.MonthlyReconciliation) != 2 {
		t.Fatalf("monthly table must keep both years, got %d rows", len(p.MonthlyReconciliation))
	}
	// An explicit year gives the same window.
	p26 := f.dash(t, 2026)
	if !near(p26.MatchedSellInValueExclVATEGP, 12000) || !near(p26.MatchedSellOutPOSValueEGP, 12000) {
		t.Fatalf("year=2026 window differs: %.2f / %.2f", p26.MatchedSellInValueExclVATEGP, p26.MatchedSellOutPOSValueEGP)
	}
}

// Chain margin compares excl-VAT POS with excl-VAT factory cost (cost incl. VAT ÷ (1 + VAT)).
func TestChainMarginUsesSameVATBasis(t *testing.T) {
	f := newChainTermsFixture(t)
	p := f.dash(t, 2026)
	m := p.MonthlyReconciliation[0]
	// Cost incl 114 × 0.9 = 102.6 per piece × 100 = 10260 incl; excl = 9000.
	if !near(m.SellOutFactoryCostInclVATEGP, 10260) || !near(m.SellOutFactoryCostExclVATEGP, 9000) {
		t.Fatalf("cost incl/excl: %.2f / %.2f", m.SellOutFactoryCostInclVATEGP, m.SellOutFactoryCostExclVATEGP)
	}
	if !near(m.ChainGrossMarginEGP, 3000) || !near(m.ChainGrossMarginPct, 25) {
		t.Fatalf("margin must be 12000-9000=3000 (25%%), got %.2f (%.2f%%)", m.ChainGrossMarginEGP, m.ChainGrossMarginPct)
	}
	if !near(p.MatchedChainGrossMarginEGP, 3000) || !near(p.MatchedSellOutFactoryCostExclVATEGP, 9000) {
		t.Fatalf("matched margin/cost excl: %.2f / %.2f", p.MatchedChainGrossMarginEGP, p.MatchedSellOutFactoryCostExclVATEGP)
	}
}

func sellInRow(t *testing.T, f chainTermsFixture, year int) domain.SellInRecord {
	t.Helper()
	rows, _, err := f.c.GetSellInRecords(f.ctx, ctTenant, SellInRecordFilter{RetailerChain: "fathalla", Year: year})
	if err != nil || len(rows) != 1 {
		t.Fatalf("sell-in rows: %d err=%v", len(rows), err)
	}
	return rows[0]
}

// Saved chain terms drive cost, margin, VAT and the Sell-In row; changing them needs no re-upload.
func TestChainTermsDriveCostMarginAndSellInVAT(t *testing.T) {
	f := newChainTermsFixture(t)

	// Defaults: master VAT 14%, no extra discount.
	row := sellInRow(t, f, 2026)
	if row.VATRate != 0.14 || !near(row.GrossValueInclVATEGP, 13680) || !near(row.VATAmountEGP, 1680) || row.ExtraDiscountPct != 0 {
		t.Fatalf("default row VAT: rate=%v gross=%.2f vat=%.2f extra=%v", row.VATRate, row.GrossValueInclVATEGP, row.VATAmountEGP, row.ExtraDiscountPct)
	}

	// Chain: invoice 10%, extra 20%, VAT 5%.
	f.c.SetChainDiscountProfiles(ctTenant, []domain.ChainDiscountProfile{
		{Chain: "Fathalla", InvoiceDiscountPct: 10, AdditionalDiscountPct: 20, VATRatePct: f64(5)},
	})
	row = sellInRow(t, f, 2026)
	if row.VATRate != 0.05 || !near(row.GrossValueInclVATEGP, 12600) || !near(row.VATAmountEGP, 600) {
		t.Fatalf("chain VAT must drive the row: rate=%v gross=%.2f vat=%.2f", row.VATRate, row.GrossValueInclVATEGP, row.VATAmountEGP)
	}
	if row.InvoiceDiscountPct != 10 || row.ExtraDiscountPct != 20 {
		t.Fatalf("row discounts: inv=%v extra=%v", row.InvoiceDiscountPct, row.ExtraDiscountPct)
	}
	// Dashboard: VAT total and factory cost follow the chain terms.
	p := f.dash(t, 2026)
	if !near(p.YTD2026VATAmountEGP, 600) {
		t.Fatalf("dashboard VAT: %.2f", p.YTD2026VATAmountEGP)
	}
	// 100 pcs × (list excl 100 × (1-10%) × (1-20%)) = 7200 excl; incl at 5% = 7560.
	m := p.MonthlyReconciliation[0]
	if !near(m.SellOutFactoryCostExclVATEGP, 7200) || !near(m.SellOutFactoryCostInclVATEGP, 7560) {
		t.Fatalf("chain cost excl/incl: %.2f / %.2f", m.SellOutFactoryCostExclVATEGP, m.SellOutFactoryCostInclVATEGP)
	}
	if !near(m.ChainGrossMarginEGP, 4800) {
		t.Fatalf("margin after extra discount: %.2f", m.ChainGrossMarginEGP)
	}

	// Raising the extra discount lowers cost and raises margin.
	f.c.SetChainDiscountProfiles(ctTenant, []domain.ChainDiscountProfile{
		{Chain: "fathalla", InvoiceDiscountPct: 10, AdditionalDiscountPct: 30, VATRatePct: f64(5)},
	})
	m2 := f.dash(t, 2026).MonthlyReconciliation[0]
	if m2.SellOutFactoryCostExclVATEGP >= m.SellOutFactoryCostExclVATEGP || m2.ChainGrossMarginEGP <= m.ChainGrossMarginEGP {
		t.Fatalf("higher extra discount must lower cost / raise margin: %.2f→%.2f margin %.2f→%.2f",
			m.SellOutFactoryCostExclVATEGP, m2.SellOutFactoryCostExclVATEGP, m.ChainGrossMarginEGP, m2.ChainGrossMarginEGP)
	}

	// A profile for another chain changes nothing for Fathalla.
	f.c.SetChainDiscountProfiles(ctTenant, []domain.ChainDiscountProfile{{Chain: "kazyon", InvoiceDiscountPct: 40, AdditionalDiscountPct: 30, VATRatePct: f64(0)}})
	row = sellInRow(t, f, 2026)
	if row.VATRate != 0.14 || !near(row.GrossValueInclVATEGP, 13680) {
		t.Fatalf("other chain's profile leaked: rate=%v gross=%.2f", row.VATRate, row.GrossValueInclVATEGP)
	}

	// Removing the profile restores the defaults (still no re-upload).
	f.c.SetChainDiscountProfiles(ctTenant, nil)
	back := f.dash(t, 2026).MonthlyReconciliation[0]
	if !near(back.ChainGrossMarginEGP, 3000) {
		t.Fatalf("defaults must return: margin %.2f", back.ChainGrossMarginEGP)
	}
}

func TestChainDiscountProfilesSnapshotIncludesVAT(t *testing.T) {
	f := newChainTermsFixture(t)
	f.c.SetChainDiscountProfiles(ctTenant, []domain.ChainDiscountProfile{
		{Chain: "B", InvoiceDiscountPct: 1}, {Chain: "a", VATRatePct: f64(7)},
	})
	got := f.c.ChainDiscountProfilesSnapshot(f.ctx, ctTenant)
	if len(got) != 2 || got[0].Chain != "a" || got[0].VATRatePct == nil || *got[0].VATRatePct != 7 || got[1].VATRatePct != nil {
		t.Fatalf("snapshot: %+v", got)
	}
}

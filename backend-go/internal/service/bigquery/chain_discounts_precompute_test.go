package bigquery

import (
	"context"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func newSeededTestClient(t *testing.T) *Client {
	t.Helper()
	dir := t.TempDir()
	// Copy (read-only) the real product master so seeded sell-out rows match master prices.
	if raw, err := os.ReadFile("../../../data/product_master/tenant-adeco.json"); err == nil && len(raw) > 0 {
		_ = os.WriteFile(filepath.Join(dir, "tenant-adeco.json"), raw, 0o644)
	}
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", dir)
	c := NewClient("test-project", "tashil_analytics", true)
	if len(c.tenantChains("tenant-adeco")) == 0 {
		t.Skip("no seeded tenant-adeco data in mock client")
	}
	return c
}

func mustJSON(t *testing.T, v interface{}) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestResolveFactoryUnitCostForChainFormula(t *testing.T) {
	pm := domain.ProductMasterItem{NetUnitInvoiceCost: 90, UnitPriceInclVAT: 100}
	prof := domain.ChainDiscountProfile{Chain: "kazyon", InvoiceDiscountPct: 20, AdditionalDiscountPct: 5}
	c, src, _ := resolveFactoryUnitCostForChain(0, pm, true, prof, true)
	if math.Abs(c-76) > 1e-9 || src != costSourceMasterListChainProfile {
		t.Fatalf("100 × 0.80 × 0.95 = 76 expected, got %v %s", c, src)
	}
	// No profile: exactly the default path (10% invoice / 0% additional).
	c1, s1, r1 := resolveFactoryUnitCostForChain(40, pm, true, domain.ChainDiscountProfile{}, false)
	c2, s2, r2 := resolveRealFactoryUnitCost(40, pm, true)
	if c1 != c2 || s1 != s2 || r1 != r2 {
		t.Fatalf("no-profile path must equal default path")
	}
	// Profile but item not in master: sheet cost, unchanged.
	if c, src, _ := resolveFactoryUnitCostForChain(40, domain.ProductMasterItem{}, false, prof, true); c != 40 || src != costSourceSellOutSheet {
		t.Fatalf("unmatched item keeps sheet cost, got %v %s", c, src)
	}
}

func TestChainDiscountDefaultNumbersUnchanged(t *testing.T) {
	c := newSeededTestClient(t)
	ctx := context.Background()
	before, err := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{})
	if err != nil {
		t.Fatal(err)
	}
	c.SetChainDiscountProfiles("tenant-adeco", nil)
	after, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{})
	if mustJSON(t, before) != mustJSON(t, after) {
		t.Fatalf("empty profile list must leave the dashboard unchanged")
	}
	// A profile for a chain with no data changes nothing either.
	c.SetChainDiscountProfiles("tenant-adeco", []domain.ChainDiscountProfile{{Chain: "no-such-chain", InvoiceDiscountPct: 30}})
	after2, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{})
	if mustJSON(t, before) != mustJSON(t, after2) {
		t.Fatalf("profile for an unknown chain must leave the dashboard unchanged")
	}
}

func monthlyCost(p *domain.CPFRDashboardPayload) float64 {
	s := 0.0
	for _, m := range p.MonthlyReconciliation {
		s += m.SellOutFactoryCostInclVATEGP
	}
	return s
}

func TestChainDiscountProfileChangesThatChainCostOnly(t *testing.T) {
	c := newSeededTestClient(t)
	ctx := context.Background()
	chains := c.tenantChains("tenant-adeco")
	target := ""
	var base *domain.CPFRDashboardPayload
	var others []string
	for _, ch := range chains {
		p, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{RetailerChain: ch})
		if target == "" && monthlyCost(p) > 0 {
			target, base = ch, p
			continue
		}
		others = append(others, ch)
	}
	if target == "" {
		t.Fatalf("no seeded chain with costed sell-out among %v", chains)
	}
	c.SetChainDiscountProfiles("tenant-adeco", []domain.ChainDiscountProfile{{Chain: target, InvoiceDiscountPct: 50, AdditionalDiscountPct: 10}})
	disc, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{RetailerChain: target})
	if monthlyCost(disc) >= monthlyCost(base) {
		t.Fatalf("a 50%%+10%% profile must lower %s cost: before %.2f after %.2f", target, monthlyCost(base), monthlyCost(disc))
	}
	for _, other := range others {
		c.SetChainDiscountProfiles("tenant-adeco", nil)
		o1, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{RetailerChain: other})
		c.SetChainDiscountProfiles("tenant-adeco", []domain.ChainDiscountProfile{{Chain: target, InvoiceDiscountPct: 50, AdditionalDiscountPct: 10}})
		o2, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{RetailerChain: other})
		if monthlyCost(o1) != monthlyCost(o2) {
			t.Fatalf("profile for %s must not change %s cost", target, other)
		}
	}
}

// onTheFlyAggregates recomputes the three tables directly from GetCPFRDashboard (no cache).
func onTheFlyAggregates(t *testing.T, c *Client, version int64, at time.Time) *domain.AnalyticsAggregates {
	t.Helper()
	out := &domain.AnalyticsAggregates{TenantID: normalizeTenantKey("tenant-adeco"), Version: version, UpdatedAt: at,
		ChainProfitMonthly: []domain.AggChainProfitMonthly{}, SkuCostMargin: []domain.AggSkuCostMargin{}, SellThrough: []domain.AggSellThrough{}}
	for _, ch := range append([]string{"all"}, c.tenantChains("tenant-adeco")...) {
		p, err := c.GetCPFRDashboard(context.Background(), "tenant-adeco", CPFRFilter{RetailerChain: ch})
		if err != nil {
			t.Fatal(err)
		}
		a, b, d := BuildAnalyticsAggregatesFromPayload(ch, p, version, at)
		out.ChainProfitMonthly = append(out.ChainProfitMonthly, a...)
		out.SkuCostMargin = append(out.SkuCostMargin, b...)
		out.SellThrough = append(out.SellThrough, d...)
	}
	return out
}

func assertAggregatesEqualOnTheFly(t *testing.T, c *Client, agg *domain.AnalyticsAggregates) {
	t.Helper()
	want := onTheFlyAggregates(t, c, agg.Version, agg.UpdatedAt)
	if !reflect.DeepEqual(agg, want) {
		t.Fatalf("precomputed layer differs from on-the-fly computation\nprecomputed=%s\non-the-fly=%s", mustJSON(t, agg)[:400], mustJSON(t, want)[:400])
	}
	// And the totals row (chain "all") matches the dashboard's own matched-period totals.
	all, _ := c.GetCPFRDashboard(context.Background(), "tenant-adeco", CPFRFilter{})
	var sales, cost float64
	for _, r := range agg.ChainProfitMonthly {
		if r.Chain == "all" {
			sales += r.SellOutValueEGP
			cost += r.FactoryCostInclVATEGP
		}
	}
	var wantSales, wantCost float64
	for _, m := range all.MonthlyReconciliation {
		wantSales += m.SellOutValueEGP
		wantCost += m.SellOutFactoryCostInclVATEGP
	}
	if sales != wantSales || cost != wantCost {
		t.Fatalf("all-chains totals differ: sales %.2f vs %.2f cost %.2f vs %.2f", sales, wantSales, cost, wantCost)
	}
}

func TestPrecomputedLayerMatchesOnTheFlyAndInvalidates(t *testing.T) {
	c := newSeededTestClient(t)
	ctx := context.Background()

	agg1, err := c.GetAnalyticsAggregates(ctx, "tenant-adeco")
	if err != nil {
		t.Fatal(err)
	}
	if len(agg1.ChainProfitMonthly) == 0 || len(agg1.SellThrough) == 0 {
		t.Fatalf("expected non-empty materialized tables")
	}
	assertAggregatesEqualOnTheFly(t, c, agg1)

	// No source change: served from memory (same object, same version).
	agg1b, _ := c.GetAnalyticsAggregates(ctx, "tenant-adeco")
	if agg1b != agg1 {
		t.Fatalf("expected cached layer when nothing changed")
	}
	p1, v1, _ := c.GetCPFRDashboardCached(ctx, "tenant-adeco", CPFRFilter{})
	p1b, v1b, _ := c.GetCPFRDashboardCached(ctx, "tenant-adeco", CPFRFilter{})
	if p1 != p1b || v1 != v1b {
		t.Fatalf("expected cached dashboard when nothing changed")
	}
	fresh, _ := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{})
	if mustJSON(t, p1) != mustJSON(t, fresh) {
		t.Fatalf("cached dashboard differs from on-the-fly")
	}

	// Source change (chain discount profile) -> new version, recomputed, still equal on-the-fly.
	chains := c.tenantChains("tenant-adeco")
	c.SetChainDiscountProfiles("tenant-adeco", []domain.ChainDiscountProfile{{Chain: chains[0], InvoiceDiscountPct: 25, AdditionalDiscountPct: 3}})
	agg2, _ := c.GetAnalyticsAggregates(ctx, "tenant-adeco")
	if agg2.Version <= agg1.Version || agg2 == agg1 {
		t.Fatalf("expected recompute after source change: v1=%d v2=%d", agg1.Version, agg2.Version)
	}
	assertAggregatesEqualOnTheFly(t, c, agg2)
	p2, v2, _ := c.GetCPFRDashboardCached(ctx, "tenant-adeco", CPFRFilter{})
	if v2 <= v1 || p2 == p1 {
		t.Fatalf("expected dashboard recompute after source change")
	}

	// Source change (product master edit) -> invalidated again.
	if _, err := c.UpsertProductMasterItem(ctx, "tenant-adeco", domain.ProductMasterItem{ItemCode: "ZZ-TEST-1", OfficialName: "test", UnitsPerCarton: 6, VATRate: 0.14, UnitPriceExclVAT: 10}); err != nil {
		t.Fatal(err)
	}
	agg3, _ := c.GetAnalyticsAggregates(ctx, "tenant-adeco")
	if agg3.Version <= agg2.Version {
		t.Fatalf("expected recompute after product master change")
	}
	assertAggregatesEqualOnTheFly(t, c, agg3)
}

type fakeAggWriter struct{ got chan *domain.AnalyticsAggregates }

func (f *fakeAggWriter) WriteAnalyticsAggregates(_ context.Context, a *domain.AnalyticsAggregates) error {
	f.got <- a
	return nil
}

// backgroundComputeWait bounds one full aggregates compute over the seeded dataset. It is not a race:
// a single compute (4 chains) measured 7.7s on an M-series Mac, and the CI runner runs it 2-3x slower
// while other package tests run in parallel, so the old 20s wait failed intermittently.
const backgroundComputeWait = 90 * time.Second

func TestPrecomputedLayerRecomputesInBackgroundAndMirrors(t *testing.T) {
	c := newSeededTestClient(t)
	old := recomputeDelay
	recomputeDelay = 10 * time.Millisecond
	defer func() { recomputeDelay = old }()
	w := &fakeAggWriter{got: make(chan *domain.AnalyticsAggregates, 8)}
	c.WithAggregatesWriter(w, "tenant-adeco")
	var first *domain.AnalyticsAggregates
	select {
	case first = <-w.got:
	case <-time.After(backgroundComputeWait):
		t.Fatal("no background compute after attaching writer")
	}
	c.SetChainDiscountProfiles("tenant-adeco", []domain.ChainDiscountProfile{{Chain: "x", InvoiceDiscountPct: 5}})
	select {
	case a := <-w.got:
		if a.Version <= first.Version {
			t.Fatalf("expected newer version mirrored, got %d after %d", a.Version, first.Version)
		}
	case <-time.After(backgroundComputeWait):
		t.Fatal("no background recompute after source change")
	}
}

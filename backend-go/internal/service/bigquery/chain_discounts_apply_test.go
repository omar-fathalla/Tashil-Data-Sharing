package bigquery

import (
	"context"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const applyTenant = "tenant-applytest"

func newApplyFixture(t *testing.T) *Client {
	t.Helper()
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	c := NewClient("p", "d", true)
	if _, err := c.UpsertProductMasterItem(context.Background(), applyTenant, domain.ProductMasterItem{
		ItemCode: "FGCL-0550-0001", OfficialName: "SKU", UnitsPerCarton: 10, VATRate: 0.14, UnitPriceExclVAT: 10,
	}); err != nil {
		t.Fatal(err)
	}
	c.ReplaceSellInRecords(applyTenant, []domain.SellInRecord{
		applyRow("f1", "fathalla", 100), applyRow("f2", "fathalla", 100),
		applyRow("k1", "kazyon", 100), applyRow("k2", "kazyon", 100),
		applyRow("g1", "gomla", 100),
	})
	return c
}

func applyRow(id, chain string, net float64) domain.SellInRecord {
	return domain.SellInRecord{
		RecordID: id, TenantID: applyTenant, RetailerChain: chain, Year: 2026, MonthNum: 9,
		CustomerName: chain, ItemCode: "FGCL-0550-0001", ItemName: "SKU", NetQtyCases: 1, NetValueEGP: net,
		TransactionType: "مسحوبات بيع (Sale)",
	}
}

func applyRows(c *Client) map[string]domain.SellInRecord {
	out := map[string]domain.SellInRecord{}
	for _, r := range c.SellInRecordsSnapshot(applyTenant) {
		out[r.RecordID] = r
	}
	return out
}

func TestSetChainDiscountProfilesReenrichesOnlyChangedChains(t *testing.T) {
	c := newApplyFixture(t)

	// Stamp rows so a re-enrichment is detectable: enrichSellInRecordLocked always rewrites VATRate.
	const sentinel = 0.777
	c.mu.Lock()
	recs := c.sellInRecords[normalizeTenantKey(applyTenant)]
	for i := range recs {
		recs[i].VATRate = sentinel
	}
	c.mu.Unlock()

	c.SetChainDiscountProfiles(applyTenant, []domain.ChainDiscountProfile{
		{Chain: "Kazyon", InvoiceDiscountPct: 20, AdditionalDiscountPct: 5, VATRatePct: f64(5)},
	})
	rows := applyRows(c)
	for _, id := range []string{"k1", "k2"} {
		if r := rows[id]; r.VATRate != 0.05 || r.InvoiceDiscountPct != 20 || r.ExtraDiscountPct != 5 {
			t.Fatalf("%s must follow the new terms: %+v", id, r)
		}
	}
	for _, id := range []string{"f1", "f2", "g1"} {
		if rows[id].VATRate != sentinel {
			t.Fatalf("%s belongs to an unchanged chain and must not be re-enriched (VAT %v)", id, rows[id].VATRate)
		}
	}

	// Re-saving the same terms (any case / whitespace in the name) touches nothing.
	c.mu.Lock()
	recs = c.sellInRecords[normalizeTenantKey(applyTenant)]
	for i := range recs {
		recs[i].VATRate = sentinel
	}
	c.mu.Unlock()
	ver := c.AnalyticsSourceVersion()
	c.SetChainDiscountProfiles(applyTenant, []domain.ChainDiscountProfile{
		{Chain: " kazyon ", InvoiceDiscountPct: 20, AdditionalDiscountPct: 5, VATRatePct: f64(5)},
	})
	for id, r := range applyRows(c) {
		if r.VATRate != sentinel {
			t.Fatalf("unchanged save re-enriched %s", id)
		}
	}
	if c.AnalyticsSourceVersion() != ver {
		t.Fatal("an unchanged save must not invalidate cached analytics")
	}

	// Deleting a chain's profile re-prices exactly that chain back to the defaults.
	c.SetChainDiscountProfiles(applyTenant, nil)
	rows = applyRows(c)
	if r := rows["k1"]; r.VATRate != 0.14 || r.InvoiceDiscountPct != 10 || r.ExtraDiscountPct != 0 {
		t.Fatalf("deleted profile must restore defaults: %+v", r)
	}
	if rows["f1"].VATRate != sentinel {
		t.Fatal("unrelated chain re-enriched on delete")
	}
	if c.AnalyticsSourceVersion() == ver {
		t.Fatal("a changed list must invalidate cached analytics")
	}
}

// The row's chain is resolved from the customer name exactly like enrichment does, so a row stored on
// the generic "fathalla" chain whose customer maps to another chain follows that chain's terms.
func TestChangedChainMatchesCustomerResolvedRows(t *testing.T) {
	c := newApplyFixture(t)
	norm := normalizeTenantKey(applyTenant)
	c.mu.Lock()
	recs := c.sellInRecords[norm]
	for i := range recs {
		if recs[i].RecordID == "f1" {
			recs[i].RetailerChain, recs[i].CustomerName = "fathalla", "بيت الجملة فرع 1"
		}
	}
	c.mu.Unlock()

	c.SetChainDiscountProfiles(applyTenant, []domain.ChainDiscountProfile{{Chain: "beet-elgomla", InvoiceDiscountPct: 22}})
	rows := applyRows(c)
	if r := rows["f1"]; r.RetailerChain != "beet-elgomla" || r.InvoiceDiscountPct != 22 {
		t.Fatalf("customer-resolved row must follow its chain's terms: %+v", r)
	}
	if r := rows["f2"]; r.InvoiceDiscountPct != 10 {
		t.Fatalf("plain fathalla row must keep the defaults: %+v", r)
	}
}

func TestSetChainDiscountProfilesComputesOutsideWriteLock(t *testing.T) {
	c := newApplyFixture(t)
	reached := make(chan struct{})
	reenrichBeforeSwapHook = func() { close(reached) }
	defer func() { reenrichBeforeSwapHook = nil }()

	// A long analytics read holds the read lock; the compute phase must not wait for it.
	c.mu.RLock()
	done := make(chan struct{})
	go func() {
		c.SetChainDiscountProfiles(applyTenant, []domain.ChainDiscountProfile{{Chain: "kazyon", InvoiceDiscountPct: 30}})
		close(done)
	}()
	select {
	case <-reached:
	case <-time.After(2 * time.Second):
		c.mu.RUnlock()
		t.Fatal("re-enrichment compute waited for the analytics read lock")
	}
	select {
	case <-done:
		c.mu.RUnlock()
		t.Fatal("swap must wait for in-flight readers")
	case <-time.After(50 * time.Millisecond):
	}
	c.mu.RUnlock()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("swap did not complete after readers finished")
	}
	if r := applyRows(c)["k1"]; r.InvoiceDiscountPct != 30 {
		t.Fatalf("swapped rows: %+v", r)
	}
}

// An upload landing between compute and swap must win: the stale copy is dropped and the new rows are
// priced with the new terms.
func TestSetChainDiscountProfilesDiscardsStaleCopyAfterConcurrentUpload(t *testing.T) {
	c := newApplyFixture(t)
	calls := 0
	reenrichBeforeSwapHook = func() {
		calls++
		if calls == 1 {
			c.ReplaceSellInRecords(applyTenant, []domain.SellInRecord{
				applyRow("n1", "kazyon", 500), applyRow("n2", "fathalla", 500),
			})
		}
	}
	defer func() { reenrichBeforeSwapHook = nil }()

	c.SetChainDiscountProfiles(applyTenant, []domain.ChainDiscountProfile{{Chain: "kazyon", InvoiceDiscountPct: 35, AdditionalDiscountPct: 5}})
	rows := applyRows(c)
	if len(rows) != 2 || rows["k1"].RecordID != "" {
		t.Fatalf("stale rows resurrected: %v", rows)
	}
	if r := rows["n1"]; r.NetValueEGP != 500 || r.InvoiceDiscountPct != 35 || r.ExtraDiscountPct != 5 {
		t.Fatalf("uploaded row must carry the new terms: %+v", r)
	}
	if calls < 2 {
		t.Fatalf("a conflicting swap must be recomputed, hook calls=%d", calls)
	}
}

// Persistent conflicts fall back to an in-place re-enrichment so the terms always end up applied.
func TestSetChainDiscountProfilesFallsBackAfterRepeatedConflicts(t *testing.T) {
	c := newApplyFixture(t)
	reenrichBeforeSwapHook = func() {
		c.mu.Lock()
		c.noteSellInDataChanged()
		c.mu.Unlock()
	}
	defer func() { reenrichBeforeSwapHook = nil }()
	c.SetChainDiscountProfiles(applyTenant, []domain.ChainDiscountProfile{{Chain: "kazyon", InvoiceDiscountPct: 25}})
	if r := applyRows(c)["k2"]; r.InvoiceDiscountPct != 25 {
		t.Fatalf("fallback must apply the terms: %+v", r)
	}
}

func TestNormalizeArabicCustomerFoldsLetterVariants(t *testing.T) {
	if got := normalizeArabicCustomer("  أسواق  إيمان آمنة  مدرسى "); got != "اسواق ايمان امنه مدرسي" {
		t.Fatalf("got %q", got)
	}
}

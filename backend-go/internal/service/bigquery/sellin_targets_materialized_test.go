package bigquery

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// storedDerived returns the materialized Sell-In records of a Sell-Out target held in memory.
func storedDerived(c *Client, tenant, sourceID string) []domain.TargetRecord {
	c.mu.RLock()
	defer c.mu.RUnlock()
	var out []domain.TargetRecord
	for _, t := range c.targets[normalizeTenantKey(tenant)] {
		if t.TargetType == "sell_in" && t.SourceTargetID == sourceID {
			out = append(out, t)
		}
	}
	return out
}

func persistedTargets(t *testing.T, tenant string) []domain.TargetRecord {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(os.Getenv("TASHIL_TARGETS_DIR"), normalizeTenantKey(tenant)+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var list []domain.TargetRecord
	if err := json.Unmarshal(raw, &list); err != nil {
		t.Fatal(err)
	}
	return list
}

func linePieces(lines []domain.DerivedSellInLine) int64 {
	var n int64
	for _, l := range lines {
		n += l.Pieces
	}
	return n
}

// stripDerived simulates targets saved before materialization existed.
func stripDerived(c *Client, tenant string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	norm := normalizeTenantKey(tenant)
	var kept []domain.TargetRecord
	for _, t := range c.targets[norm] {
		if !isDerivedSellInRecord(t) {
			kept = append(kept, t)
		}
	}
	c.targets[norm] = kept
}

func TestSellOutCreateMaterializesDerivedSellInQuantities(t *testing.T) {
	c := newDerivedFixture(t)
	so := dsiSellOutTarget(t, c, 2026, 3, 1000, 14000)

	recs := storedDerived(c, dsiTenant, so.ID)
	if len(recs) != 1 {
		t.Fatalf("want one derived record, got %d", len(recs))
	}
	d := recs[0]
	if d.ID != DerivedSellInTargetID(so.ID) || !d.Derived || d.TargetType != "sell_in" || d.SourceUpdatedAt != so.UpdatedAt ||
		d.DerivedVersion != derivedSellInFormatVersion || d.Year != 2026 || d.Month != 3 {
		t.Fatalf("derived record identity: %+v", d)
	}
	if d.TargetUnits != 1000 || linePieces(d.DerivedLines) != 1000 {
		t.Fatalf("pieces 1:1 with the Sell-Out target: units=%v lines=%d", d.TargetUnits, linePieces(d.DerivedLines))
	}
	if d.TargetRevenueEGP != 0 {
		t.Fatalf("value is computed on read, never stored: %v", d.TargetRevenueEGP)
	}
	codes := map[string]bool{}
	for _, l := range d.DerivedLines {
		if l.BranchKey == "" || l.Pieces <= 0 {
			t.Fatalf("each line is a branch x SKU quantity: %+v", l)
		}
		codes[l.ItemCode] = true
	}
	if !codes["FGCL-0001"] || !codes["FGCL-0003"] {
		t.Fatalf("lines carry the Product Master item code: %+v", d.DerivedLines)
	}

	found := false
	for _, p := range persistedTargets(t, dsiTenant) {
		if p.ID == d.ID && p.Derived && len(p.DerivedLines) == len(d.DerivedLines) {
			found = true
		}
	}
	if !found {
		t.Fatal("derived record must be persisted with the Sell-Out target")
	}

	it := derivedSummary(t, c).Items[0]
	if it.ID != d.ID || it.TargetUnits != 1000 || it.TargetRevenueEGP <= 0 {
		t.Fatalf("read serves the stored record valued from the Product Master: %+v", it)
	}
}

func TestSellOutEditReplacesAndDeleteRemovesDerivedSellIn(t *testing.T) {
	c := newDerivedFixture(t)
	so := dsiSellOutTarget(t, c, 2026, 3, 1000, 14000)
	edited := dsiSellOutTarget(t, c, 2026, 3, 400, 5600)
	if edited.ID != so.ID {
		t.Fatalf("same scope updates the same Sell-Out target: %s vs %s", edited.ID, so.ID)
	}
	recs := storedDerived(c, dsiTenant, so.ID)
	if len(recs) != 1 || recs[0].TargetUnits != 400 || linePieces(recs[0].DerivedLines) != 400 || recs[0].SourceUpdatedAt != edited.UpdatedAt {
		t.Fatalf("edit replaces the derived record: %+v", recs)
	}
	if s := derivedSummary(t, c); len(s.Items) != 1 || s.Items[0].TargetUnits != 400 {
		t.Fatalf("read follows the edit: %+v", s.Items)
	}

	if err := c.DeleteTarget(context.Background(), dsiTenant, so.ID); err != nil {
		t.Fatal(err)
	}
	if recs := storedDerived(c, dsiTenant, so.ID); len(recs) != 0 {
		t.Fatalf("delete removes the derived record: %+v", recs)
	}
	for _, p := range persistedTargets(t, dsiTenant) {
		if p.SourceTargetID == so.ID {
			t.Fatalf("derived record still persisted: %+v", p)
		}
	}
	if s := derivedSummary(t, c); len(s.Items) != 0 {
		t.Fatalf("no Sell-In target after the Sell-Out delete: %+v", s.Items)
	}
}

func TestDerivedSellInValueFollowsCurrentCostPrice(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	before := skuByCode(derivedSummary(t, c).Items[0].ChainSKUTotals, "FGCL-0001")

	if _, err := c.SetProductMaster(context.Background(), dsiTenant, &domain.ProductMasterSummaryResponse{
		TenantID: dsiTenant,
		Items: []domain.ProductMasterItem{
			{SerialNo: 1, ItemCode: "FGCL-0001", ItemCodePrefix: "FGCL", Barcode: "6220000000011", OfficialName: "صنف 1", Brand: dsiBrandA, UnitsPerCarton: 24, NetUnitInvoiceCost: 30},
			{SerialNo: 2, ItemCode: "FGCL-0002", ItemCodePrefix: "FGCL", Barcode: "6220000000028", OfficialName: "صنف 2", Brand: dsiBrandB, UnitsPerCarton: 0, NetUnitInvoiceCost: 5},
			{SerialNo: 3, ItemCode: "FGCL-0003", ItemCodePrefix: "FGCL", Barcode: "6220000000035", OfficialName: "صنف 3", Brand: "", UnitsPerCarton: 6, NetUnitInvoiceCost: 20},
		},
	}); err != nil {
		t.Fatal(err)
	}
	after := skuByCode(derivedSummary(t, c).Items[0].ChainSKUTotals, "FGCL-0001")
	if after.TargetUnits != before.TargetUnits {
		t.Fatalf("stored pieces do not change with the price list: %v -> %v", before.TargetUnits, after.TargetUnits)
	}
	if after.TargetRevenueEGP != round2(after.TargetUnits*30) || after.TargetRevenueEGP == before.TargetRevenueEGP {
		t.Fatalf("value = pieces x the current cost: before=%v after=%v pieces=%v", before.TargetRevenueEGP, after.TargetRevenueEGP, after.TargetUnits)
	}
	if after.TargetCases == nil || *after.TargetCases != round2(after.TargetUnits/24) {
		t.Fatalf("cases = pieces / the current pack size: %+v", after.TargetCases)
	}
}

func TestDerivedSellInLazyBackfillIsIdempotent(t *testing.T) {
	c := newDerivedFixture(t)
	so1 := dsiSellOutTarget(t, c, 2026, 3, 1000, 14000)
	so2 := dsiSellOutTarget(t, c, 2026, 4, 500, 7000)
	stripDerived(c, dsiTenant)

	var calls atomic.Int32
	bd := func(ctx context.Context, tr domain.TargetRecord) (domain.TargetBreakdownResponse, bool) {
		calls.Add(1)
		time.Sleep(20 * time.Millisecond)
		return domain.TargetBreakdownResponse{}, false
	}
	read := func() *domain.TargetsSummaryResponse {
		s, err := c.GetDerivedSellInTargetsSummary(context.Background(), dsiTenant, DerivedSellInOptions{Chain: "fathalla", Year: 2026, Breakdown: bd})
		if err != nil {
			t.Fatal(err)
		}
		return s
	}

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			read()
		}()
	}
	wg.Wait()
	if got := calls.Load(); got != 2 {
		t.Fatalf("concurrent first reads materialize each Sell-Out target once: %d allocations", got)
	}
	for _, id := range []string{so1.ID, so2.ID} {
		if recs := storedDerived(c, dsiTenant, id); len(recs) != 1 {
			t.Fatalf("backfill stores exactly one derived record for %s: %d", id, len(recs))
		}
	}
	persisted := 0
	for _, p := range persistedTargets(t, dsiTenant) {
		if p.Derived {
			persisted++
		}
	}
	if persisted != 2 {
		t.Fatalf("backfilled records are persisted: %d", persisted)
	}

	version := c.AnalyticsSourceVersion()
	s := read()
	if calls.Load() != 2 || c.AnalyticsSourceVersion() != version {
		t.Fatalf("a second read writes nothing: allocations=%d version %d -> %d", calls.Load(), version, c.AnalyticsSourceVersion())
	}
	if len(s.Items) != 2 || s.TotalTargetUnits != 1500 {
		t.Fatalf("backfilled read: %+v", s)
	}
}

func TestDerivedSellInOutdatedAndOrphanRecordsAreRepaired(t *testing.T) {
	c := newDerivedFixture(t)
	so := dsiSellOutTarget(t, c, 2026, 3, 1000, 14000)
	legacy := domain.TargetRecord{ID: "legacy_si_1", TenantID: dsiTenant, TargetType: "sell_in", RetailerChain: "fathalla", Year: 2026, TargetUnits: 777}
	orphan := domain.TargetRecord{ID: DerivedSellInTargetID("gone"), TenantID: dsiTenant, TargetType: "sell_in", Year: 2026,
		Derived: true, SourceTargetID: "gone", DerivedVersion: derivedSellInFormatVersion, TargetUnits: 5}
	c.mu.Lock()
	norm := normalizeTenantKey(dsiTenant)
	for i := range c.targets[norm] {
		if c.targets[norm][i].SourceTargetID == so.ID {
			c.targets[norm][i].SourceUpdatedAt = "2000-01-01T00:00:00Z"
			c.targets[norm][i].TargetUnits = 1
			c.targets[norm][i].DerivedLines = []domain.DerivedSellInLine{{SKUName: "x", Pieces: 1}}
		}
	}
	c.targets[norm] = append(c.targets[norm], legacy, orphan)
	c.mu.Unlock()

	s := derivedSummary(t, c)
	if len(s.Items) != 1 || s.Items[0].TargetUnits != 1000 {
		t.Fatalf("an outdated derived record is rebuilt from its Sell-Out target: %+v", s.Items)
	}
	recs := storedDerived(c, dsiTenant, so.ID)
	if len(recs) != 1 || recs[0].SourceUpdatedAt != so.UpdatedAt || linePieces(recs[0].DerivedLines) != 1000 {
		t.Fatalf("rebuilt record stored: %+v", recs)
	}
	if len(storedDerived(c, dsiTenant, "gone")) != 0 {
		t.Fatal("orphaned derived record removed")
	}
	keptLegacy := false
	for _, p := range persistedTargets(t, dsiTenant) {
		if p.ID == "legacy_si_1" && p.TargetUnits == 777 {
			keptLegacy = true
		}
	}
	if !keptLegacy {
		t.Fatal("legacy manual Sell-In records are never deleted")
	}
}

func TestDeferredSellOutWritesMaterializeInOneBatch(t *testing.T) {
	c := newDerivedFixture(t)
	ctx := WithDeferredSellInMaterialization(context.Background())
	var ids []string
	for m := 1; m <= 3; m++ {
		tr, err := c.UpsertTarget(ctx, dsiTenant, domain.TargetRecord{TargetType: "sell_out", RetailerChain: "fathalla", Year: 2026, Month: m, TargetUnits: 100})
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, tr.ID)
		if len(storedDerived(c, dsiTenant, tr.ID)) != 0 {
			t.Fatal("deferred write leaves materialization to the batch")
		}
	}
	if err := c.MaterializeDerivedSellInTargets(context.Background(), dsiTenant); err != nil {
		t.Fatal(err)
	}
	for _, id := range ids {
		if recs := storedDerived(c, dsiTenant, id); len(recs) != 1 || recs[0].TargetUnits != 100 {
			t.Fatalf("batch materialized %s: %+v", id, recs)
		}
	}
}

func TestDerivedBreakdownsRunInParallelAndKeepTargetOrder(t *testing.T) {
	c := newDerivedFixture(t)
	works := make([]domain.TargetRecord, 9)
	for i := range works {
		works[i] = domain.TargetRecord{ID: "t" + string(rune('a'+i)), RetailerChain: "fathalla", Year: 2026, TargetUnits: 10}
	}
	var inFlight, peak atomic.Int32
	bd := func(ctx context.Context, tr domain.TargetRecord) (domain.TargetBreakdownResponse, bool) {
		n := inFlight.Add(1)
		for {
			p := peak.Load()
			if n <= p || peak.CompareAndSwap(p, n) {
				break
			}
		}
		time.Sleep(time.Duration(10*(len(works)-int(tr.ID[1]-'a'))) * time.Millisecond)
		inFlight.Add(-1)
		return domain.TargetBreakdownResponse{TargetID: tr.ID, Branches: []domain.TargetBreakdownBranch{{BranchKey: tr.ID}}}, true
	}
	out, err := c.derivedBreakdowns(context.Background(), dsiTenant, works, bd)
	if err != nil {
		t.Fatal(err)
	}
	for i, r := range out {
		if r.TargetID != works[i].ID || r.Branches[0].BranchKey != works[i].ID {
			t.Fatalf("result %d belongs to %s, want %s", i, r.TargetID, works[i].ID)
		}
	}
	if p := peak.Load(); p < 2 || p > derivedBreakdownParallelism {
		t.Fatalf("parallelism must be bounded by %d and > 1: peak %d", derivedBreakdownParallelism, p)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := c.derivedBreakdowns(ctx, dsiTenant, works, bd); err == nil {
		t.Fatal("a cancelled request must not materialize a fallback allocation")
	}
}

func TestDerivedSellInReadNeverRematchesSellInRows(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	if err := c.SetSellInRecords(context.Background(), dsiTenant, "si.xlsx", []domain.SellInRecord{
		dsiSellIn("r1", "", "صنف لاحق", 3, 10, 1500),
	}); err != nil {
		t.Fatal(err)
	}
	// A Product Master item the row would now match by name, added without re-enriching the loaded rows.
	c.mu.Lock()
	norm := normalizeTenantKey(dsiTenant)
	late := domain.ProductMasterItem{SerialNo: 9, ItemCode: "FGCL-0009", ItemCodePrefix: "FGCL", OfficialName: "صنف لاحق", Brand: dsiBrandB, UnitsPerCarton: 12, NetUnitInvoiceCost: 1}
	c.productMaster[norm].Items = append(c.productMaster[norm].Items, late)
	c.productMasterByName[norm][normalizeArabicNameForLookup(late.OfficialName)] = late
	c.mu.Unlock()

	it := derivedSummary(t, c).Items[0]
	if it.ActualUnits != 120 {
		t.Fatalf("the row still counts as an actual: %v", it.ActualUnits)
	}
	for _, b := range it.Brands {
		if b.Brand == dsiBrandB && b.ActualUnits > 0 {
			t.Fatalf("the read re-matched a Sell-In row to the Product Master: %+v", it.Brands)
		}
	}
}

func TestDerivedSellInSummaryIsCachedUntilTheSourceChanges(t *testing.T) {
	c := newDerivedFixture(t)
	dsiSellOutTarget(t, c, 2026, 0, 1000, 14000)
	s1 := derivedSummary(t, c)
	s2 := derivedSummary(t, c)
	if &s1.Items[0] != &s2.Items[0] {
		t.Fatal("a warm read is served from the cache")
	}
	if s1.Items[0].ActualUnits != 0 {
		t.Fatalf("no Sell-In yet: %v", s1.Items[0].ActualUnits)
	}

	if err := c.SetSellInRecords(context.Background(), dsiTenant, "si.xlsx", []domain.SellInRecord{
		dsiSellIn("r1", "FGCL-0001", "صنف 1", 3, 10, 1500),
	}); err != nil {
		t.Fatal(err)
	}
	s3 := derivedSummary(t, c)
	if &s3.Items[0] == &s1.Items[0] || s3.Items[0].ActualUnits != 120 {
		t.Fatalf("a new upload invalidates the cache: actual=%v", s3.Items[0].ActualUnits)
	}
	if s := derivedSummary(t, c, dsiBrandA); len(s.AppliedBrands) != 1 || &s.Items[0] == &s3.Items[0] {
		t.Fatal("the brand filter is part of the cache key")
	}
}

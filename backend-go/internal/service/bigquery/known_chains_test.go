package bigquery

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestEnrichmentChainKeyMatchesSellInAndSellOut(t *testing.T) {
	cases := []struct {
		customer, chain string
		sellIn          bool
		want            string
	}{
		{"عميل", "Fathalla ", true, "fathalla"},
		{"عميل", " FATHALLA", false, "fathalla"},
		{"عميل", "", true, "fathalla"},
		{"عميل", "", false, "fathalla"},
		{"عميل", "   ", true, "fathalla"},
		{"بيت الجملة - فرع", "fathalla", true, "beet-elgomla"},
		{"بيت الجملة - فرع", "Gomla", true, "gomla"},
		{"عميل", "all", true, ""},
		{"عميل", "HyperOne", false, "hyperone"},
	}
	for _, tc := range cases {
		if got := enrichmentChainKey(tc.customer, tc.chain, tc.sellIn); got != tc.want {
			t.Errorf("enrichmentChainKey(%q, %q, sellIn=%v)=%q want %q", tc.customer, tc.chain, tc.sellIn, got, tc.want)
		}
	}
}

func TestKnownChainKeyMatchesFathallaEnrichment(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	c := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()
	const tenant = "tenant-chainkeys"

	if err := c.SetSellInRecords(ctx, tenant, "in.xlsx", []domain.SellInRecord{
		{CustomerName: "عميل عادي", RetailerChain: "Fathalla ", Year: 2026, MonthNum: 1, NetQtyCases: 1, NetValueEGP: 10},
		{CustomerName: "بيت الجملة - فرع", RetailerChain: "fathalla", Year: 2026, MonthNum: 2, NetQtyCases: 1, NetValueEGP: 20},
		{CustomerName: "بدون سلسلة", RetailerChain: "", Year: 2026, MonthNum: 3, NetQtyCases: 1, NetValueEGP: 5},
		{CustomerName: "جملة محفوظة", RetailerChain: "Gomla", Year: 2026, MonthNum: 4, NetQtyCases: 1, NetValueEGP: 7},
	}); err != nil {
		t.Fatal(err)
	}
	c.mu.Lock()
	c.records = append(c.records,
		domain.SellOutFact{RecordID: "so-fat", TenantID: tenant, RetailerChain: "FATHALLA", TransactionDate: "2026-04-15", IsOwnBrand: true},
		domain.SellOutFact{RecordID: "so-empty", TenantID: tenant, RetailerChain: "", TransactionDate: "2026-05-01"},
		domain.SellOutFact{RecordID: "so-new", TenantID: tenant, RetailerChain: "HyperOne", TransactionDate: "2026-06-02", IsOwnBrand: true},
		domain.SellOutFact{RecordID: "so-comp", TenantID: tenant, RetailerChain: "only-competitor", TransactionDate: "2026-06-03", Supplier: "Other Brand", IsOwnBrand: false},
	)
	c.bumpSourceVersion()
	c.mu.Unlock()

	chains, err := c.KnownChainsWithData(ctx, tenant)
	if err != nil {
		t.Fatal(err)
	}
	by := map[string]domain.KnownChain{}
	for _, ch := range chains {
		if ch.Key != ch.Name {
			t.Fatalf("name must equal the match key: %+v", ch)
		}
		by[ch.Key] = ch
	}
	fat, ok := by["fathalla"]
	if !ok {
		t.Fatalf("missing fathalla: %+v", chains)
	}
	if fat.DisplayName != "أسواق فتح الله (Fathalla Market)" {
		t.Fatalf("display: %q", fat.DisplayName)
	}
	if fat.SellInRows != 2 || fat.SellOutRows != 2 || fat.RowCount != 4 {
		t.Fatalf("fathalla counts: %+v", fat)
	}
	if fat.LastDataDate != "2026-05-01" {
		t.Fatalf("fathalla last date: %s", fat.LastDataDate)
	}
	if by["beet-elgomla"].SellInRows != 1 || by["beet-elgomla"].DisplayName != "بيت الجملة (Beet El Gomla)" {
		t.Fatalf("beet: %+v", by["beet-elgomla"])
	}
	if by["gomla"].SellInRows != 1 || by["gomla"].Key != "gomla" {
		t.Fatalf("gomla must stay gomla (rules only remap fathalla/empty): %+v", by["gomla"])
	}
	if by["hyperone"].SellOutRows != 1 || by["hyperone"].DisplayName != "hyperone" {
		t.Fatalf("new upload chain must appear with no code change: %+v", by["hyperone"])
	}
	if _, ok := by["only-competitor"]; ok {
		t.Fatal("competitor-only chain must not be listed")
	}
	for _, raw := range []string{"FATHALLA", "Fathalla ", "HyperOne", "only-competitor", "أسواق فتح الله (Fathalla Market)"} {
		if _, ok := by[raw]; ok {
			t.Fatalf("unnormalized or display key %q leaked into the list", raw)
		}
	}

	// The Arabic display name is not the enrichment key.
	c.SetChainDiscountProfiles(tenant, []domain.ChainDiscountProfile{{
		Chain: "أسواق فتح الله (Fathalla Market)", InvoiceDiscountPct: 33,
	}})
	norm := normalizeTenantKey(tenant)
	if _, ok := c.chainDiscountProfile(norm, "fathalla"); ok {
		t.Fatal("display name must not match fathalla")
	}
	vat := 5.0
	c.SetChainDiscountProfiles(tenant, []domain.ChainDiscountProfile{{
		Chain: "fathalla", InvoiceDiscountPct: 12, AdditionalDiscountPct: 3, VATRatePct: &vat,
	}})
	for _, variant := range []string{"fathalla", "Fathalla", " FATHALLA "} {
		p, ok := c.chainDiscountProfile(norm, variant)
		if !ok || p.InvoiceDiscountPct != 12 {
			t.Fatalf("variant %q did not match the saved fathalla profile: %+v ok=%v", variant, p, ok)
		}
	}
	if _, ok := c.chainDiscountProfile(norm, ""); ok {
		t.Fatal("an empty lookup is not fathalla; enrichment rewrites the row first")
	}

	blank := domain.SellInRecord{TenantID: tenant, RetailerChain: "", CustomerName: "x", NetQtyCases: 1, NetValueEGP: 10, Year: 2026, MonthNum: 1}
	mixed := domain.SellInRecord{TenantID: tenant, RetailerChain: "Fathalla ", CustomerName: "عميل عادي", NetQtyCases: 1, NetValueEGP: 10, Year: 2026, MonthNum: 1}
	other := domain.SellInRecord{TenantID: tenant, RetailerChain: "fathalla", CustomerName: "بيت الجملة - فرع", NetQtyCases: 1, NetValueEGP: 10, Year: 2026, MonthNum: 1}
	c.mu.Lock()
	c.enrichSellInRecordLocked(&blank)
	c.enrichSellInRecordLocked(&mixed)
	c.enrichSellInRecordLocked(&other)
	c.mu.Unlock()
	if blank.InvoiceDiscountPct != 12 || blank.ExtraDiscountPct != 3 || blank.VATRate != 0.05 {
		t.Fatalf("empty chain must take the fathalla profile: %+v", blank)
	}
	if mixed.InvoiceDiscountPct != 12 {
		t.Fatalf("Fathalla  must take the fathalla profile: %+v", mixed.InvoiceDiscountPct)
	}
	if other.InvoiceDiscountPct == 12 {
		t.Fatal("بيت الجملة is beet-elgomla and must not take the fathalla profile")
	}
}

func TestKnownChainsCacheDoesNotWaitOnAnalyticsWriteLock(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	c := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()
	first, err := c.KnownChainsWithData(ctx, "tenant-adeco")
	if err != nil || len(first) == 0 {
		t.Fatalf("seed chains: %v %+v", err, first)
	}

	release := make(chan struct{})
	started := make(chan struct{})
	go func() {
		c.mu.Lock()
		c.bumpSourceVersion()
		c.records = nil
		close(started)
		<-release
		c.mu.Unlock()
	}()
	<-started

	start := time.Now()
	second, err := c.KnownChainsWithData(ctx, "tenant-adeco")
	elapsed := time.Since(start)
	close(release)
	if err != nil {
		t.Fatal(err)
	}
	if elapsed > 200*time.Millisecond {
		t.Fatalf("stale cache waited on the analytics write lock for %s", elapsed)
	}
	if len(second) != len(first) || second[0].Key != first[0].Key {
		t.Fatalf("stale snapshot changed: %+v vs %+v", second, first)
	}
}

func TestKnownChainsMissTimesOutInsteadOfBlocking(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	c := NewClient("test-project", "test-dataset", true)
	release := make(chan struct{})
	started := make(chan struct{})
	go func() {
		c.mu.Lock()
		close(started)
		<-release
		c.mu.Unlock()
	}()
	<-started

	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	start := time.Now()
	_, err := c.KnownChainsWithData(ctx, "tenant-adeco")
	elapsed := time.Since(start)
	close(release)
	if elapsed > time.Second {
		t.Fatalf("blocked on the analytics write lock for %s", elapsed)
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("want deadline, got %v", err)
	}
}

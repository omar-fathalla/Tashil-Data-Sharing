package customers

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func rec(name string, v float64) domain.SellInRecord {
	return domain.SellInRecord{CustomerName: name, RetailerChain: "fathalla", Year: 2026, MonthNum: 3, NetValueEGP: v, NetQtyCases: 1}
}

func TestSeedNamesAttachExactlyAndUnknownIsQuarantined(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	if r.SeedCount() < 150 {
		t.Fatalf("seed must hold all current names, got %d", r.SeedCount())
	}
	recs := []domain.SellInRecord{rec("عائله فتح الله ماركت - طنطا", 100), rec("QA عميل تجريبي", 40), rec("QA عميل تجريبي", 2), rec("", 5)}
	kept, q := r.Partition(ctx, "tenant-adeco", "f.xlsx", "fathalla", recs, true)
	if len(kept) != 2 || len(q) != 1 || q[0].Name != "QA عميل تجريبي" || q[0].Rows != 2 || q[0].Value != 42 || q[0].Units != 2 || len(q[0].Months) != 1 || q[0].Months[0] != "2026-03" {
		t.Fatalf("kept=%d q=%+v", len(kept), q)
	}
	p := r.List(ctx, "tenant-adeco", StatusPending, false)
	if len(p) != 1 || p[0].FirstSeenFile != "f.xlsx" || len(p[0].Quarantine) != 1 {
		t.Fatalf("pending entry must be persisted: %+v", p)
	}
	// Seed also applies to the bare slug form of the tenant id.
	if kept, q := r.Partition(ctx, "adeco", "g.xlsx", "fathalla", recs[:1], true); len(kept) != 1 || len(q) != 0 {
		t.Fatal("seed must apply to adeco / tenant-adeco alike")
	}
	// Other tenants never inherit Adeco's seed.
	if kept, _ := r.Partition(ctx, "tenant-other", "f.xlsx", "x", recs[:1], true); len(kept) != 0 {
		t.Fatal("seed must not apply to another tenant")
	}
}

// TOP RULE: near-identical فتح الله names in different cities never merge.
func TestNearIdenticalCityNamesNeverMerge(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	near := []string{
		"عائله فتح الله ماركت - طنطا 2",         // new branch, 1 char away
		"عائلة فتح الله ماركت - المنصورة",       // other city
		"فتح الله جملة - الاسماعيلية",           // sibling of the Hurghada name
		"عائله فتح الله ماركت - دمنهور الجديدة", // extension of an approved branch
	}
	var recs []domain.SellInRecord
	for _, n := range near {
		recs = append(recs, rec(n, 10))
	}
	kept, q := r.Partition(ctx, "tenant-adeco", "near.xlsx", "fathalla", recs, true)
	if len(kept) != 0 || len(q) != len(near) {
		t.Fatalf("every near name must be quarantined separately: kept=%d q=%d", len(kept), len(q))
	}
	for _, c := range q {
		if c.Status != StatusPending || c.SuggestedName == c.Name {
			t.Fatalf("bad quarantine %+v", c)
		}
	}
	// Normalization alone (ة/ه, spacing, tatweel) is an exact match, not a guess.
	if kept, q := r.Partition(ctx, "tenant-adeco", "n.xlsx", "fathalla", []domain.SellInRecord{rec("عائلة  فتح الله ماركـت -  طنطا", 1)}, true); len(kept) != 1 || len(q) != 0 {
		t.Fatal("spelling-normalized exact name must attach")
	}
	// Hurghada name stays attached to fathalla (pending Mohamed's decision).
	if kept, _ := r.Partition(ctx, "tenant-adeco", "h.xlsx", "fathalla", []domain.SellInRecord{rec("فتح الله جملة - الغردقة", 1)}, true); len(kept) != 1 || kept[0].RetailerChain != "fathalla" {
		t.Fatal("Hurghada name must stay on fathalla")
	}
}

func TestSuggestionIsNeverApplied(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	_, q := r.Partition(ctx, "tenant-adeco", "s.xlsx", "fathalla", []domain.SellInRecord{rec("عائله فتح الله ماركت - طنطا 2", 1)}, true)
	if len(q) != 1 || q[0].SuggestedName == "" {
		t.Fatalf("a suggestion is expected for a near name: %+v", q)
	}
	// Re-upload: still quarantined although a suggestion exists.
	kept, q2 := r.Partition(ctx, "tenant-adeco", "s.xlsx", "fathalla", []domain.SellInRecord{rec("عائله فتح الله ماركت - طنطا 2", 1)}, true)
	if len(kept) != 0 || len(q2) != 1 {
		t.Fatal("suggestion must not attach rows")
	}
	if e := r.List(ctx, "tenant-adeco", StatusPending, false); len(e) != 1 || len(e[0].Quarantine) != 1 {
		t.Fatalf("re-upload of the same file replaces its stats: %+v", e)
	}
}

func TestApproveRejectUnmerge(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	name := "QA عميل تجريبي"
	r.Partition(ctx, "tenant-adeco", "qa.xlsx", "fathalla", []domain.SellInRecord{rec(name, 5)}, true)
	if _, err := r.Decide(ctx, "tenant-adeco", name, StatusApproved, "qa-test", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	kept, q := r.Partition(ctx, "tenant-adeco", "qa.xlsx", "fathalla", []domain.SellInRecord{rec(name, 5)}, true)
	if len(kept) != 1 || len(q) != 0 || kept[0].RetailerChain != "qa-test" {
		t.Fatalf("approved name with chain must attach to that chain: %+v %+v", kept, q)
	}
	if _, err := r.Decide(ctx, "tenant-adeco", name, StatusPending, "", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if kept, _ := r.Partition(ctx, "tenant-adeco", "qa.xlsx", "fathalla", []domain.SellInRecord{rec(name, 5)}, true); len(kept) != 0 {
		t.Fatal("unmerged name must be quarantined again")
	}
	if _, err := r.Decide(ctx, "tenant-adeco", name, StatusRejected, "", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if kept, q := r.Partition(ctx, "tenant-adeco", "qa.xlsx", "fathalla", []domain.SellInRecord{rec(name, 5)}, true); len(kept) != 0 || q[0].Status != StatusRejected {
		t.Fatal("rejected name stays out of totals")
	}
	// Alias: approved spelling of an existing customer is logged on the entry and reversible.
	e, err := r.Decide(ctx, "tenant-adeco", "عائله فتح الله ماركت-طنطا الجديدة", StatusApproved, "", "عائله فتح الله ماركت - طنطا", "admin@x")
	if err != nil || e.AliasOf == "" || e.DecidedBy != "admin@x" {
		t.Fatalf("alias decision must be recorded: %+v %v", e, err)
	}
}

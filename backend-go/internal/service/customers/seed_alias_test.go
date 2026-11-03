package customers

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func loadAliases(t *testing.T) map[string]string {
	t.Helper()
	var m map[string]string
	if err := json.Unmarshal(seedAliasesJSON, &m); err != nil {
		t.Fatal(err)
	}
	return m
}

// Item 7: all 84 new spellings resolve to their approved seed name, zero quarantine.
func TestSeedAliasesAllResolveApproved(t *testing.T) {
	ctx := context.Background()
	aliases := loadAliases(t)
	if len(aliases) != 84 {
		t.Fatalf("want 84 aliases, got %d", len(aliases))
	}
	r := New(&MemoryStore{})
	if r.AliasCount() != 84 {
		t.Fatalf("AliasCount=%d, want 84 (every target must be a seed name)", r.AliasCount())
	}
	var recs []domain.SellInRecord
	for newName, old := range aliases {
		if !strings.HasPrefix(old, "فرع فتح الله - ") || strings.TrimPrefix(old, "فرع فتح الله - ") != newName {
			t.Errorf("alias %q -> %q is not the branch-label rename", newName, old)
		}
		recs = append(recs, chainRec(newName, "fathalla"))
	}
	kept, q := r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", "fathalla", AliasLayout, recs, false)
	if len(q) != 0 || len(kept) != 84 {
		t.Fatalf("kept=%d quarantined=%d (%+v)", len(kept), len(q), q)
	}
	for _, k := range kept {
		if !strings.HasPrefix(k.CustomerName, "فرع فتح الله - ") {
			t.Errorf("row kept under new name %q, want stored seed name", k.CustomerName)
		}
	}
}

// A decision on the old (seed) name wins over the alias' implicit approval.
func TestSeedAliasDecisionOnOldNameWins(t *testing.T) {
	ctx := context.Background()
	var newName, old string
	for n, o := range loadAliases(t) {
		newName, old = n, o
		break
	}
	r := New(&MemoryStore{})
	if _, err := r.Decide(ctx, "tenant-adeco", old, StatusRejected, "", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	kept, q := r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{chainRec(newName, "fathalla")}, false)
	if len(kept) != 0 || len(q) != 1 || q[0].Status != StatusRejected {
		t.Fatalf("rejected old name must hold the aliased row: kept=%d q=%+v", len(kept), q)
	}
}

// Aliases are exact (normalized) matches only: a near spelling is not aliased, and other tenants are untouched.
func TestSeedAliasExactOnlyAndSeedTenantOnly(t *testing.T) {
	ctx := context.Background()
	var newName string
	for n := range loadAliases(t) {
		newName = n
		break
	}
	r := New(&MemoryStore{})
	if _, q := r.PartitionLayout(ctx, "tenant-adeco", "x.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{chainRec(newName+" 2", "fathalla")}, false); len(q) != 1 {
		t.Fatalf("near spelling must not be aliased: %+v", q)
	}
	kept, q := r.PartitionLayout(ctx, "tenant-other", "x.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{chainRec(newName, "fathalla")}, false)
	if len(q) != 1 || (len(kept) > 0 && kept[0].CustomerName != newName) {
		t.Fatalf("alias must apply only to seed tenants: kept=%+v q=%+v", kept, q)
	}
}

// B1: a Zahran or Gomla upload with «زهران - البيطاش» is never aliased to the Fathalla customer; it
// goes to quarantine. Neither is a fathalla upload from another layout, nor a call without a layout.
func TestSeedAliasOnlyForFathallaGPSOP(t *testing.T) {
	ctx := context.Background()
	const name = "زهران - البيطاش"
	if _, ok := loadAliases(t)[name]; !ok {
		t.Fatalf("%q must be one of the 84 aliases", name)
	}
	cases := []struct{ chain, layout string }{
		{"zahran", AliasLayout}, {"gomla", AliasLayout}, {"zahran", "raw_plan"}, {"gomla", "clean_30_col"},
		{"fathalla", "raw_plan"}, {"fathalla", "guided_template"}, {"fathalla", ""},
	}
	for _, c := range cases {
		r := New(&MemoryStore{})
		kept, q := r.PartitionLayout(ctx, "tenant-adeco", "z.xlsx", c.chain, c.layout, []domain.SellInRecord{chainRec(name, c.chain)}, false)
		if len(kept) != 0 || len(q) != 1 || q[0].Name != name {
			t.Errorf("chain=%s layout=%q: want quarantined under its own name, kept=%+v q=%+v", c.chain, c.layout, kept, q)
		}
	}
	// Plain Partition (no layout) never aliases either.
	r := New(&MemoryStore{})
	if kept, q := r.Partition(ctx, "tenant-adeco", "f.xlsx", "fathalla", []domain.SellInRecord{chainRec(name, "fathalla")}, false); len(kept) != 0 || len(q) != 1 {
		t.Errorf("Partition without layout aliased: kept=%+v q=%+v", kept, q)
	}
}

// S1: the parser normalizes the upload chain ("", "all", «فتح الله», "Fathalla Market") to fathalla on
// every row; the alias gate uses that row chain, so all 84 still resolve approved with zero quarantine.
func TestSeedAliasUsesNormalizedRowChain(t *testing.T) {
	ctx := context.Background()
	aliases := loadAliases(t)
	for _, upload := range []string{"", "all", "فتح الله", "Fathalla Market", "FATHALLA"} {
		var recs []domain.SellInRecord
		for n := range aliases {
			recs = append(recs, chainRec(n, "fathalla"))
		}
		r := New(&MemoryStore{})
		kept, q := r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", upload, AliasLayout, recs, false)
		if len(q) != 0 || len(kept) != 84 {
			t.Errorf("upload chain %q: kept=%d quarantined=%d", upload, len(kept), len(q))
		}
	}
}

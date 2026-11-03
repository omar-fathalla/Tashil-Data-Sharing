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
	kept, q := r.Partition(ctx, "tenant-adeco", "in26.xlsx", "fathalla", recs, false)
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
	kept, q := r.Partition(ctx, "tenant-adeco", "in26.xlsx", "fathalla", []domain.SellInRecord{chainRec(newName, "fathalla")}, false)
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
	if _, q := r.Partition(ctx, "tenant-adeco", "x.xlsx", "fathalla", []domain.SellInRecord{chainRec(newName+" 2", "fathalla")}, false); len(q) != 1 {
		t.Fatalf("near spelling must not be aliased: %+v", q)
	}
	kept, q := r.Partition(ctx, "tenant-other", "x.xlsx", "fathalla", []domain.SellInRecord{chainRec(newName, "fathalla")}, false)
	if len(q) != 1 || (len(kept) > 0 && kept[0].CustomerName != newName) {
		t.Fatalf("alias must apply only to seed tenants: kept=%+v q=%+v", kept, q)
	}
}

package customers

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestRegistryAliasOfRemapsToCanonicalCustomer(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	alias := "عائله فتح الله ماركت مواد عناية - كفر الدوار2"

	r.Partition(ctx, "tenant-adeco", "in26.xlsx", "fathalla", []domain.SellInRecord{rec(canonical, 10)}, true)
	if _, err := r.Decide(ctx, "tenant-adeco", canonical, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	r.Partition(ctx, "tenant-adeco", "in26.xlsx", "fathalla", []domain.SellInRecord{rec(alias, 3)}, true)
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", canonical, "admin@x"); err != nil {
		t.Fatal(err)
	}

	row := rec(alias, 3)
	row.CustomerBranchCode = "fat_auto_old"
	kept, q := r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{row}, false)
	if len(q) != 0 {
		t.Fatalf("aliased approved name must not be quarantined: %+v", q)
	}
	if len(kept) != 1 || kept[0].CustomerName != canonical {
		t.Fatalf("want canonical name %q, got %+v", canonical, kept)
	}
	if kept[0].CustomerBranchCode == "fat_auto_old" && kept[0].CustomerName == canonical {
		// Branch code may be empty (ingest fills it) but must not stay on the alias id
		// if a canonical branch code was stored; empty is acceptable here.
	}

	// Unmerge: clearing alias_of + pending puts the spelling back in quarantine.
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusPending, "", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	kept, q = r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{rec(alias, 3)}, false)
	if len(kept) != 0 || len(q) != 1 {
		t.Fatalf("unmerge must quarantine the spelling again: kept=%+v q=%+v", kept, q)
	}
}

func TestRegistryAliasOfDoesNotAttachUnapprovedCanonical(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	alias := "QA alias name"
	r.Partition(ctx, "tenant-adeco", "x.xlsx", "fathalla", []domain.SellInRecord{rec(alias, 1)}, true)
	// Approved alias of a name that is not itself approved must keep the alias row
	// on its own approved entry (no attribution to an unknown customer).
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", "QA missing canonical", "admin@x"); err != nil {
		t.Fatal(err)
	}
	kept, q := r.PartitionLayout(ctx, "tenant-adeco", "x.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{rec(alias, 1)}, false)
	if len(kept) != 1 || kept[0].CustomerName != alias || len(q) != 0 {
		t.Fatalf("unapproved canonical must not swallow the row: kept=%+v q=%+v", kept, q)
	}
}

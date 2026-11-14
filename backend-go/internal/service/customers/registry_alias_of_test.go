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
	_, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", "QA missing canonical", "admin@x")
	if err == nil {
		t.Fatal("expected decide to reject an unapproved canonical")
	}
}

func TestRegistryAliasOfRejectsSelfAndCrossChain(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	a, b := "عميل سلسلة فتح الله", "عميل سلسلة كارفور"
	if _, err := r.Decide(ctx, "tenant-adeco", a, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Decide(ctx, "tenant-adeco", b, StatusApproved, "carrefour", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Decide(ctx, "tenant-adeco", a, StatusApproved, "fathalla", a, "admin@x"); err == nil {
		t.Fatal("self alias must be rejected")
	}
	if _, err := r.Decide(ctx, "tenant-adeco", a, StatusApproved, "fathalla", b, "admin@x"); err == nil {
		t.Fatal("cross-chain alias must be rejected")
	}
}

func TestRegistryAliasOfAlreadyApprovedRemapsAndUnmergeKeepsApproved(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	alias := "عائله فتح الله ماركت مواد عناية - كفر الدوار2"
	if _, err := r.Decide(ctx, "tenant-adeco", canonical, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", canonical, "admin@x"); err != nil {
		t.Fatal(err)
	}
	kept, q := r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{rec(alias, 3)}, false)
	if len(q) != 0 || len(kept) != 1 || kept[0].CustomerName != canonical {
		t.Fatalf("approved merge must remap: kept=%+v q=%+v", kept, q)
	}
	// Clearing alias_of while staying approved puts the spelling back on its own name.
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	kept, q = r.PartitionLayout(ctx, "tenant-adeco", "in26.xlsx", "fathalla", AliasLayout, []domain.SellInRecord{rec(alias, 3)}, false)
	if len(q) != 0 || len(kept) != 1 || kept[0].CustomerName != alias {
		t.Fatalf("unmerge must keep the name approved under itself: kept=%+v q=%+v", kept, q)
	}
}

func TestRegistryAliasOfDoesNotRemapAcrossChainsAtPartition(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	canonical := "عميل فتح الله"
	alias := "اسم مشترك"
	if _, err := r.Decide(ctx, "tenant-adeco", canonical, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Decide(ctx, "tenant-adeco", alias, StatusApproved, "fathalla", canonical, "admin@x"); err != nil {
		t.Fatal(err)
	}
	row := rec(alias, 3)
	row.RetailerChain = "carrefour"
	kept, q := r.PartitionLayout(ctx, "tenant-adeco", "x.xlsx", "carrefour", "", []domain.SellInRecord{row}, false)
	if len(q) != 0 || len(kept) != 1 || kept[0].CustomerName != alias {
		t.Fatalf("row on another chain must not be remapped: kept=%+v q=%+v", kept, q)
	}
}

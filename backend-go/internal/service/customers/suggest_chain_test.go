package customers

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func chainRec(name, chain string) domain.SellInRecord {
	return domain.SellInRecord{CustomerName: name, RetailerChain: chain, Year: 2026, MonthNum: 3, NetValueEGP: 1, NetQtyCases: 1}
}

// Rule 1: a suggestion never proposes another chain's customer.
func TestSuggestNeverCrossesChains(t *testing.T) {
	ctx := context.Background()
	r := New(&MemoryStore{})
	fathTanta := "QA فتح الله جملة (طنطا)"
	zahTanta := "QA زهران (طنطا)"
	r.Partition(ctx, "tenant-adeco", "f.xlsx", "fathalla", []domain.SellInRecord{chainRec(fathTanta, "fathalla")}, true)
	if _, err := r.Decide(ctx, "tenant-adeco", fathTanta, StatusApproved, "fathalla", "", "admin@x"); err != nil {
		t.Fatal(err)
	}
	r.Partition(ctx, "tenant-adeco", "z.xlsx", "zahran", []domain.SellInRecord{chainRec(zahTanta, "zahran")}, true)
	if _, err := r.Decide(ctx, "tenant-adeco", zahTanta, StatusApproved, "zahran", "", "admin@x"); err != nil {
		t.Fatal(err)
	}

	// A near-copy of the Fathalla name uploaded under Zahran: never suggest the Fathalla customer.
	_, q := r.Partition(ctx, "tenant-adeco", "z2.xlsx", "zahran", []domain.SellInRecord{chainRec("QA فتح الله جملة (طنطا) 2", "zahran")}, true)
	if len(q) != 1 {
		t.Fatalf("expected quarantine: %+v", q)
	}
	if q[0].SuggestedName == fathTanta || (q[0].SuggestedChain != "" && q[0].SuggestedChain != "zahran") {
		t.Fatalf("Zahran upload got a Fathalla suggestion: %+v", q[0])
	}

	// And vice versa: a near-copy of the Zahran name under Fathalla never gets the Zahran customer.
	_, q = r.Partition(ctx, "tenant-adeco", "f2.xlsx", "fathalla", []domain.SellInRecord{chainRec("QA زهران (طنطا) 2", "fathalla")}, true)
	if len(q) != 1 {
		t.Fatalf("expected quarantine: %+v", q)
	}
	if q[0].SuggestedName == zahTanta || (q[0].SuggestedChain != "" && q[0].SuggestedChain != "fathalla") {
		t.Fatalf("Fathalla upload got a Zahran suggestion: %+v", q[0])
	}

	// Same chain still gets its suggestion.
	_, q = r.Partition(ctx, "tenant-adeco", "f3.xlsx", "fathalla", []domain.SellInRecord{chainRec("QA فتح الله جملة (طنطا) 2", "fathalla")}, true)
	if len(q) != 1 || q[0].SuggestedName != fathTanta {
		t.Fatalf("same-chain suggestion expected: %+v", q)
	}
}

func TestSuggestEmptyChainOrUnknownEntryChainGivesNothing(t *testing.T) {
	approved := []Entry{{Name: "QA فتح الله جملة (طنطا)", Key: NormalizeName("QA فتح الله جملة (طنطا)"), Status: StatusApproved}}
	if s := Suggest("QA فتح الله جملة (طنطا) 2", "fathalla", approved); s.Name != "" {
		t.Fatalf("entry with unknown chain must not be suggested: %+v", s)
	}
	approved[0].Chain = "fathalla"
	if s := Suggest("QA فتح الله جملة (طنطا) 2", "", approved); s.Name != "" {
		t.Fatalf("empty upload chain must not get a suggestion: %+v", s)
	}
	if s := Suggest("QA فتح الله جملة (طنطا) 2", "fathalla", approved); s.Name == "" {
		t.Fatal("same chain must be suggested")
	}
}

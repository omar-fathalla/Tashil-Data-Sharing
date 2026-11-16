package bigquery

import (
	"context"
	"fmt"
	"math"
	"reflect"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func matchedFact(tenant, chain, store, id, date string, rev float64) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID: id, TenantID: tenant, RetailerChain: chain, StoreID: store,
		StoreName: store, Barcode: "6220000000001", SKUName: "Item 1",
		QuantitySold: 1, NetRevenue: rev, TransactionDate: date, IsOwnBrand: true,
	}
}

// Last year only has Jan–Apr uploaded while this year runs Jan–Oct: the full
// 2026 total is NOT comparable with 2025, but the matched-month windows are.
func TestMatchedYoYMonthsAndLikeForLikeWindow(t *testing.T) {
	ctx := context.Background()
	c := NewClient("p", "d", true)
	tn := "tenant-matched-months"

	var facts []domain.SellOutFact
	for m := 1; m <= 4; m++ {
		facts = append(facts, matchedFact(tn, "gomla", "s1", fmt.Sprintf("p%d", m), fmt.Sprintf("2025-%02d-10", m), 100))
	}
	for m := 1; m <= 10; m++ {
		facts = append(facts, matchedFact(tn, "gomla", "s1", fmt.Sprintf("c%d", m), fmt.Sprintf("2026-%02d-10", m), 300))
	}
	// Another chain with the 2025 months May–Jun only: must not widen gomla's window.
	facts = append(facts,
		matchedFact(tn, "other", "o1", "o25", "2025-05-10", 50),
		matchedFact(tn, "other", "o1", "o26", "2026-05-10", 50),
	)
	if err := c.ReplaceTenantFacts(ctx, tn, facts); err != nil {
		t.Fatal(err)
	}

	got, err := c.MatchedYoYMonths(ctx, tn, "gomla", 2026, 2025)
	if err != nil {
		t.Fatal(err)
	}
	if want := []int{1, 2, 3, 4}; !reflect.DeepEqual(got, want) {
		t.Fatalf("gomla matched months: want %v got %v", want, got)
	}

	all, err := c.MatchedYoYMonths(ctx, tn, "", 2026, 2025)
	if err != nil {
		t.Fatal(err)
	}
	if want := []int{1, 2, 3, 4, 5}; !reflect.DeepEqual(all, want) {
		t.Fatalf("all-chain matched months: want %v got %v", want, all)
	}

	none, err := c.MatchedYoYMonths(ctx, tn, "gomla", 2026, 2024)
	if err != nil {
		t.Fatal(err)
	}
	if len(none) != 0 {
		t.Fatalf("no 2024 data: want no matched months, got %v", none)
	}

	rev := func(f StoreMatrixFilter) float64 {
		items, err := c.GetStoreBenchmarkMatrix(ctx, tn, f)
		if err != nil {
			t.Fatal(err)
		}
		var total float64
		for _, it := range items {
			total += it.TotalRevenue
		}
		return total
	}
	full26 := rev(StoreMatrixFilter{Year: 2026, RetailerChain: "gomla"})
	prev := rev(StoreMatrixFilter{Year: 2025, RetailerChain: "gomla", SameMonthsAsYear: 2026})
	cur := rev(StoreMatrixFilter{Year: 2026, RetailerChain: "gomla", SameMonthsAsYear: 2025})
	if math.Abs(full26-3000) > 0.01 {
		t.Fatalf("full 2026 should cover Jan–Oct: got %v", full26)
	}
	// Both sides cover exactly the months returned by MatchedYoYMonths.
	if math.Abs(prev-400) > 0.01 || math.Abs(cur-1200) > 0.01 {
		t.Fatalf("matched window: want 2025=400 and 2026=1200 (Jan–Apr), got %v and %v", prev, cur)
	}
}

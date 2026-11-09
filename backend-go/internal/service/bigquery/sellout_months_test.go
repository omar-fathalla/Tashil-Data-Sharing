package bigquery

import (
	"context"
	"fmt"
	"strconv"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestMonthsFromSellOutFactsIncludesAllUploadedMonths(t *testing.T) {
	var facts []domain.SellOutFact
	for m := 1; m <= 10; m++ {
		facts = append(facts, domain.SellOutFact{
			TenantID:        "tenant-adeco",
			TransactionDate: fmt.Sprintf("2026-%02d-15", m),
			NetRevenue:      float64(m) * 100,
		})
	}
	// Noise: other tenant + other year must not leak in.
	facts = append(facts,
		domain.SellOutFact{TenantID: "tenant-other", TransactionDate: "2026-11-01"},
		domain.SellOutFact{TenantID: "tenant-adeco", TransactionDate: "2025-12-01"},
	)

	got := monthsFromSellOutFacts(facts, "tenant-adeco", 2026)
	if len(got) != 10 {
		t.Fatalf("want 10 months (Jan–Oct), got %v", got)
	}
	for i, want := range []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10} {
		if got[i] != want {
			t.Fatalf("month[%d]=%d want %d (full list %v)", i, got[i], want, got)
		}
	}
}

func TestSellOutMonthsMonthZeroRangeIncludesAllMonths(t *testing.T) {
	c := NewClient("test-proj", "test-dataset", true)
	tenant := "tenant-months-all"
	var facts []domain.SellOutFact
	var wantRev float64
	for m := 1; m <= 10; m++ {
		rev := float64(m) * 50
		wantRev += rev
		facts = append(facts, domain.SellOutFact{
			RecordID:        fmt.Sprintf("m-%d", m),
			TenantID:        tenant,
			RetailerChain:   "fathalla",
			StoreID:         "s1",
			StoreName:       "فرع",
			Barcode:         "6223000239438",
			SKUName:         "فيبا 3 كجم",
			QuantitySold:    m,
			NetRevenue:      rev,
			UnitPrice:       50,
			TransactionDate: fmt.Sprintf("2026-%02d-10", m),
		})
	}
	if err := c.ReplaceTenantFacts(context.Background(), tenant, facts); err != nil {
		t.Fatal(err)
	}

	months := c.SellOutMonths(tenant, 2026)
	if len(months) != 10 {
		t.Fatalf("SellOutMonths: %v", months)
	}

	// month=0 → full-year window must include every uploaded month's revenue.
	recs, total, err := c.GetSellOutRecords(context.Background(), tenant, RecordFilter{
		StartDate: "2026-01-01",
		EndDate:   "2026-12-31",
		Limit:     500,
	})
	if err != nil {
		t.Fatal(err)
	}
	if total != 10 || len(recs) != 10 {
		t.Fatalf("month=0 range returned %d/%d rows, want 10", len(recs), total)
	}
	var sum float64
	seen := map[int]bool{}
	for _, r := range recs {
		sum += r.NetRevenue
		if len(r.TransactionDate) >= 7 {
			mo, _ := strconv.Atoi(r.TransactionDate[5:7])
			seen[mo] = true
		}
	}
	if sum != wantRev {
		t.Fatalf("month=0 revenue sum %.0f want %.0f", sum, wantRev)
	}
	for m := 1; m <= 10; m++ {
		if !seen[m] {
			t.Fatalf("month=0 missing month %d in results", m)
		}
	}
}

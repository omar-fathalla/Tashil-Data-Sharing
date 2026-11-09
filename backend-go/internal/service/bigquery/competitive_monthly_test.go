package bigquery

import (
	"fmt"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestAggregateCompetitiveMonthlyJanThroughOct(t *testing.T) {
	var facts []domain.SellOutFact
	for m := 1; m <= 10; m++ {
		facts = append(facts, domain.SellOutFact{
			TenantID:        "tenant-adeco",
			RetailerChain:   "fathalla",
			Barcode:         "6223000239438",
			QuantitySold:    10 * m,
			UnitPrice:       float64(100 + m),
			NetRevenue:      float64(10*m) * float64(100+m),
			TransactionDate: fmt.Sprintf("2026-%02d-15", m),
			Supplier:        "competitor-x",
			IsOwnBrand:      false,
		})
		// Other barcode in May–Oct only.
		if m >= 5 {
			facts = append(facts, domain.SellOutFact{
				TenantID:        "tenant-adeco",
				RetailerChain:   "fathalla",
				Barcode:         "6221143099674",
				QuantitySold:    5,
				UnitPrice:       50,
				NetRevenue:      250,
				TransactionDate: fmt.Sprintf("2026-%02d-10", m),
				IsOwnBrand:      true,
			})
		}
	}
	// Noise: other chain / other year / other tenant.
	facts = append(facts,
		domain.SellOutFact{TenantID: "tenant-adeco", RetailerChain: "gomla", Barcode: "6223000239438", QuantitySold: 1, UnitPrice: 9, TransactionDate: "2026-11-01"},
		domain.SellOutFact{TenantID: "tenant-adeco", RetailerChain: "fathalla", Barcode: "6223000239438", QuantitySold: 1, UnitPrice: 9, TransactionDate: "2025-12-01"},
		domain.SellOutFact{TenantID: "tenant-other", RetailerChain: "fathalla", Barcode: "6223000239438", QuantitySold: 1, UnitPrice: 9, TransactionDate: "2026-10-01"},
	)

	start, end := CompetitiveMonthlyYearWindow(2026)
	got := AggregateCompetitiveMonthly(facts, "tenant-adeco", RecordFilter{
		RetailerChain: "fathalla",
		Supplier:      "all_market",
		StartDate:     start,
		EndDate:       end,
	})

	if len(got.Months) != 10 {
		t.Fatalf("months=%v want Jan–Oct (10)", got.Months)
	}
	for i, want := range []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10} {
		if got.Months[i] != want {
			t.Fatalf("month[%d]=%d want %d", i, got.Months[i], want)
		}
	}
	if len(got.Items) != 2 {
		t.Fatalf("items=%d want 2", len(got.Items))
	}
	own := got.Items[0]
	if own.Barcode != "6221143099674" { // sort by barcode
		own = got.Items[1]
	}
	feba := got.Items[0]
	if feba.Barcode != "6223000239438" {
		feba = got.Items[1]
	}
	if len(feba.Months) != 10 {
		t.Fatalf("feba months=%d want 10", len(feba.Months))
	}
	if feba.Months[0].UnitPrice != 101 || feba.Months[0].Units != 10 {
		t.Fatalf("jan point=%+v", feba.Months[0])
	}
	if len(own.Months) != 6 {
		t.Fatalf("own months=%d want 6 (May–Oct)", len(own.Months))
	}
}

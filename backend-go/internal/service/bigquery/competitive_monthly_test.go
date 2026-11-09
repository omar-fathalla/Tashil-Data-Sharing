package bigquery

import (
	"fmt"
	"strings"
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

func TestAggregateCompetitiveMonthlyOwnSkusFromLiveMetadata(t *testing.T) {
	facts := []domain.SellOutFact{
		{
			TenantID: "tenant-adeco", RetailerChain: "fathalla",
			Barcode: "6223000232514", SKUName: "فيبا صابون سائل اطباق 1 كجم",
			Category: "صابون سائل اطباق", IsOwnBrand: true,
			QuantitySold: 5, UnitPrice: 40, NetRevenue: 200, TransactionDate: "2026-03-10",
		},
		{
			TenantID: "tenant-adeco", RetailerChain: "fathalla",
			Barcode: "6223000239438", SKUName: "عرض شرنك فيبا بلس + 3 كجم & فيبا 3 كجم - 3 مجموعه",
			Category: "منظف ارضيات", IsOwnBrand: true,
			QuantitySold: 8, UnitPrice: 150, NetRevenue: 1200, TransactionDate: "2026-03-12",
		},
		{
			TenantID: "tenant-adeco", RetailerChain: "fathalla",
			Barcode: "6221143099674", SKUName: "بريل", Category: "صابون سائل اطباق",
			IsOwnBrand: false, Supplier: "هنكل",
			QuantitySold: 3, UnitPrice: 140, NetRevenue: 420, TransactionDate: "2026-03-11",
		},
		// Extra own barcodes in dish soap — must all appear in own_skus.
		{
			TenantID: "tenant-adeco", RetailerChain: "fathalla",
			Barcode: "6223000999001", SKUName: "فيبا اطباق A", Category: "صابون سائل اطباق",
			IsOwnBrand: true, QuantitySold: 2, UnitPrice: 30, NetRevenue: 60, TransactionDate: "2026-03-01",
		},
		{
			TenantID: "tenant-adeco", RetailerChain: "fathalla",
			Barcode: "6223000999002", SKUName: "فيبا اطباق B", Category: "صابون سائل اطباق",
			IsOwnBrand: true, QuantitySold: 2, UnitPrice: 31, NetRevenue: 62, TransactionDate: "2026-03-02",
		},
	}
	start, end := CompetitiveMonthlyYearWindow(2026)
	got := AggregateCompetitiveMonthly(facts, "tenant-adeco", RecordFilter{
		RetailerChain: "fathalla", Supplier: "all_market", StartDate: start, EndDate: end,
	})
	if len(got.OwnSkus) != 4 {
		t.Fatalf("own_skus=%d want 4 (all own with sales); got %+v", len(got.OwnSkus), got.OwnSkus)
	}
	byBC := map[string]CompetitiveOwnSku{}
	for _, o := range got.OwnSkus {
		byBC[o.Barcode] = o
	}
	floor := byBC["6223000239438"]
	if floor.Category != "منظف ارضيات" {
		t.Fatalf("live category for 6223000239438 = %q want منظف ارضيات (seed must not apply server-side)", floor.Category)
	}
	if floor.SKUName == "" || !strings.Contains(floor.SKUName, "شرنك") {
		t.Fatalf("live name missing: %q", floor.SKUName)
	}
	dish := byBC["6223000232514"]
	if dish.Category != "صابون سائل اطباق" {
		t.Fatalf("dish category=%q", dish.Category)
	}
	for _, item := range got.Items {
		if item.Barcode == "6223000239438" && !item.IsOwnBrand {
			t.Fatal("own barcode missing is_own_brand on item")
		}
		if item.Barcode == "6221143099674" && item.IsOwnBrand {
			t.Fatal("competitor marked as own")
		}
	}
}

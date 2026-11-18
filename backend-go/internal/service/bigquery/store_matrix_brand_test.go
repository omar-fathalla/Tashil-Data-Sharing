package bigquery

import (
	"context"
	"math"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestGetStoreBenchmarkMatrix_BrandFilter(t *testing.T) {
	ctx := context.Background()
	c := NewClient("p", "d", true)
	tn := "tenant-brand-matrix"

	facts := []domain.SellOutFact{
		{
			RecordID: "d1", TenantID: tn, RetailerChain: "fathalla",
			StoreID: "s1", StoreName: "فرع أ", SKUName: "شامبو ديفا 400 مل",
			Category: "عناية بالشعر", IsOwnBrand: true,
			QuantitySold: 10, NetRevenue: 1000, TransactionDate: "2026-03-15",
		},
		{
			RecordID: "d2", TenantID: tn, RetailerChain: "fathalla",
			StoreID: "s2", StoreName: "فرع ب", SKUName: "ديفاتول مطهر 750 مل",
			Category: "مطهرات", IsOwnBrand: true,
			QuantitySold: 5, NetRevenue: 500, TransactionDate: "2026-03-15",
		},
		{
			RecordID: "v1", TenantID: tn, RetailerChain: "fathalla",
			StoreID: "s1", StoreName: "فرع أ", SKUName: "فلفيتا جيل للحرير 750 مل",
			Category: "مساحيق", IsOwnBrand: true,
			QuantitySold: 8, NetRevenue: 800, TransactionDate: "2026-03-15",
		},
		{
			RecordID: "c1", TenantID: tn, RetailerChain: "fathalla",
			StoreID: "s2", StoreName: "فرع ب", SKUName: "كلوريل أبيض 1050 جم",
			Category: "مطهرات", IsOwnBrand: true,
			QuantitySold: 20, NetRevenue: 2000, TransactionDate: "2026-03-15",
		},
		{
			RecordID: "u1", TenantID: tn, RetailerChain: "fathalla",
			StoreID: "s1", StoreName: "فرع أ", SKUName: "صنف عشوائي بلا علامة",
			Category: "أخرى", IsOwnBrand: true,
			QuantitySold: 3, NetRevenue: 300, TransactionDate: "2026-03-15",
		},
	}
	if err := c.ReplaceTenantFacts(ctx, tn, facts); err != nil {
		t.Fatal(err)
	}

	sum := func(brand string) (float64, int) {
		items, err := c.GetStoreBenchmarkMatrix(ctx, tn, StoreMatrixFilter{
			Year: 2026, Brand: brand,
		})
		if err != nil {
			t.Fatal(err)
		}
		var rev float64
		var units int
		for _, it := range items {
			rev += it.TotalRevenue
			units += it.TotalUnits
		}
		return rev, units
	}

	allRev, allUnits := sum("")
	if math.Abs(allRev-4600) > 0.01 || allUnits != 46 {
		t.Fatalf("all brands: want 4600/46 got %v/%d", allRev, allUnits)
	}

	divaRev, divaUnits := sum("Diva")
	if math.Abs(divaRev-1500) > 0.01 || divaUnits != 15 {
		t.Fatalf("Diva: want 1500/15 got %v/%d", divaRev, divaUnits)
	}
	divaAr, _ := sum("ديفا (Diva)")
	if math.Abs(divaAr-divaRev) > 0.01 {
		t.Fatalf("Arabic Diva label should match English filter: %v vs %v", divaAr, divaRev)
	}

	velRev, velUnits := sum("Velveta")
	if math.Abs(velRev-800) > 0.01 || velUnits != 8 {
		t.Fatalf("Velveta: want 800/8 got %v/%d", velRev, velUnits)
	}
	velAr, _ := sum("فلفيتا")
	if math.Abs(velAr-velRev) > 0.01 {
		t.Fatalf("فلفيتا should fold to فلڤيتا: %v vs %v", velAr, velRev)
	}

	clorelRev, _ := sum("Clorel")
	if math.Abs(clorelRev-2000) > 0.01 {
		t.Fatalf("Clorel: want 2000 got %v", clorelRev)
	}

	// Per-brand sums + unbranded remainder == unfiltered total.
	unbranded := allRev - divaRev - velRev - clorelRev
	if math.Abs(unbranded-300) > 0.01 {
		t.Fatalf("unbranded remainder: want 300 got %v", unbranded)
	}
	if math.Abs(divaRev+velRev+clorelRev+unbranded-allRev) > 0.01 {
		t.Fatalf("brand parts do not sum to all")
	}

	// Selecting Diva must change branch rows (s1+s2), not leave the all-brand matrix.
	divaItems, err := c.GetStoreBenchmarkMatrix(ctx, tn, StoreMatrixFilter{Year: 2026, Brand: "Diva"})
	if err != nil {
		t.Fatal(err)
	}
	allItems, err := c.GetStoreBenchmarkMatrix(ctx, tn, StoreMatrixFilter{Year: 2026})
	if err != nil {
		t.Fatal(err)
	}
	if len(divaItems) == 0 {
		t.Fatal("Diva filter returned no stores")
	}
	var divaS1, allS1 float64
	for _, it := range divaItems {
		if it.StoreID == "s1" {
			divaS1 = it.TotalRevenue
		}
	}
	for _, it := range allItems {
		if it.StoreID == "s1" {
			allS1 = it.TotalRevenue
		}
	}
	if !(divaS1 < allS1) {
		t.Fatalf("s1 Diva revenue %v should be less than all-brand %v", divaS1, allS1)
	}
}

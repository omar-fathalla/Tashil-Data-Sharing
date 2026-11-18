package bigquery

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestShareTargetBaselineReturnsAllCategories(t *testing.T) {
	c := NewClient("test", "ds", true)
	_ = c.ClearTenantData(context.Background(), "all")
	tenant := "tenant-many-cats"
	var facts []domain.SellOutFact
	const n = 20
	for i := 0; i < n; i++ {
		cat := fmt.Sprintf("فئة-%02d", i+1)
		facts = append(facts,
			domain.SellOutFact{
				RecordID: fmt.Sprintf("o-%d", i), TenantID: tenant, RetailerChain: "fathalla",
				StoreID: "s1", StoreName: "الرحاب", Category: cat, Barcode: fmt.Sprintf("b-%d", i),
				SKUName: "sku", QuantitySold: 10, NetRevenue: float64(100 + i),
				TransactionDate: "2026-03-01", IsOwnBrand: true,
			},
			domain.SellOutFact{
				RecordID: fmt.Sprintf("c-%d", i), TenantID: tenant, RetailerChain: "fathalla",
				StoreID: "s1", StoreName: "الرحاب", Category: cat, Barcode: fmt.Sprintf("x-%d", i),
				SKUName: "comp", QuantitySold: 10, NetRevenue: float64(200 + i),
				TransactionDate: "2026-03-01", IsOwnBrand: false, Supplier: "Comp",
			},
		)
	}
	// Market-only category (no Adeco) must still appear so step 2 can edit share from 0.
	facts = append(facts, domain.SellOutFact{
		RecordID: "m-only", TenantID: tenant, RetailerChain: "fathalla",
		StoreID: "s1", StoreName: "الرحاب", Category: "فئة-سوق-فقط", Barcode: "m1",
		SKUName: "comp-only", QuantitySold: 5, NetRevenue: 50,
		TransactionDate: "2026-04-01", IsOwnBrand: false, Supplier: "Comp",
	})
	if err := c.InsertSellOutFacts(context.Background(), facts); err != nil {
		t.Fatal(err)
	}
	base, err := c.GetShareTargetBaseline(context.Background(), tenant, "fathalla", 2026)
	if err != nil {
		t.Fatal(err)
	}
	if len(base.Categories) != n+1 {
		t.Fatalf("want %d categories (all editable), got %d: %+v", n+1, len(base.Categories), base.Categories)
	}
}

func TestBuildShareTargetCascadesBatchMatchesPerCategory(t *testing.T) {
	c := NewClient("test", "ds", true)
	_ = c.ClearTenantData(context.Background(), "all")
	tenant := "tenant-batch"
	facts := []domain.SellOutFact{
		{
			RecordID: "1", TenantID: tenant, RetailerChain: "fathalla",
			StoreID: "s1", StoreName: "الرحاب", Category: "صابون", Barcode: "a",
			SKUName: "A", QuantitySold: 10, NetRevenue: 40,
			TransactionDate: "2026-01-10", IsOwnBrand: true,
		},
		{
			RecordID: "2", TenantID: tenant, RetailerChain: "fathalla",
			StoreID: "s2", StoreName: "سموحة", Category: "صابون", Barcode: "a",
			SKUName: "A", QuantitySold: 5, NetRevenue: 20,
			TransactionDate: "2026-02-10", IsOwnBrand: true,
		},
		{
			RecordID: "3", TenantID: tenant, RetailerChain: "fathalla",
			StoreID: "s1", StoreName: "الرحاب", Category: "شاور", Barcode: "b",
			SKUName: "B", QuantitySold: 8, NetRevenue: 16,
			TransactionDate: "2026-01-15", IsOwnBrand: true,
		},
	}
	if err := c.InsertSellOutFacts(context.Background(), facts); err != nil {
		t.Fatal(err)
	}
	cats := []string{"صابون", "شاور"}
	start := time.Now()
	batch, err := c.BuildShareTargetCascadesBatch(context.Background(), tenant, "fathalla", 2026, cats, nil, map[string]bool{"صابون": true})
	if err != nil {
		t.Fatal(err)
	}
	batchDur := time.Since(start)

	start = time.Now()
	for _, cat := range cats {
		br, skus, months, err := c.BuildShareTargetCascadeInputs(context.Background(), tenant, "fathalla", cat, 2026, nil)
		if err != nil {
			t.Fatal(err)
		}
		got := batch[cat]
		if len(got.Branches) != len(br) {
			t.Fatalf("%s branches batch=%d single=%d", cat, len(got.Branches), len(br))
		}
		if len(got.Months) != len(months) {
			t.Fatalf("%s months batch=%d single=%d", cat, len(got.Months), len(months))
		}
		if cat == "صابون" {
			if len(got.SKUsByBranch) == 0 || len(skus) == 0 {
				t.Fatalf("صابون should have SKUs")
			}
		} else if len(got.SKUsByBranch) != 0 {
			// skuFor limited to صابون only when calling batch above — but
			// BuildShareTargetCascadeInputs uses skuFor=nil (all). Compare branches/months only.
			_ = skus
		}
	}
	singleDur := time.Since(start)
	t.Logf("batch=%s two-singles-via-batch-wrapper=%s", batchDur, singleDur)
	soap := batch["صابون"]
	if len(soap.Branches) < 2 {
		t.Fatalf("expected 2 branches for صابون, got %+v", soap.Branches)
	}
	if len(soap.SKUsByBranch["s1"]) == 0 {
		t.Fatalf("expected SKUs for s1: %+v", soap.SKUsByBranch)
	}
	shower := batch["شاور"]
	if len(shower.SKUsByBranch) != 0 {
		t.Fatalf("skuFor should skip SKUs for شاور, got %+v", shower.SKUsByBranch)
	}
}

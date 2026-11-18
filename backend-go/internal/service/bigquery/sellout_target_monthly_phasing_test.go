package bigquery

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestBuildSellOutMonthlyPhasingEqualSplit(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	tenant := "tenant-adeco"
	c.records = []domain.SellOutFact{
		{
			TenantID:        tenant,
			RetailerChain:   "fathalla",
			IsOwnBrand:      true,
			TransactionDate: "2026-01-15",
			NetRevenue:      1000,
			QuantitySold:    10,
		},
		{
			TenantID:        tenant,
			RetailerChain:   "fathalla",
			IsOwnBrand:      true,
			TransactionDate: "2026-02-10",
			NetRevenue:      2000,
			QuantitySold:    20,
		},
	}

	trec := domain.TargetRecord{
		ID:            "t1",
		TenantID:      tenant,
		TargetType:    "sell_out",
		RetailerChain: "fathalla",
		Year:          2026,
		Month:         0,
		BranchName:    "كل الفروع",
		Category:      "كل الفئات",
	}

	months := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey(tenant), trec, 12000, 120)
	if len(months) != 12 {
		t.Fatalf("expected 12 months, got %d", len(months))
	}
	if months[0].TargetRevenueEGP != 1000 {
		t.Fatalf("jan target want 1000 got %v", months[0].TargetRevenueEGP)
	}
	if months[0].ActualRevenueEGP != 1000 {
		t.Fatalf("jan actual want 1000 got %v", months[0].ActualRevenueEGP)
	}
	if months[1].ActualRevenueEGP != 2000 {
		t.Fatalf("feb actual want 2000 got %v", months[1].ActualRevenueEGP)
	}
	if months[2].ActualRevenueEGP != 0 {
		t.Fatalf("mar actual want 0 got %v", months[2].ActualRevenueEGP)
	}
}

func TestBuildSellOutMonthlyPhasingSingleMonth(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	trec := domain.TargetRecord{
		ID:            "t-mar",
		TenantID:      "tenant-adeco",
		TargetType:    "sell_out",
		RetailerChain: "fathalla",
		Year:          2026,
		Month:         3,
		BranchName:    "كل الفروع",
		Category:      "كل الفئات",
	}
	months := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey("tenant-adeco"), trec, 5000, 50)
	if len(months) != 1 {
		t.Fatalf("expected 1 month, got %d", len(months))
	}
	if months[0].Month != 3 {
		t.Fatalf("want month 3 got %d", months[0].Month)
	}
	if months[0].TargetRevenueEGP != 5000 {
		t.Fatalf("want target 5000 got %v", months[0].TargetRevenueEGP)
	}
}

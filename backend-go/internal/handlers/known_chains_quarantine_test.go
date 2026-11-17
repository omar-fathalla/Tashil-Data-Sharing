package handlers

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
)

// Counted Sell-In is whatever ingestion kept. A chain that exists only on quarantined unknown
// customers must not be offered in the dropdown, and a quarantined row must not inflate the count
// of a chain that also has an approved customer.
func TestKnownChainsSkipQuarantinedCustomers(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	reg := customers.New(nil)
	ctx := context.Background()
	const tenant = "tenant-qchain"

	if _, err := reg.Decide(ctx, tenant, "عميل معروف", customers.StatusApproved, "KnownCo", "", "admin@test"); err != nil {
		t.Fatal(err)
	}
	recs := []domain.SellInRecord{
		{TenantID: tenant, CustomerName: "عميل معروف", RetailerChain: "KnownCo", Year: 2026, MonthNum: 1, NetQtyCases: 1, NetValueEGP: 10},
		{TenantID: tenant, CustomerName: "عميل مجهول", RetailerChain: "MysteryCo", Year: 2026, MonthNum: 2, NetQtyCases: 1, NetValueEGP: 50},
		{TenantID: tenant, CustomerName: "عميل مجهول آخر", RetailerChain: "KnownCo", Year: 2026, MonthNum: 3, NetQtyCases: 1, NetValueEGP: 80},
	}
	kept, held := reg.Partition(ctx, tenant, "sheet.xlsx", "KnownCo", recs, true)
	if len(kept) != 1 {
		t.Fatalf("approved rows kept: %+v", kept)
	}
	if len(held) != 2 {
		t.Fatalf("quarantine: %+v", held)
	}
	if err := bq.SetSellInRecords(ctx, tenant, "sheet.xlsx", kept); err != nil {
		t.Fatal(err)
	}
	chains, err := bq.KnownChainsWithData(ctx, tenant)
	if err != nil {
		t.Fatal(err)
	}
	if len(chains) != 1 {
		t.Fatalf("chains: %+v", chains)
	}
	got := chains[0]
	if got.Key != "knownco" || got.Name != "knownco" {
		t.Fatalf("saved key must be the normalized chain, got %+v", got)
	}
	if got.SellInRows != 1 || got.RowCount != 1 {
		t.Fatalf("quarantined row on the same chain must not count: %+v", got)
	}
	for _, ch := range chains {
		if ch.Key == "mysteryco" || ch.Key == "MysteryCo" {
			t.Fatalf("quarantined chain listed: %+v", ch)
		}
	}
}

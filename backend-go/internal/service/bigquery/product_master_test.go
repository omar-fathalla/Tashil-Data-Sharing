package bigquery

import (
	"context"
	"math"
	"path/filepath"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestProductMasterEnrichmentAndPullStats(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", filepath.Join(t.TempDir(), "pm"))
	ctx := context.Background()
	client := NewClient("test-proj", "test-ds", true)

	summary := &domain.ProductMasterSummaryResponse{
		TenantID:           "tenant-adeco",
		CompanyName:        "شركة الاسكندرية للكيماويات و المنظفات ( ادكو )",
		SheetDateLabel:     "تحديث 01-08-2026",
		DefaultDiscountPct: 0.10,
		DefaultVATRate:     0.14,
		Items: []domain.ProductMasterItem{
			{
				SerialNo:             1,
				ItemCode:             "FGCL-0550-0001",
				ItemCodePrefix:       "FGCL",
				Barcode:              "6223000231227",
				OfficialName:         "كلوريل أبيض 550 جم",
				Brand:                "كلوريل (Clorel)",
				Category:             "كلور ومبيضات",
				ItemType:             "عادي",
				PackagingType:        "عبوة",
				UnitsPerCarton:       20,
				VATRate:              0.14,
				UnitPriceExclVAT:     12.281,
				UnitPriceInclVAT:     14.0,
				CartonPriceExclVAT:   245.61,
				CartonPriceInclVAT:   280.0,
				InvoiceDiscountPct:   0.10,
				NetUnitInvoiceCost:   12.60,
				NetCartonInvoiceCost: 252.0,
			},
			{
				SerialNo:             2,
				ItemCode:             "PRHC-0600-0002",
				ItemCodePrefix:       "PRHC",
				Barcode:              "6223000239999",
				OfficialName:         "عرض ديفاتول مطهر 2 عبوة",
				Brand:                "ديفا (Diva)",
				Category:             "منظفات ومطهرات منزلية",
				ItemType:             "عرض",
				PackagingType:        "شرينك",
				UnitsPerCarton:       6,
				VATRate:              0.14,
				UnitPriceExclVAT:     50.0,
				UnitPriceInclVAT:     57.0,
				CartonPriceExclVAT:   300.0,
				CartonPriceInclVAT:   342.0,
				InvoiceDiscountPct:   0.10,
				NetUnitInvoiceCost:   51.30,
				NetCartonInvoiceCost: 307.80,
			},
		},
	}

	if _, err := client.SetProductMaster(ctx, "tenant-adeco", summary); err != nil {
		t.Fatalf("SetProductMaster failed: %v", err)
	}

	// Insert POS record for FGCL-0550-0001 (by barcode only)
	err := client.ReplaceTenantFacts(ctx, "tenant-adeco", []domain.SellOutFact{
		{
			RecordID:        "fact_1",
			TenantID:        "tenant-adeco",
			RetailerChain:   "fathalla",
			StoreID:         "fat_smouha",
			StoreName:       "سموحة",
			Barcode:         "6223000231227",
			SKUName:         "كلوريل 550",
			QuantitySold:    40,
			NetRevenue:      600.0,
			UnitPrice:       15.0,
			TransactionDate: "2026-08-10",
			IsOwnBrand:      true,
		},
	})
	if err != nil {
		t.Fatalf("ReplaceTenantFacts failed: %v", err)
	}

	// Verify SellOutRecords enrichment & phonetic search (fgsl)
	recs, total, err := client.GetSellOutRecords(ctx, "tenant-adeco", RecordFilter{
		SearchQuery: "fgsl-0550",
	})
	if err != nil || total != 1 || len(recs) != 1 {
		t.Fatalf("expected 1 SellOutRecord for phonetic query 'fgsl-0550', got total=%d len=%d err=%v", total, len(recs), err)
	}
	if recs[0].ItemCode != "FGCL-0550-0001" || recs[0].UnitsPerCarton != 20 || recs[0].SKUName != "كلوريل أبيض 550 جم" {
		t.Errorf("unexpected enriched SellOutFact: %+v", recs[0])
	}

	// Verify ProductMaster pull status & PR prefix filtering
	pmAll, err := client.GetProductMaster(ctx, "tenant-adeco", ProductMasterFilter{})
	if err != nil {
		t.Fatalf("GetProductMaster failed: %v", err)
	}
	if pmAll.ActiveInChainsCount != 1 || pmAll.UnpulledSKUsCount != 1 {
		t.Errorf("expected ActiveInChainsCount=1, UnpulledSKUsCount=1, got active=%d unpulled=%d", pmAll.ActiveInChainsCount, pmAll.UnpulledSKUsCount)
	}
	if !pmAll.Items[0].IsActiveInChains || pmAll.Items[0].TotalPOSUnitsSold != 40 || math.Abs(pmAll.Items[0].TotalPOSCartonsSold-2.0) > 0.01 {
		t.Errorf("expected FGCL-0550-0001 active with 40 units (2.0 cartons), got %+v", pmAll.Items[0])
	}

	pmUnpulled, err := client.GetProductMaster(ctx, "tenant-adeco", ProductMasterFilter{PullStatus: "unpulled"})
	if err != nil || len(pmUnpulled.Items) != 1 || pmUnpulled.Items[0].ItemCode != "PRHC-0600-0002" {
		t.Errorf("expected 1 unpulled SKU PRHC-0600-0002, got %+v", pmUnpulled)
	}

	pmPR, err := client.GetProductMaster(ctx, "tenant-adeco", ProductMasterFilter{Prefix: "PR"})
	if err != nil || len(pmPR.Items) != 1 || pmPR.Items[0].ItemCode != "PRHC-0600-0002" {
		t.Errorf("expected PR prefix filter to match PRHC-0600-0002, got %+v", pmPR)
	}

	// Verify UpsertProductMasterItem updates barcode & price and re-enriches existing SellOutFacts
	_, err = client.UpsertProductMasterItem(ctx, "tenant-adeco", domain.ProductMasterItem{
		ItemCode:           "FGCL-0550-0001",
		Barcode:            "6223000238888",
		OfficialName:       "كلوريل أبيض 550 جم محدث",
		UnitsPerCarton:     10,
		VATRate:            0.14,
		UnitPriceExclVAT:   20.0,
		InvoiceDiscountPct: 0.10,
	})
	if err != nil {
		t.Fatalf("UpsertProductMasterItem failed: %v", err)
	}

	recsAfter, _, _ := client.GetSellOutRecords(ctx, "tenant-adeco", RecordFilter{
		SearchQuery: "6223000238888",
	})
	if len(recsAfter) != 1 || recsAfter[0].Barcode != "6223000238888" || recsAfter[0].UnitsPerCarton != 10 {
		t.Errorf("expected SellOutFact barcode and UnitsPerCarton to be updated on re-enrichment, got %+v", recsAfter)
	}

	// Verify CPFR Dashboard uses SKU UnitsPerCarton (10 units/carton -> 40 units = 4.0 cartons) and SearchQuery
	cpfr, err := client.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{
		SearchQuery: "FGCL-0550-0001",
	})
	if err != nil {
		t.Fatalf("GetCPFRDashboard failed: %v", err)
	}
	if len(cpfr.MonthlyReconciliation) != 1 || math.Abs(cpfr.MonthlyReconciliation[0].SellOutEstCases-4.0) > 0.01 {
		t.Errorf("expected CPFR SellOutEstCases=4.0 (40 units / 10 units_per_carton), got %+v", cpfr.MonthlyReconciliation)
	}
}

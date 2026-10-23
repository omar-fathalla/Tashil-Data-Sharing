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

func TestProductMasterDiffDetectionAndPriceChangeFilter(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", filepath.Join(t.TempDir(), "pm_diff"))
	ctx := context.Background()
	client := NewClient("test-proj", "test-ds", true)

	sheet1 := &domain.ProductMasterSummaryResponse{
		TenantID:           "tenant-diff",
		CompanyName:        "أدكو",
		SheetDateLabel:     "تحديث 01-08-2026",
		SourceFilename:     "sheet_aug_2026.xlsx",
		DefaultDiscountPct: 0.10,
		DefaultVATRate:     0.14,
		Items: []domain.ProductMasterItem{
			{
				SerialNo:           1,
				ItemCode:           "FGCL-0550-0001",
				Barcode:            "6223000231227",
				OfficialName:       "كلوريل أبيض 550 جم",
				UnitsPerCarton:     20,
				VATRate:            0.14,
				UnitPriceExclVAT:   10.0,
				UnitPriceInclVAT:   11.40,
				InvoiceDiscountPct: 0.10,
			},
			{
				SerialNo:           2,
				ItemCode:           "FGDG-0600-0002",
				Barcode:            "6223000231228",
				OfficialName:       "فيبا أطباق 600 مل",
				UnitsPerCarton:     12,
				VATRate:            0.14,
				UnitPriceExclVAT:   20.0,
				UnitPriceInclVAT:   22.80,
				InvoiceDiscountPct: 0.10,
			},
			{
				SerialNo:           3,
				ItemCode:           "FGGC-0500-0003",
				Barcode:            "6223000231229",
				OfficialName:       "ملمع زجاج 500 مل",
				UnitsPerCarton:     12,
				VATRate:            0.14,
				UnitPriceExclVAT:   15.0,
				UnitPriceInclVAT:   17.10,
				InvoiceDiscountPct: 0.10,
			},
		},
	}

	if _, err := client.SetProductMaster(ctx, "tenant-diff", sheet1); err != nil {
		t.Fatalf("SetProductMaster sheet1 failed: %v", err)
	}

	// Upload Sheet 2: SKU 1 price increased, SKU 2 price decreased, SKU 3 unchanged, SKU 4 new
	sheet2 := &domain.ProductMasterSummaryResponse{
		TenantID:           "tenant-diff",
		CompanyName:        "أدكو",
		SheetDateLabel:     "تحديث 01-09-2026",
		SourceFilename:     "sheet_sep_2026.xlsx",
		DefaultDiscountPct: 0.10,
		DefaultVATRate:     0.14,
		Items: []domain.ProductMasterItem{
			{
				SerialNo:           1,
				ItemCode:           "FGCL-0550-0001",
				Barcode:            "6223000231227",
				OfficialName:       "كلوريل أبيض 550 جم",
				UnitsPerCarton:     20,
				VATRate:            0.14,
				UnitPriceExclVAT:   12.0,
				UnitPriceInclVAT:   13.68, // Up from 11.40 (+20%)
				InvoiceDiscountPct: 0.10,
			},
			{
				SerialNo:           2,
				ItemCode:           "FGDG-0600-0002",
				Barcode:            "6223000231228",
				OfficialName:       "فيبا أطباق 600 مل",
				UnitsPerCarton:     12,
				VATRate:            0.14,
				UnitPriceExclVAT:   18.0,
				UnitPriceInclVAT:   20.52, // Down from 22.80 (-10%)
				InvoiceDiscountPct: 0.10,
			},
			{
				SerialNo:           3,
				ItemCode:           "FGGC-0500-0003",
				Barcode:            "6223000231229",
				OfficialName:       "ملمع زجاج 500 مل",
				UnitsPerCarton:     12,
				VATRate:            0.14,
				UnitPriceExclVAT:   15.0,
				UnitPriceInclVAT:   17.10, // Unchanged
				InvoiceDiscountPct: 0.10,
			},
			{
				SerialNo:           4,
				ItemCode:           "FGDW-0900-0004",
				Barcode:            "6223000231230",
				OfficialName:       "أقراص غسالات أطباق جديد",
				UnitsPerCarton:     6,
				VATRate:            0.14,
				UnitPriceExclVAT:   100.0,
				UnitPriceInclVAT:   114.0, // New SKU
				InvoiceDiscountPct: 0.10,
			},
		},
	}

	diff, err := client.SetProductMaster(ctx, "tenant-diff", sheet2)
	if err != nil {
		t.Fatalf("SetProductMaster sheet2 failed: %v", err)
	}
	if diff == nil {
		t.Fatalf("expected non-nil diff summary when uploading second sheet")
	}
	if diff.PriceIncreasedCount != 1 || diff.PriceDecreasedCount != 1 || diff.PriceUnchangedCount != 1 || diff.NewSKUsCount != 1 {
		t.Errorf("unexpected diff counts: %+v", diff)
	}

	// Test PriceChange filters: up, down, new, changed, same
	pmUp, _ := client.GetProductMaster(ctx, "tenant-diff", ProductMasterFilter{PriceChange: "up"})
	if len(pmUp.Items) != 1 || pmUp.Items[0].ItemCode != "FGCL-0550-0001" || pmUp.Items[0].PrevUnitPriceInclVAT != 11.40 {
		t.Errorf("expected 1 'up' item FGCL-0550-0001 with prev=11.40, got %+v", pmUp.Items)
	}

	pmDown, _ := client.GetProductMaster(ctx, "tenant-diff", ProductMasterFilter{PriceChange: "down"})
	if len(pmDown.Items) != 1 || pmDown.Items[0].ItemCode != "FGDG-0600-0002" {
		t.Errorf("expected 1 'down' item FGDG-0600-0002, got %+v", pmDown.Items)
	}

	pmNew, _ := client.GetProductMaster(ctx, "tenant-diff", ProductMasterFilter{PriceChange: "new"})
	if len(pmNew.Items) != 1 || pmNew.Items[0].ItemCode != "FGDW-0900-0004" {
		t.Errorf("expected 1 'new' item FGDW-0900-0004, got %+v", pmNew.Items)
	}

	pmChanged, _ := client.GetProductMaster(ctx, "tenant-diff", ProductMasterFilter{PriceChange: "changed"})
	if len(pmChanged.Items) != 3 {
		t.Errorf("expected 3 'changed' items (up+down+new), got %d", len(pmChanged.Items))
	}

	pmSame, _ := client.GetProductMaster(ctx, "tenant-diff", ProductMasterFilter{PriceChange: "same"})
	if len(pmSame.Items) != 1 || pmSame.Items[0].ItemCode != "FGGC-0500-0003" {
		t.Errorf("expected 1 'same' item FGGC-0500-0003, got %+v", pmSame.Items)
	}
}

func TestCrosswalkDisambiguationAndCPFRReconciliation(t *testing.T) {
	ctx := context.Background()
	client := NewClient("test-proj", "test-ds", true)

	// 1. Verify all 10 Fathalla POS supplemental/crosswalk barcodes resolve 100% in tenant-adeco
	supplementalBarcodes := map[string]string{
		"6223000234266": "PRHC-1100-0001",
		"6223000234402": "PRHC-1100-0002",
		"6223004148064": "PRGC-0600-0001",
		"6223000236222": "PRGC-0475-0001",
		"6223000234211": "FGHC-0500-0091",
		"6223004148521": "FGGC-0475-0010",
		"6223000237038": "FGGC-0475-0011",
		"6223000236734": "FGLC-0750-0091",
		"6223004145667": "PRHC-0000-0091",
		"6223000232231": "FGDG-0750-0091",
	}
	for bar, wantCode := range supplementalBarcodes {
		pm, ok := client.LookupProductMaster("tenant-adeco", "", bar, "")
		if !ok || pm.ItemCode != wantCode {
			t.Errorf("expected barcode %s to resolve to %s, got ok=%v code=%s", bar, wantCode, ok, pm.ItemCode)
		}
		if pm.InvoiceDiscountPct != 0.10 || pm.NetUnitInvoiceCost <= 0 || pm.NetCartonInvoiceCost <= 0 {
			t.Errorf("expected clean discount and net costs for %s, got %+v", bar, pm)
		}
	}

	// 2. Verify shared barcode disambiguation (6223000230015 -> regular FGCL-1050-0001 vs promo PRHC-1050-0001)
	regPM, okReg := client.LookupProductMaster("tenant-adeco", "", "6223000230015", "كلوريل أبيض 1050 جم")
	if !okReg || regPM.ItemType != "عادي" {
		t.Errorf("expected regular item for 'كلوريل أبيض 1050 جم' on shared barcode 6223000230015, got %+v", regPM)
	}
	promoPM, okPromo := client.LookupProductMaster("tenant-adeco", "", "6223000230015", "عرض كلوريل أبيض 1050 جم")
	if !okPromo || promoPM.ItemType != "عرض" {
		t.Errorf("expected promo item for 'عرض كلوريل أبيض 1050 جم' on shared barcode 6223000230015, got %+v", promoPM)
	}

	// 3. Verify CPFR reconciliation does not inflate ClosingStockCases with awaiting_sell_out months
	// and does not mix 2025 Sell-Out into 2026 Sell-In when Year=0
	_ = client.ReplaceTenantFacts(ctx, "tenant-adeco", []domain.SellOutFact{
		{
			RecordID:        "f_2025_jan",
			TenantID:        "tenant-adeco",
			RetailerChain:   "fathalla",
			StoreID:         "fat_smouha",
			StoreName:       "سموحة",
			Barcode:         "6223000230015",
			SKUName:         "كلوريل أبيض 1050 جم",
			QuantitySold:    240, // 2025 Sell-Out (must not contaminate 2026 Sell-In when Year=0)
			NetRevenue:      6000.0,
			UnitPrice:       25.0,
			TransactionDate: "2025-01-15",
			IsOwnBrand:      true,
		},
		{
			RecordID:        "f_jan",
			TenantID:        "tenant-adeco",
			RetailerChain:   "fathalla",
			StoreID:         "fat_smouha",
			StoreName:       "سموحة",
			Barcode:         "6223000230015",
			SKUName:         "كلوريل أبيض 1050 جم",
			QuantitySold:    120, // 10 cartons (12 units/carton)
			NetRevenue:      3000.0,
			UnitPrice:       25.0,
			TransactionDate: "2026-01-15",
			IsOwnBrand:      true,
		},
	})
	_ = client.SetSellInRecords(ctx, "tenant-adeco", "plan_2026.xlsx", []domain.SellInRecord{
		{
			RecordID:      "si_jan",
			TenantID:      "tenant-adeco",
			RetailerChain: "fathalla",
			Year:          2026,
			MonthNum:      1,
			RegionCode:    "ALX",
			Governorate:   "الإسكندرية",
			Sector:        "MT",
			Brand:         "كلوريل (Clorel)",
			ItemCode:      regPM.ItemCode,
			Barcode:       "6223000230015",
			ItemName:      regPM.OfficialName,
			PromotionType: "عادي",
			NetQtyCases:   15.0, // 15 supplied - 10 sold = 5 remaining reconciled cases
			NetValueEGP:   3500.0,
		},
		{
			RecordID:      "si_oct",
			TenantID:      "tenant-adeco",
			RetailerChain: "fathalla",
			Year:          2026,
			MonthNum:      10,
			RegionCode:    "ALX",
			Governorate:   "الإسكندرية",
			Sector:        "MT",
			Brand:         "كلوريل (Clorel)",
			ItemCode:      regPM.ItemCode,
			Barcode:       "6223000230015",
			ItemName:      regPM.OfficialName,
			PromotionType: "عادي",
			NetQtyCases:   40.0, // Pending Sell-Out month (Oct 2026)
			NetValueEGP:   9200.0,
		},
	})

	cpfr, err := client.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{
		RetailerChain: "fathalla",
		Year:          0, // Default Year=0 from CPFRDashboardScreen
	})
	if err != nil {
		t.Fatalf("GetCPFRDashboard failed: %v", err)
	}
	if cpfr.MatchedMonthsCount != 1 || cpfr.PendingSellOutMonthsCount != 1 {
		t.Errorf("expected 1 matched month (Jan 2026) and 1 pending month (Oct 2026) even when Year=0, got matched=%d pending=%d", cpfr.MatchedMonthsCount, cpfr.PendingSellOutMonthsCount)
	}
	if math.Abs(cpfr.MatchedRemainingCases-5.0) > 0.01 {
		t.Errorf("expected MatchedRemainingCases=5.0, got %.2f", cpfr.MatchedRemainingCases)
	}
	if math.Abs(cpfr.TotalEstimatedStockCases-5.0) > 0.01 {
		t.Errorf("expected TotalEstimatedStockCases=5.0 (reconciled without Oct pending inflation), got %.2f", cpfr.TotalEstimatedStockCases)
	}
	if len(cpfr.MonthlyReconciliation) == 2 && math.Abs(cpfr.MonthlyReconciliation[1].ClosingStockCases-5.0) > 0.01 {
		t.Errorf("expected Oct awaiting_sell_out row ClosingStockCases to stay at reconciled 5.0, got %.2f", cpfr.MonthlyReconciliation[1].ClosingStockCases)
	}
	if len(cpfr.InventoryAndPOItems) != 1 || math.Abs(cpfr.InventoryAndPOItems[0].EstimatedStockCases-5.0) > 0.01 {
		t.Errorf("expected SKU EstimatedStockCases=5.0 (reconciled without Oct pending inflation), got %+v", cpfr.InventoryAndPOItems)
	}
}




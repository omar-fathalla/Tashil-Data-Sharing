package gemini

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func TestGeminiAgentCarrefourAnalysis(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	rawCSV := []byte("Store_Code_Branch,Barcode,Sales_Units,Net_Val_EGP\nCarrefour Maadi City Center,6221155001234,142,35500.0\n")

	payload, err := agent.AnalyzeAndNormalize(ctx, "carrefour_daily_sales_adeco.csv", rawCSV)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if payload.RetailerDetected != "carrefour" {
		t.Errorf("expected retailer carrefour, got %s", payload.RetailerDetected)
	}

	if len(payload.NormalizedRecords) == 0 {
		t.Fatalf("expected at least one normalized record")
	}

	first := payload.NormalizedRecords[0]
	if first.ResolvedStoreID != "crf_cairo_maadi" {
		t.Errorf("expected resolved store crf_cairo_maadi, got %s", first.ResolvedStoreID)
	}
}

func TestGeminiAgentFathallaAnalysis(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	rawArabicCSV := []byte("فرع فتح الله,الباركود الدولي,اسم الصنف,الكمية المباعة,صافي المبيعات\nفتح الله جملة ماركت - فرع سموحة,6221155001234,زيت زيتون أديكو 500 مل,185,46250.0\n")

	payload, err := agent.AnalyzeAndNormalize(ctx, "تقرير مبيعات فتح الله اليومية.csv", rawArabicCSV)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if payload.RetailerDetected != "fathalla" {
		t.Errorf("expected retailer fathalla, got %s", payload.RetailerDetected)
	}

	if payload.ColumnMapping.StoreNameColumn != "فرع فتح الله" {
		t.Errorf("expected store column mapped, got %s", payload.ColumnMapping.StoreNameColumn)
	}
}

func TestGeminiAgentLargeCSVWithout4KBTruncation(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	var sb strings.Builder
	sb.WriteString("Store_Code_Branch,Barcode,Item_Description,Category,Sales_Units,Net_Val_EGP,Transaction_Date\n")

	const totalRows = 150
	for i := 1; i <= totalRows; i++ {
		barcode := fmt.Sprintf("6221155%06d", i)
		sb.WriteString(fmt.Sprintf("Carrefour Maadi City Center,%s,Adeco Olive Oil Batch Item %d,زيوت طعام,%d,%.2f,2026-03-07\n",
			barcode, i, 10+i, float64(10+i)*250.0))
	}

	rawBytes := []byte(sb.String())
	if len(rawBytes) <= 4096 {
		t.Fatalf("expected test CSV to exceed 4KB, got %d bytes", len(rawBytes))
	}

	payload, err := agent.AnalyzeAndNormalize(ctx, "carrefour_large_batch.csv", rawBytes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(payload.NormalizedRecords) != totalRows {
		t.Errorf("expected all %d rows to be parsed without 4KB truncation, got %d", totalRows, len(payload.NormalizedRecords))
	}
}

func TestGeminiAgentXLSXParsing(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	rows := [][]string{
		{"فرع فتح الله", "الباركود الدولي", "اسم الصنف", "الفئة", "الكمية المباعة", "صافي المبيعات", "تاريخ البيع"},
		{"فتح الله جملة ماركت - سموحة", "6221155001234", "زيت زيتون أديكو 500 مل", "زيوت طعام", "120", "30000.0", "2026-03-06"},
		{"فتح الله - ستانلي", "6221155001241", "زيت عباد الشمس أديكو 1 لتر", "زيوت طعام", "90", "9900.0", "2026-03-06"},
		{"فتح الله - المنشية", "1234", "صنف بباركود قصير", "زيوت طعام", "15", "1500.0", "2026-03-06"},
	}

	xlsxBytes, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatalf("failed to build sample xlsx: %v", err)
	}

	payload, err := agent.AnalyzeAndNormalize(ctx, "كشف_مبيعات_فروع_فتح_الله_الاسكندرية.xlsx", xlsxBytes)
	if err != nil {
		t.Fatalf("unexpected error parsing xlsx: %v", err)
	}

	if payload.RetailerDetected != "fathalla" {
		t.Errorf("expected retailer fathalla, got %s", payload.RetailerDetected)
	}

	if len(payload.NormalizedRecords) != 3 {
		t.Fatalf("expected 3 normalized records from xlsx, got %d", len(payload.NormalizedRecords))
	}

	if payload.NormalizedRecords[0].ResolvedStoreID != "fat_alex_smouha" {
		t.Errorf("expected fat_alex_smouha, got %s", payload.NormalizedRecords[0].ResolvedStoreID)
	}
	if payload.NormalizedRecords[1].ResolvedStoreID != "fat_alex_stanley" {
		t.Errorf("expected fat_alex_stanley, got %s", payload.NormalizedRecords[1].ResolvedStoreID)
	}
	if len(payload.AnomaliesDetected) != 1 || payload.AnomaliesDetected[0].IssueType != "invalid_barcode" {
		t.Errorf("expected 1 invalid_barcode anomaly on row 3, got %+v", payload.AnomaliesDetected)
	}
}

func TestGeminiAgentSyntheticFallbackPreserved(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	payload, err := agent.AnalyzeAndNormalize(ctx, "carrefour_synthetic.csv", []byte{1, 2, 3})
	if err != nil {
		t.Fatalf("unexpected error on synthetic payload: %v", err)
	}
	if payload.RetailerDetected != "carrefour" || len(payload.NormalizedRecords) == 0 {
		t.Errorf("expected fallback records for synthetic payload, got %+v", payload)
	}
}

func TestGeminiAgentExcelSerialDateAndHeaderDisambiguation(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	// Test Excel serial date 46088 (2026-03-07), title banner row, and Store_ID/Store_Name + Product_Category/Product_Name disambiguation
	rows := [][]string{
		{"تقرير مبيعات كارفور الأسبوعي المجمع"},
		{"Store_ID", "Store_Name", "Barcode", "Product_Category", "Product_Name", "Sales_Units", "Net_Amount", "Transaction_Date"},
		{"CRF_001", "Carrefour Dandy Mall", "6221155001241", "زيوت طعام", "Adeco Pure Sunflower Oil 1L", "120", "13200.0", "46088"},
		{"CRF_002", "Carrefour City Stars", "6221155001258", "زيوت طعام", "Adeco Pure Corn Oil 800ml", "80", "9600.0", "07/03/2026 14:30:00"},
	}

	xlsxBytes, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatalf("failed to build xlsx: %v", err)
	}

	payload, err := agent.AnalyzeAndNormalize(ctx, "carrefour_serial_dates.xlsx", xlsxBytes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(payload.NormalizedRecords) != 2 {
		t.Fatalf("expected 2 records, got %d", len(payload.NormalizedRecords))
	}

	r0 := payload.NormalizedRecords[0]
	if r0.ResolvedStoreID != "crf_giza_dandy" {
		t.Errorf("expected Store_Name 'Carrefour Dandy Mall' to resolve to crf_giza_dandy, got %s (raw: %s)", r0.ResolvedStoreID, r0.RawStoreName)
	}
	if r0.Category != "زيوت طعام" {
		t.Errorf("expected Product_Category 'زيوت طعام', got '%s'", r0.Category)
	}
	if r0.SKUName != "Adeco Pure Sunflower Oil 1L" {
		t.Errorf("expected Product_Name 'Adeco Pure Sunflower Oil 1L', got '%s'", r0.SKUName)
	}
	if r0.TransactionDate != "2026-03-07" {
		t.Errorf("expected Excel serial date 46088 to normalize to 2026-03-07, got %s", r0.TransactionDate)
	}

	r1 := payload.NormalizedRecords[1]
	if r1.TransactionDate != "2026-03-07" {
		t.Errorf("expected '07/03/2026 14:30:00' to normalize to 2026-03-07, got %s", r1.TransactionDate)
	}
}

func TestGeminiAgentRevenueOnlyCSVDefaultsQuantityToOne(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	csvWithoutQty := []byte(
		"Store_Name,Barcode,Item_Description,Net_Val_EGP,Transaction_Date\n" +
			"Carrefour Maadi City Center,6221155001234,Adeco Olive Oil 500ml,2500.0,2026-03-07\n",
	)

	payload, err := agent.AnalyzeAndNormalize(ctx, "carrefour_rev_only.csv", csvWithoutQty)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(payload.AnomaliesDetected) != 0 {
		t.Errorf("expected 0 anomalies for revenue-only sheet, got %+v", payload.AnomaliesDetected)
	}
	if len(payload.NormalizedRecords) != 1 || payload.NormalizedRecords[0].QuantitySold != 1 {
		t.Errorf("expected QuantitySold=1 default, got %+v", payload.NormalizedRecords)
	}
}

func TestGeminiAgentAdcoEgyptianRetailColumnsWithPreamble(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	csvContent := []byte(
		"Details for Net Value,,,,,,,,,\n" +
			",,,,,,,,,\n" +
			"السنة,الشهر,المورد,الفئة,الباركود,إسم الصنف,الوحدة,إسم الفرع,\"صافى كمية\nالمبيعات\",\"صافى قيمة \nالمبيعات\"\n" +
			"2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000238875,فلفيتا معطر ملابس مركز نسيم البحر 750 مل,قطعة,الإبراهيمية,17,612\n" +
			"2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000238868,فلفيتا معطر ملابس مركز همسات اللافندر 750 مل,قطعة,الجمرك,15,540\n" +
			"2025,يناير,ادكو / 318,منعمات ملابس مركزة,6223000234464,فلفيتا منعم ملابس مركز عطر الرفاهيه 1لتر,قطعة,الزيتون,6,763\n",
	)

	payload, err := agent.AnalyzeAndNormalize(ctx, "تقرير مبيعات فروع جملة ماركت.csv", csvContent)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(payload.DiscoveredBranches) != 3 {
		t.Errorf("expected 3 discovered branches, got %d: %+v", len(payload.DiscoveredBranches), payload.DiscoveredBranches)
	}

	if payload.ColumnMapping.StoreNameColumn != "إسم الفرع" {
		t.Errorf("expected StoreNameColumn 'إسم الفرع', got '%s'", payload.ColumnMapping.StoreNameColumn)
	}

	if len(payload.NormalizedRecords) != 3 {
		t.Fatalf("expected 3 records, got %d", len(payload.NormalizedRecords))
	}

	storesExpected := []string{"الإبراهيمية", "الجمرك", "الزيتون"}
	for i, exp := range storesExpected {
		if payload.NormalizedRecords[i].RawStoreName != exp {
			t.Errorf("record %d: expected RawStoreName '%s', got '%s'", i, exp, payload.NormalizedRecords[i].RawStoreName)
		}
	}
}

func TestGeminiAgentDetectRetailerMajorityVotingGomla(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	// Generic filename without any chain name in the title
	csvContent := []byte(
		"الباركود,إسم الصنف,إسم الفرع,الكمية المباعة,صافي المبيعات\n" +
			"6221155001234,Adeco Extra Virgin Olive Oil 500ml,فرع جملة ماركت - الكوثر - شارع المطار,10,2500\n" +
			"6221155001241,Adeco Pure Sunflower Oil 1L,فرع جملة ماركت - جسر السويس,15,1800\n" +
			"6221155001258,Adeco Pure Corn Oil 800ml,فرع جملة ماركت - برج العرب,8,960\n",
	)

	payload, err := agent.AnalyzeAndNormalize(ctx, "Sales_Data_Export_2026.csv", csvContent)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if payload.RetailerDetected != "gomla" {
		t.Errorf("expected RetailerDetected to be 'gomla' via branch majority voting, got '%s'", payload.RetailerDetected)
	}

	if len(payload.DiscoveredBranches) != 3 {
		t.Errorf("expected 3 branches, got %d", len(payload.DiscoveredBranches))
	}
}

func TestGeminiAgentWideMatrixSingleSheetMultiMonthAndSmartInference(t *testing.T) {
	agent := NewAgent("", "gemini-3.8-flash", true)
	ctx := context.Background()

	// Simulates "2025 out.xlsx": single sheet containing multiple months (jan, feb, mar, apr) and year (2025)
	// with unlabeled or arbitrarily named temporal columns to verify smart content-based AI inference.
	rows := [][]string{
		{"المجموعة", "المورد", "الباركود", "الصنف", "سموحة", "جاردينيا", "الاجمالى", "Unlabeled_Col_M", "كمية سموحة", "كمية جاردينيا", "اجمالى كميات", "Unlabeled_Col_Y"},
		{"منظفات", "ادكو (1)", "6223000232514", "فيبا 4 كجم ليمون", "1000", "500", "1500", "jan", "10", "5", "15", "2025"},
		{"منظفات", "ادكو (1)", "6223000232514", "فيبا 4 كجم ليمون", "2000", "1000", "3000", "fe", "20", "10", "30", "2025"},
		{"منظفات", "ادكو (1)", "6223000232514", "فيبا 4 كجم ليمون", "1500", "1500", "3000", "مارس", "15", "15", "30", "2025"},
		{"منظفات", "ادكو (1)", "6223000232514", "فيبا 4 كجم ليمون", "2500", "500", "3000", "apr", "25", "5", "30", "2025"},
	}

	xlsxBytes, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatalf("failed to build xlsx: %v", err)
	}

	payload, err := agent.AnalyzeAndNormalize(ctx, "2025 out.xlsx", xlsxBytes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !payload.IsWideMatrixWorkbook {
		t.Fatalf("expected IsWideMatrixWorkbook=true")
	}

	if len(payload.DetectedSheets) != 4 {
		t.Fatalf("expected 4 virtual monthly sheets (Jan..Apr 2025), got %d: %+v", len(payload.DetectedSheets), payload.DetectedSheets)
	}

	if payload.ReportingPeriodStart != "2025-01-31" || payload.ReportingPeriodEnd != "2025-04-30" {
		t.Errorf("expected period 2025-01-31..2025-04-30, got %s..%s", payload.ReportingPeriodStart, payload.ReportingPeriodEnd)
	}

	var totalAdcoRev float64
	for _, s := range payload.SupplierShares {
		if s.IsTenant {
			totalAdcoRev = s.TotalRevenue
		}
	}
	if totalAdcoRev != 10500 {
		t.Errorf("expected cumulative Adco revenue across all 4 months to be 10500, got %.2f", totalAdcoRev)
	}

	if len(payload.NormalizedRecords) != 8 {
		t.Errorf("expected 8 branch-month records (2 branches x 4 months), got %d", len(payload.NormalizedRecords))
	}
}




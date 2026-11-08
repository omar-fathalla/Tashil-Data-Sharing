package gemini

import (
	"fmt"
	"math"
	"os"
	"strings"
	"testing"
)

func wideReconHeader() []string {
	return []string{
		"المجموعة", "المورد", "الباركود", "الصنف",
		" سموحة", " ستانلى", "الاجمالى", "MONTH",
		"كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR",
	}
}

func TestWideMatrixPositiveAndNegativeUnallocated(t *testing.T) {
	rows := [][]string{
		wideReconHeader(),
		// Positive remainder: branches 100+50=150, total 200 → unallocated +50
		{"منعمات", "ادكو (1)", "6223000233701", "منتج أ", "100", "50", "200", "JAN", "10", "5", "15", "2026"},
		// Negative remainder: branches 80+40=120, total 100 → unallocated -20
		{"منعمات", "ادكو (1)", "6223000233702", "منتج ب", "80", "40", "100", "FEB", "8", "4", "12", "2026"},
		// Competing supplier with positive remainder
		{"منعمات", "يونيلفر", "6223000233799", "منافس", "30", "20", "60", "JAN", "3", "2", "5", "2026"},
	}
	xlsx, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("recon-posneg.xlsx", xlsx)
	if !ok || payload == nil {
		t.Fatal("expected wide parse")
	}

	var total float64
	var unallocRows int
	var unallocSum float64
	suppliers := map[string]bool{}
	for _, r := range payload.NormalizedRecords {
		total += r.NetRevenue
		suppliers[r.Supplier] = true
		if r.RawStoreName == UnallocatedBranchName || strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			unallocRows++
			unallocSum += r.NetRevenue
		}
	}
	if math.Abs(total-360) > 0.01 { // 200+100+60
		t.Fatalf("imported total %.2f want 360 (file الاجمالى sum)", total)
	}
	if unallocRows != 3 {
		t.Fatalf("expected 3 unallocated rows (2 adeco + 1 competitor), got %d", unallocRows)
	}
	if math.Abs(unallocSum-40) > 0.01 { // +50 -20 +10
		t.Fatalf("unallocated sum %.2f want 40", unallocSum)
	}
	if !suppliers["ادكو (1)"] || !suppliers["يونيلفر"] {
		t.Fatalf("expected multiple suppliers, got %v", suppliers)
	}

	var sawValueGap, sawFlag bool
	for _, a := range payload.AnomaliesDetected {
		if a.IssueType == anomalyValueTotalGap {
			sawValueGap = true
		}
	}
	if !sawValueGap {
		t.Fatal("expected value_total_gap anomaly")
	}
	v := validateExtraction(payload, nil)
	mergeWideMatrixReconIntoValidation(v, payload)
	if v.Status != "flagged" {
		t.Fatalf("expected flagged validation, got %s issues=%v", v.Status, v.Issues)
	}
	for _, r := range v.DiffReasons {
		if r == diffReasonUnallocated {
			sawFlag = true
		}
	}
	if !sawFlag {
		t.Fatalf("expected diff reason %s in %v", diffReasonUnallocated, v.DiffReasons)
	}
}

func TestWideMatrixEmptyBranchColumnsStillReconcile(t *testing.T) {
	rows := [][]string{
		wideReconHeader(),
		// Both named branches empty; total 75 → entire amount unallocated
		{"منعمات", "ادكو (1)", "6223000233710", "فارغ فروع", "", "", "75", "MAR", "", "", "0", "2026"},
		// One branch empty, other has value; total exceeds named sum
		{"منعمات", "ادكو (1)", "6223000233711", "فرع واحد", "40", "", "55", "MAR", "4", "", "4", "2026"},
	}
	xlsx, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("recon-empty.xlsx", xlsx)
	if !ok {
		t.Fatal("parse failed")
	}
	var total, unalloc float64
	var namedSmouha float64
	for _, r := range payload.NormalizedRecords {
		total += r.NetRevenue
		if strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			unalloc += r.NetRevenue
		}
		if strings.Contains(r.RawStoreName, "سموحة") {
			namedSmouha += r.NetRevenue
		}
	}
	if math.Abs(total-130) > 0.01 {
		t.Fatalf("total %.2f want 130", total)
	}
	if math.Abs(unalloc-90) > 0.01 { // 75 + 15
		t.Fatalf("unallocated %.2f want 90", unalloc)
	}
	if math.Abs(namedSmouha-40) > 0.01 {
		t.Fatalf("سموحة %.2f want 40", namedSmouha)
	}
}

func TestWideMatrixNoGapNoUnallocated(t *testing.T) {
	rows := [][]string{
		wideReconHeader(),
		{"منعمات", "ادكو (1)", "6223000233720", "متطابق", "100", "50", "150", "APR", "10", "5", "15", "2026"},
		{"منعمات", "يونيلفر", "6223000233721", "متطابق2", "20", "10", "30", "APR", "2", "1", "3", "2026"},
	}
	xlsx, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("recon-nogap.xlsx", xlsx)
	if !ok {
		t.Fatal("parse failed")
	}
	for _, r := range payload.NormalizedRecords {
		if strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			t.Fatalf("unexpected unallocated row: %+v", r)
		}
	}
	for _, a := range payload.AnomaliesDetected {
		if a.IssueType == anomalyValueTotalGap || a.IssueType == anomalyQtyTotalMismatch {
			t.Fatalf("unexpected recon anomaly: %+v", a)
		}
	}
	v := validateExtraction(payload, nil)
	mergeWideMatrixReconIntoValidation(v, payload)
	if v.Status != "ok" {
		t.Fatalf("expected ok, got %s %v", v.Status, v.Issues)
	}
	var total float64
	for _, r := range payload.NormalizedRecords {
		total += r.NetRevenue
	}
	if math.Abs(total-180) > 0.01 {
		t.Fatalf("total %.2f want 180", total)
	}
}

func TestWideMatrixNegativeBranchValuesDoNotInventUnallocated(t *testing.T) {
	rows := [][]string{
		wideReconHeader(),
		// Named branches 100 + (-15) = 85; file total 85 → no unallocated
		{"منعمات", "ادكو (1)", "6223000233740", "مرتجع", "100", "-15", "85", "JUN", "10", "-1", "9", "2026"},
	}
	xlsx, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("recon-neg-branch.xlsx", xlsx)
	if !ok {
		t.Fatal("parse failed")
	}
	var total, unalloc float64
	var sawNegBranch bool
	for _, r := range payload.NormalizedRecords {
		total += r.NetRevenue
		if strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			unalloc += r.NetRevenue
		}
		if r.NetRevenue < 0 && !strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			sawNegBranch = true
		}
	}
	if math.Abs(total-85) > 0.01 {
		t.Fatalf("total %.2f want 85", total)
	}
	if unalloc != 0 {
		t.Fatalf("unallocated %.2f want 0", unalloc)
	}
	if !sawNegBranch {
		t.Fatal("expected negative named-branch record to be kept")
	}
}

func TestWideMatrixQtyMismatchFlaggedBranchQtyTruth(t *testing.T) {
	rows := [][]string{
		wideReconHeader(),
		// Value matches; file qty total 10 but branch qtys 6+5=11
		{"منعمات", "ادكو (1)", "6223000233730", "كمية", "60", "50", "110", "MAY", "6", "5", "10", "2026"},
	}
	xlsx, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("recon-qty.xlsx", xlsx)
	if !ok {
		t.Fatal("parse failed")
	}
	var units int
	for _, r := range payload.NormalizedRecords {
		units += r.QuantitySold
		if strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			t.Fatal("no value gap → must not emit unallocated")
		}
	}
	if units != 11 {
		t.Fatalf("branch qty truth: got %d want 11", units)
	}
	var sawQty bool
	for _, a := range payload.AnomaliesDetected {
		if a.IssueType == anomalyQtyTotalMismatch {
			sawQty = true
		}
	}
	if !sawQty {
		t.Fatal("expected qty_total_mismatch anomaly")
	}
	v := validateExtraction(payload, nil)
	mergeWideMatrixReconIntoValidation(v, payload)
	if v.Status != "flagged" {
		t.Fatalf("expected flagged, got %s", v.Status)
	}
	found := false
	for _, r := range v.DiffReasons {
		if r == diffReasonQtyMismatch {
			found = true
		}
	}
	if !found {
		t.Fatalf("missing %s in %v", diffReasonQtyMismatch, v.DiffReasons)
	}
}

func TestWideMatrixMultiSupplierMultiMonthSynthetic(t *testing.T) {
	header := wideReconHeader()
	rows := [][]string{header}
	// ~60 synthetic rows across 3 months / 2 suppliers with mixed gaps
	for i := 0; i < 20; i++ {
		bc := fmt.Sprintf("%d", 6223000240000+i)
		rows = append(rows, []string{"منعمات", "ادكو (1)", bc, "SKU-A", "10", "5", "20", "JAN", "1", "1", "2", "2026"}) // +5 gap
	}
	for i := 0; i < 20; i++ {
		bc := fmt.Sprintf("%d", 6223000250000+i)
		rows = append(rows, []string{"منعمات", "يونيلفر", bc, "SKU-B", "8", "2", "10", "FEB", "1", "1", "3", "2026"}) // exact value; qty mismatch
	}
	for i := 0; i < 20; i++ {
		bc := fmt.Sprintf("%d", 6223000260000+i)
		rows = append(rows, []string{"منعمات", "ادكو (1)", bc, "SKU-C", "12", "8", "15", "seb", "2", "1", "3", "2026"}) // -5 gap
	}
	xlsx, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("recon-multi.xlsx", xlsx)
	if !ok {
		t.Fatal("parse failed")
	}
	var total, unalloc float64
	var unallocCount int
	months := map[string]bool{}
	for _, r := range payload.NormalizedRecords {
		total += r.NetRevenue
		if len(r.TransactionDate) >= 7 {
			months[r.TransactionDate[:7]] = true
		}
		if strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			unalloc += r.NetRevenue
			unallocCount++
		}
	}
	// JAN: 20*20=400, FEB: 20*10=200, SEP: 20*15=300 → 900
	if math.Abs(total-900) > 0.01 {
		t.Fatalf("total %.2f want 900", total)
	}
	// JAN +5*20=100, SEP -5*20=-100 → net 0 unalloc value but 40 rows
	if unallocCount != 40 {
		t.Fatalf("unallocated rows %d want 40", unallocCount)
	}
	if math.Abs(unalloc) > 0.01 {
		t.Fatalf("net unallocated %.2f want 0", unalloc)
	}
	for _, m := range []string{"2026-01", "2026-02", "2026-09"} {
		if !months[m] {
			t.Fatalf("missing month %s in %v", m, months)
		}
	}
	v := validateExtraction(payload, nil)
	mergeWideMatrixReconIntoValidation(v, payload)
	if v.Status != "flagged" {
		t.Fatalf("expected flagged recon warnings, got %s", v.Status)
	}
}

// Optional acceptance against a locally provided real workbook (never committed).
// Skips unless F2_XLSX points at a readable .xlsx.
func TestRealF2AdecoAcceptance(t *testing.T) {
	path := os.Getenv("F2_XLSX")
	if path == "" {
		t.Skip("set F2_XLSX to run optional full-file Adeco acceptance")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := parseFullTabularPayload("f2.xlsx", raw)
	if !ok || payload == nil {
		t.Fatal("expected wide-matrix parse of f2.xlsx")
	}

	wantMonth := map[string]float64{
		"2026-01": 9536992.70,
		"2026-02": 10397073.65,
		"2026-03": 10071096.50,
		"2026-04": 10559132.50,
		"2026-05": 12541294.50,
		"2026-06": 11401466.70,
		"2026-07": 14453318.30,
		"2026-08": 14780898.55,
		"2026-09": 15058210.35,
		"2026-10": 18333871.05,
	}
	monthTot := map[string]float64{}
	var adecoTotal, unallocOct float64
	var unallocOctRows int
	for _, r := range payload.NormalizedRecords {
		if !isAdcoOrTenantSupplier(r.Supplier) {
			continue
		}
		adecoTotal += r.NetRevenue
		if len(r.TransactionDate) < 7 {
			continue
		}
		ym := r.TransactionDate[:7]
		monthTot[ym] += r.NetRevenue
		if ym == "2026-10" && strings.Contains(r.RawStoreName, UnallocatedBranchName) {
			unallocOct += r.NetRevenue
			unallocOctRows++
		}
	}
	if math.Abs(adecoTotal-127133354.80) > 0.05 {
		t.Fatalf("Adeco total %.2f want 127133354.80", adecoTotal)
	}
	if math.Abs(unallocOct-192868.00) > 0.05 {
		t.Fatalf("Oct unallocated %.2f want 192868.00 (rows=%d)", unallocOct, unallocOctRows)
	}
	for ym, want := range wantMonth {
		got := monthTot[ym]
		if math.Abs(got-want) > 0.05 {
			t.Errorf("%s: got %.2f want %.2f", ym, got, want)
		}
	}
	v := validateExtraction(payload, nil)
	mergeWideMatrixReconIntoValidation(v, payload)
	if v.Status == "ok" {
		t.Fatal("expected flagged recon warnings on real f2")
	}
}

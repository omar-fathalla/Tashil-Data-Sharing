package gemini

import (
	"math"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func syntheticIn26Path(t *testing.T) string {
	t.Helper()
	_, thisFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(thisFile), "testdata", "in26_synthetic.xlsx")
}

// Synthetic in26-layout fixture (no real customer data): TO→value, Invoice+Return,
// دمنهور vs دمنهور - الاستاد, double-space trim, Branch=region ignored for store.
func TestIn26SyntheticFixtureTOAndBranches(t *testing.T) {
	raw, err := os.ReadFile(syntheticIn26Path(t))
	if err != nil {
		t.Fatal(err)
	}
	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26_synthetic.xlsx", raw, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if rep == nil || rep.Layout != "gp_sop_export" {
		t.Fatalf("layout: %+v", rep)
	}
	if len(recs) != 75 {
		t.Fatalf("expected 75 rows, got %d", len(recs))
	}
	names := map[string]bool{}
	damanhourID, stadiumID := "", ""
	var to float64
	var sawNeg bool
	for _, r := range recs {
		names[r.CustomerName] = true
		to += r.NetValueEGP
		if r.NetValueEGP < 0 {
			sawNeg = true
		}
		if r.RetailerChain != "fathalla" {
			t.Fatalf("chain %q on %q", r.RetailerChain, r.CustomerName)
		}
		// Branch column is region (ALX/BHR/…) — must not become the store name.
		if r.CustomerName == "ALX" || r.CustomerName == "BHR" || r.CustomerName == "TNT" || r.CustomerName == "BRG" {
			t.Fatalf("region code leaked into CustomerName: %q", r.CustomerName)
		}
		switch r.CustomerName {
		case "عائله فتح الله ماركت - دمنهور":
			damanhourID = r.CustomerBranchCode
		case "عائله فتح الله ماركت - دمنهور - الاستاد":
			stadiumID = r.CustomerBranchCode
		}
	}
	if !sawNeg {
		t.Fatal("expected a Return row with negative TO (current sign-preserving behavior)")
	}
	if _, ok := names["عائله فتح الله ماركت - فلمنج"]; !ok {
		t.Fatalf("whitespace-collapsed فلمنج missing: %v", names)
	}
	if damanhourID == "" || stadiumID == "" || damanhourID == stadiumID {
		t.Fatalf("stadium must have distinct store id from plain دمنهور: %q vs %q", damanhourID, stadiumID)
	}
	// 40*10 + 20 + 30 + 40 + 50 - 5 + 30*3 = 400+20+30+40+50-5+90 = 625
	if to != 625 {
		t.Fatalf("TO sum got %v want 625", to)
	}
}

// Optional full-file acceptance against a locally provided real workbook.
// Skips unless IN26_XLSX points at a readable .xlsx (never committed).
func TestRealIn26Acceptance(t *testing.T) {
	path := os.Getenv("IN26_XLSX")
	if path == "" {
		t.Skip("set IN26_XLSX to run optional full-file acceptance")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.xlsx", raw, "fathalla")
	if err != nil {
		t.Fatalf("parse in26: %v", err)
	}
	if rep == nil || rep.Layout != "gp_sop_export" {
		t.Fatalf("expected gp_sop_export, got %+v", rep)
	}
	if len(recs) != 40927 {
		t.Fatalf("expected 40927 rows, got %d", len(recs))
	}
	names := map[string]bool{}
	var to float64
	for _, r := range recs {
		names[r.CustomerName] = true
		to += r.NetValueEGP
	}
	if len(names) != 56 {
		t.Fatalf("expected 56 branches, got %d", len(names))
	}
	if math.Abs(to-133191402.85) > 0.02 {
		t.Fatalf("TO sum: got %.2f want 133191402.85", to)
	}
}

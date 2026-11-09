package gemini

import (
	"testing"
)

// Return rows keep Document Date month (not invoice month) and negative TO/QTY as-is.
func TestGPSOPReturnUsesDocumentDateMonthAndKeepsNegatives(t *testing.T) {
	hdr := []string{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", "TO", "Branch"}
	rows := [][]string{
		hdr,
		{"Invoice", "INV-1", "2026-01-15", "FG-1", "صنف QA", "CTN", "10", "L1", "C1", "عائله فتح الله ماركت - فرع QA", "KA", "100", "ALX"},
		{"Return", "RET-1", "2026-03-20", "FG-1", "صنف QA", "CTN", "-4", "L1", "C1", "عائله فتح الله ماركت - فرع QA", "KA", "-40", "ALX"},
	}
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "returns_month.xlsx", x, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 2 {
		t.Fatalf("expected both invoice+return rows kept, got %d", len(recs))
	}
	if rep.ReturnRows < 1 {
		t.Fatalf("expected ReturnRows counted, got %+v", rep)
	}
	var inv, ret bool
	var sum float64
	for _, r := range recs {
		sum += r.NetValueEGP
		switch {
		case r.MonthNum == 1 && r.NetValueEGP == 100:
			inv = true
		case r.MonthNum == 3 && r.NetValueEGP == -40 && r.NetQtyCases == -4:
			ret = true
			if r.TransactionType == "" || (r.TransactionType != "مرتجع (Return)" && r.NetValueEGP >= 0) {
				t.Fatalf("return tx type: %+v", r)
			}
		default:
			t.Fatalf("unexpected row month=%d val=%v qty=%v", r.MonthNum, r.NetValueEGP, r.NetQtyCases)
		}
	}
	if !inv || !ret {
		t.Fatalf("missing invoice/return: inv=%v ret=%v", inv, ret)
	}
	if sum != 60 {
		t.Fatalf("imported total must equal file total (100-40)=60, got %v", sum)
	}
}

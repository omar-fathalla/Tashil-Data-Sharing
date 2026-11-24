package gemini

import (
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Header of the raw ERP «plan 10 aswak» layout (region in "branch", store columns after customer).
var planTestHeader = []string{"branch", "sector", "sub- sector", "7", "6", "5", "item 1", "item 2", "item 5", "item 3", "item 4",
	"\\", "month", "net Q", "net V", "Ton", "city", "customer", "customer branch", "exp city", "10", "Promotion",
	"officer", "officer mgr", "t.o", "Year", "Q EXP", "V EXP"}

func planTestRow(branchCode string) []string {
	return []string{"ALX", "MT", "KA", "Detergents", "ALX-08940", "Fathalla Market - Parent",
		"item-1", "item-1 normal", "extras", "Rapido", "Rapido", "Full Month", "March", "2", "250.5", "0.01", "Alexandria",
		"Fathalla Market", "Smouha", branchCode, "10", "Normal", "rep", "mgr", "250.5", "2026", "2", "250.5"}
}

func TestPlanMarkerByFileName(t *testing.T) {
	for _, n := range []string{"Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", "adco fathalla sell-in-plan 2026.xlsx", "/tmp/x/Sell_In_Plan.xlsx"} {
		if !domain.IsSellInPlanName(n) {
			t.Errorf("%q is a Plan file name", n)
		}
	}
	for _, n := range []string{"in26.xlsx", "SOP_Sell_In_Jan_2026.xlsx", "plan 10 aswak 2026.xlsx", "Sell_In_2026.xlsx", ""} {
		if domain.IsSellInPlanName(n) {
			t.Errorf("%q is not a Plan file name", n)
		}
	}
}

func TestPlanMarkerBySheetNameStampsRows(t *testing.T) {
	rows := [][]string{planTestHeader, planTestRow("311350147"), planTestRow("311350148")}
	plan := buildMultiSheetXLSX(t, []string{"Sell_In_Plan_2026"}, map[string][][]string{"Sell_In_Plan_2026": rows})
	real := buildMultiSheetXLSX(t, []string{"Sheet1"}, map[string][][]string{"Sheet1": rows})

	if firstSheetName(plan) != "Sell_In_Plan_2026" {
		t.Fatalf("first sheet name, got %q", firstSheetName(plan))
	}
	if !IsSellInPlanWorkbookSource("upload.xlsx", plan) || IsSellInPlanWorkbookSource("upload.xlsx", real) {
		t.Fatal("only the workbook whose first sheet is Sell_In_Plan is a Plan")
	}

	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "upload.xlsx", plan, "fathalla")
	if err != nil || len(recs) != 2 {
		t.Fatalf("plan workbook should parse to 2 rows: %v rows=%d", err, len(recs))
	}
	if !rep.PlanSource {
		t.Fatal("report must flag the Plan source")
	}
	for i, r := range recs {
		if r.SourceKind != domain.SellInSourceKindPlan || !r.IsSellInPlan() {
			t.Errorf("row %d must be stamped as a Plan row", i)
		}
	}

	recs, rep, err = ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.xlsx", real, "fathalla")
	if err != nil || len(recs) != 2 || rep.PlanSource {
		t.Fatalf("real workbook: err=%v rows=%d plan=%v", err, len(recs), rep.PlanSource)
	}
	for i, r := range recs {
		if r.SourceKind != "" || r.IsSellInPlan() {
			t.Errorf("row %d of a real Sell-In file must not be a Plan row", i)
		}
	}
}

func TestPlanMarkerByFileNameStampsCSV(t *testing.T) {
	var b strings.Builder
	b.WriteString(strings.Join(planTestHeader, ",") + "\n" + strings.Join(planTestRow("311350147"), ",") + "\n")
	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "Adco_Fathalla_Sell_In_Plan_2026_Clean.csv", []byte(b.String()), "fathalla")
	if err != nil || len(recs) != 1 || !rep.PlanSource || recs[0].SourceKind != domain.SellInSourceKindPlan {
		t.Fatalf("err=%v rows=%d plan=%v", err, len(recs), rep.PlanSource)
	}
}

func TestSellInNoBranchPlaceholder(t *testing.T) {
	for _, s := range []string{SellInNoBranchPlaceholder, " مجمع الاقليم (regional) ", "مجمع الإقليم"} {
		if !IsSellInNoBranchPlaceholder(s) {
			t.Errorf("%q is the no-branch placeholder", s)
		}
	}
	for _, s := range []string{"311350147", "fat_smouha", "مجمع"} {
		if IsSellInNoBranchPlaceholder(s) {
			t.Errorf("%q is a branch", s)
		}
	}
}

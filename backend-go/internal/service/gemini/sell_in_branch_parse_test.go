package gemini

import (
	"strings"
	"testing"
)

// rawPlanHeader is the raw ERP «plan 10 aswak» header (region in "branch", store columns after customer).
var rawPlanHeader = []string{"branch", "sector", "sub- sector", "7", "6", "5", "item 1", "item 2", "item 5", "item 3", "item 4",
	"\\", "month", "net Q", "net V", "Ton", "city", "customer", "customer branch", "exp city", "10", "Promotion",
	"officer", "officer mgr", "t.o", "Year", "Q EXP", "V EXP"}

func rawPlanCSV(rows ...[]string) []byte {
	var b strings.Builder
	b.WriteString(strings.Join(rawPlanHeader, ",") + "\n")
	for _, r := range rows {
		b.WriteString(strings.Join(r, ",") + "\n")
	}
	return []byte(b.String())
}

func rawPlanRow(region, city, customer, branchName, branchCode, item string) []string {
	return []string{region, "MT", "KA", "Detergents", "ALX-08940", "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه - Parent",
		item, item + " عادي", "إضافات", "رابيدو", "رابيدو", "Full Month", "مارس", "2", "250.5", "0.01", city, customer,
		branchName, branchCode, "محمود محمد طه", "عادي", "اشرف احمد عبد السلام صفى الدين", "ملاك مجدى عزيز عبده", "250.5", "2026", "2", "250.5"}
}

// Every raw-plan row keeps its own branch (branch code, branch name column, or the «<customer> - <branch>»
// customer cell). A row that truly names none stays empty — never the «مجمع الإقليم (Regional)» bucket.
func TestRawPlanRowsKeepTheirBranch(t *testing.T) {
	legal := "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م"
	raw := rawPlanCSV(
		rawPlanRow("ALX", "الاسكندرية", legal, "", "311350147", "ووش آند واكس رابيدو 330 مل"),
		rawPlanRow("ALX", "الاسكندرية", legal, "فرع فتح الله - ستانلى", "", "منظف رشاش بنزين رابيدو"),
		rawPlanRow("TNT", "الغربية", "عائله فتح الله ماركت - طنطا", "", "", "مياة بطارية 1 لتر"),
		rawPlanRow("BHR", "البحيرة", legal, "", "", "ووش آند واكس رابيدو 330 مل"),
		rawPlanRow("ALX", "الاسكندرية", legal, "", SellInNoBranchPlaceholder, "منظف رشاش بنزين رابيدو"),
	)
	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "plan 10 aswak 2026.csv", raw, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if rep.Layout != "raw_plan" || len(recs) != 5 {
		t.Fatalf("raw plan with 5 rows, got layout=%q rows=%d", rep.Layout, len(recs))
	}
	want := []string{"311350147", "fat_stanley", "fat_tanta", "", ""}
	for i, w := range want {
		if got := recs[i].CustomerBranchCode; got != w {
			t.Errorf("row %d: customer branch code = %q, want %q", i+1, got, w)
		}
		if recs[i].CustomerBranchCode == SellInNoBranchPlaceholder {
			t.Errorf("row %d: the Regional placeholder must never be written", i+1)
		}
	}
	if recs[0].CustomerName != legal || recs[0].RegionCode != "ALX" || recs[0].MonthNum != 3 || recs[0].Year != 2026 {
		t.Fatalf("other columns unchanged: %+v", recs[0])
	}
	if rep.NoBranchRows != 2 {
		t.Fatalf("2 rows name no branch, got %d", rep.NoBranchRows)
	}
}

func TestRawPlanBranchColumnHeaders(t *testing.T) {
	cols, missing := buildRawPlanHeaderMap(rawPlanHeader)
	if len(missing) != 0 {
		t.Fatalf("missing %v", missing)
	}
	if cols["region"] != 0 || cols["branch_name"] != 18 || cols["branch_code"] != 19 || cols["customer"] != 17 {
		t.Fatalf("region=branch(0), customer=17, branch name=18, branch code=19; got %v", cols)
	}
	for _, h := range []string{"Ship To Name", "اسم الفرع", "Store Name"} {
		c, _ := buildRawPlanHeaderMap([]string{"customer", h, "item 1", "month", "net Q", "net V"})
		if c["branch_name"] != 1 {
			t.Errorf("%q must map to the branch name column, got %v", h, c)
		}
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

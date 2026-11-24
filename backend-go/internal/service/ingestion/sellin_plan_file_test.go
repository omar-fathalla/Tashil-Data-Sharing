package ingestion

import (
	"context"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

var planFileHeader = []string{"branch", "sector", "sub- sector", "7", "6", "5", "item 1", "item 2", "item 5", "item 3", "item 4",
	"\\", "month", "net Q", "net V", "Ton", "city", "customer", "customer branch", "exp city", "10", "Promotion",
	"officer", "officer mgr", "t.o", "Year", "Q EXP", "V EXP"}

func planFileCSV(branchCode string) []byte {
	row := []string{"ALX", "MT", "KA", "Detergents", "ALX-08940", "Fathalla Market - Parent",
		"item-1", "item-1 normal", "extras", "Rapido", "Rapido", "Full Month", "March", "2", "250.5", "0.01", "Alexandria",
		"Fathalla Market", "Smouha", branchCode, "10", "Normal", "rep", "mgr", "250.5", "2026", "2", "250.5"}
	return []byte(strings.Join(planFileHeader, ",") + "\n" + strings.Join(row, ",") + "\n")
}

// The Plan workbook is read, archived and reported, but its rows go to the Plan store only: Sell-In
// totals and achievement never see them. The same rows in a real Sell-In file stay Sell-In.
func TestProcessSellInPlanKeepsPlanRowsOutOfSellIn(t *testing.T) {
	ctx := context.Background()
	p, bq := newInstance(t, &sharedSellInTable{}, nil)

	res, err := p.ProcessSellInPlan(ctx, "tenant-adeco", "Adco_Fathalla_Sell_In_Plan_2026_Clean.csv", planFileCSV("311350147"), false, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("Plan rows must not enter the Sell-In store, got %d", n)
	}
	plan := bq.SellInPlanRecordsSnapshot("tenant-adeco")
	if len(plan) != 1 || plan[0].SourceKind != domain.SellInSourceKindPlan {
		t.Fatalf("Plan rows go to the Plan store (Brand Master source): %+v", plan)
	}
	found := false
	for _, w := range res.UploadWarnings {
		found = found || w.Code == "plan_file_not_sell_in"
	}
	if !found {
		t.Fatalf("the upload must say the file is a Plan, not Sell-In: %+v", res.UploadWarnings)
	}

	if _, err := p.ProcessSellInPlan(ctx, "tenant-adeco", "in26.csv", planFileCSV("311350147"), false, "fathalla"); err != nil {
		t.Fatal(err)
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 1 {
		t.Fatalf("a real Sell-In file's rows are Sell-In, got %d", n)
	}
	if n := len(bq.SellInPlanRecordsSnapshot("tenant-adeco")); n != 1 {
		t.Fatalf("the Plan rows stay as they were, got %d", n)
	}
}

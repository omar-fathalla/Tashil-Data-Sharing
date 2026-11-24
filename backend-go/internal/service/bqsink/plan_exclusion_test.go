package bqsink

import (
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// The plan is not Sell-In actuals: sell_in_records never receives Plan rows.
func TestSellInWritePlanSkipsPlanRows(t *testing.T) {
	now := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	rec := func(id, file, kind string) domain.SellInRecord {
		return domain.SellInRecord{RecordID: id, TenantID: "adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			SourceFilename: file, SourceKind: kind, NetQtyCases: 1, NetValueEGP: 10}
	}
	recs := []domain.SellInRecord{
		rec("real", "in26.xlsx", ""),
		rec("plan-by-name", "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", ""),
		rec("plan-by-stamp", "upload.xlsx", domain.SellInSourceKindPlan),
	}
	p := PlanSellIn(Meta{TenantID: "adeco", BatchID: "b1", ArchiveID: "a1", SourceFile: "in26.xlsx"}, recs, now)
	if p.N != 1 || len(p.Rows) != 1 {
		t.Fatalf("only the real Sell-In row is written, got N=%d rows=%d", p.N, len(p.Rows))
	}

	planUpload := PlanSellIn(Meta{TenantID: "adeco", BatchID: "b2", ArchiveID: "a2", SourceFile: "Sell_In_Plan_2026.xlsx"},
		[]domain.SellInRecord{rec("x", "", "")}, now)
	if planUpload.N != 0 {
		t.Fatalf("a Plan upload writes no Sell-In rows, got %d", planUpload.N)
	}
}

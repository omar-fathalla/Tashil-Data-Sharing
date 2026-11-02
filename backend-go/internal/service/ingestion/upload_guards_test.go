package ingestion

import (
	"context"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func interactive(ctx context.Context, g UploadGuards) context.Context {
	return WithUploadGuards(ctx, g)
}

func sellIn(y, m int, cust string, v float64) domain.SellInRecord {
	return domain.SellInRecord{TenantID: "tenant-adeco", RetailerChain: "fathalla", CustomerName: cust, Year: y, MonthNum: m, NetValueEGP: v, NetQtyCases: 1}
}

func TestSellInFormVsSheetPeriod(t *testing.T) {
	form := gemini.WithRequestedPeriodDate(context.Background(), "2026-05-01")
	multi := func() []domain.SellInRecord {
		return []domain.SellInRecord{sellIn(2026, 3, "a", 1), sellIn(2026, 4, "a", 2)}
	}

	// Interactive, sheet spans several months → conflict with breakdown, nothing applied.
	recs := multi()
	err := resolveSellInPeriod(interactive(form, UploadGuards{}), recs)
	c, ok := AsConfirmationRequired(err)
	if !ok || c.Kind != "period_conflict" || len(c.Breakdown) != 2 || c.FormPeriod != "2026-05" || len(c.Options) != 2 || !strings.Contains(c.MessageAR, "مفيش حاجة اتحفظت") {
		t.Fatalf("expected period conflict, got %#v", err)
	}
	if recs[0].MonthNum != 3 {
		t.Fatal("rows must not change before the user answers")
	}
	// Single month that differs from the form → conflict too.
	if _, ok := AsConfirmationRequired(resolveSellInPeriod(interactive(form, UploadGuards{}), []domain.SellInRecord{sellIn(2026, 4, "a", 1)})); !ok {
		t.Fatal("single different month must ask")
	}
	// Single month equal to the form → no question.
	if err := resolveSellInPeriod(interactive(form, UploadGuards{}), []domain.SellInRecord{sellIn(2026, 5, "a", 1)}); err != nil {
		t.Fatal(err)
	}
	// Answer "sheet" keeps the rows' months; "form" moves every row to the form month.
	recs = multi()
	if err := resolveSellInPeriod(interactive(form, UploadGuards{PeriodChoice: "sheet"}), recs); err != nil || recs[0].MonthNum != 3 || recs[1].MonthNum != 4 {
		t.Fatalf("sheet choice: %v %+v", err, recs)
	}
	recs = multi()
	if err := resolveSellInPeriod(interactive(form, UploadGuards{PeriodChoice: "form"}), recs); err != nil || recs[0].MonthNum != 5 || recs[1].MonthNum != 5 || recs[1].MonthAR != "مايو" {
		t.Fatalf("form choice: %v %+v", err, recs)
	}
	// Archive replay (non-interactive) never asks and keeps the old rule.
	recs = multi()
	if err := resolveSellInPeriod(form, recs); err != nil || recs[0].MonthNum != 3 {
		t.Fatal("replay must not ask or rewrite multi-month files")
	}
}

func TestSellOutPeriodChoice(t *testing.T) {
	sheet := []MonthSlice{{Period: "2026-03", Rows: 3}, {Period: "2026-04", Rows: 2}}
	ctx := interactive(context.Background(), UploadGuards{})
	if _, err := sellOutPeriodChoice(ctx, "2026-05-01", sheet); err == nil {
		t.Fatal("multi-month sheet vs form must ask")
	}
	if ch, err := sellOutPeriodChoice(ctx, "2026-05-01", nil); err != nil || ch != "" {
		t.Fatal("no per-row dates → form period applies without asking")
	}
	if ch, _ := sellOutPeriodChoice(interactive(context.Background(), UploadGuards{PeriodChoice: "sheet"}), "2026-05-01", sheet); ch != "sheet" {
		t.Fatal("sheet answer")
	}
	if ch, err := sellOutPeriodChoice(context.Background(), "2026-05-01", sheet); err != nil || ch != "" {
		t.Fatal("replay keeps old behaviour")
	}
	if c := chainRequiredError("carrefour"); c.Kind != "chain_required" || len(c.Options) != 1 || !strings.Contains(c.MessageAR, "اقتراح") {
		t.Fatalf("AI chain is a suggestion only: %+v", c)
	}
}

func TestSellInPartialMonthNeedsConfirmation(t *testing.T) {
	ctx := context.Background()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	var old []domain.SellInRecord
	for i := 0; i < 40; i++ {
		old = append(old, sellIn(2026, 3, "عائله فتح الله ماركت - طنطا", 100))
	}
	old = append(old, sellIn(2026, 4, "عائله فتح الله ماركت - طنطا", 100))
	if err := bq.SetSellInRecords(ctx, "tenant-adeco", "plan.xlsx", old); err != nil {
		t.Fatal(err)
	}
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true))
	small := []domain.SellInRecord{sellIn(2026, 3, "عائله فتح الله ماركت - طنطا", 100), sellIn(2026, 3, "عائله فتح الله ماركت - طنطا", 100)}
	err := p.checkSellInPartialMonth(interactive(ctx, UploadGuards{}), "tenant-adeco", "other.xlsx", small)
	c, ok := AsConfirmationRequired(err)
	if !ok || c.Kind != "partial_month" || c.Param != "replace_confirmed" || len(c.Breakdown) != 1 || c.Breakdown[0].ExistingRows != 40 {
		t.Fatalf("expected partial_month, got %#v", err)
	}
	if err := p.checkSellInPartialMonth(interactive(ctx, UploadGuards{ReplaceConfirmed: true}), "tenant-adeco", "other.xlsx", small); err != nil {
		t.Fatal("confirmed replace must pass")
	}
	if err := p.checkSellInPartialMonth(ctx, "tenant-adeco", "other.xlsx", small); err != nil {
		t.Fatal("replay must not ask")
	}
	// A month below minExistingRows is too small to judge.
	if err := p.checkSellInPartialMonth(interactive(ctx, UploadGuards{}), "tenant-adeco", "other.xlsx", []domain.SellInRecord{sellIn(2026, 4, "عائله فتح الله ماركت - طنطا", 1)}); err != nil {
		t.Fatalf("small month: %v", err)
	}
}

var sopHeader = []string{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", "Extended Price", "Branch"}

func sopWorkbook(t *testing.T, rows ...[]string) []byte {
	t.Helper()
	x, err := gemini.BuildSampleXLSX(append([][]string{sopHeader}, rows...))
	if err != nil {
		t.Fatal(err)
	}
	return x
}

// End to end: an unknown customer's rows are held out of the stored records and reported.
func TestProcessSellInQuarantinesUnknownCustomer(t *testing.T) {
	ctx := context.Background()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	reg := customers.New(&customers.MemoryStore{})
	p.SetCustomerRegistry(reg)
	x := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-03-02", "FG-1", "صنف", "CTN", "2", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "100", "ALX"},
		[]string{"Invoice", "2", "2026-03-03", "FG-1", "صنف", "CTN", "1", "L", "C2", "QA عميل تجريبي", "KA", "70", "ALX"},
	)
	res, err := p.ProcessSellInPlan(interactive(ctx, UploadGuards{}), "tenant-adeco", "in26.xlsx", x, false, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(res.QuarantinedCustomers) != 1 || res.QuarantinedCustomers[0].Value != 70 {
		t.Fatalf("quarantine report: %+v", res.QuarantinedCustomers)
	}
	var total float64
	for _, r := range bq.SellInRecordsSnapshot("tenant-adeco") {
		total += r.NetValueEGP
		if strings.Contains(r.CustomerName, "QA") {
			t.Fatal("quarantined rows must not be stored in totals")
		}
	}
	if total != 100 {
		t.Fatalf("stored total %v want 100", total)
	}
	if pend := reg.List(ctx, "tenant-adeco", customers.StatusPending, false); len(pend) != 1 || pend[0].FirstSeenFile != "in26.xlsx" {
		t.Fatalf("pending: %+v", pend)
	}
	// Approve + re-apply the archived file: rows join the totals without a re-upload.
	if _, err := reg.Decide(ctx, "tenant-adeco", res.QuarantinedCustomers[0].Name, customers.StatusApproved, "", "", "t"); err != nil {
		t.Fatal(err)
	}
	applied, errs := p.ReapplySellInFiles(ctx, "tenant-adeco", []string{"in26.xlsx"})
	if len(applied) != 1 || len(errs) != 0 {
		t.Fatalf("reapply: %v %v", applied, errs)
	}
	total = 0
	for _, r := range bq.SellInRecordsSnapshot("tenant-adeco") {
		total += r.NetValueEGP
	}
	if total != 170 {
		t.Fatalf("after approval total %v want 170", total)
	}
}

func TestProcessSellInRejectsUnparseableMonth(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	x := sopWorkbook(t, []string{"Invoice", "1", "not a date", "FG-1", "صنف", "CTN", "2", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "100", "ALX"})
	if _, err := p.ProcessSellInPlan(context.Background(), "tenant-adeco", "plan.xlsx", x, false, "fathalla"); err == nil || !strings.Contains(err.Error(), "اترفض") {
		t.Fatalf("expected Arabic rejection, got %v", err)
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("nothing may be stored, got %d", n)
	}
}

package ingestion

import (
	"context"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

type fixEnv struct {
	t   *testing.T
	p   *Processor
	bq  *bigquery.Client
	reg *customers.Registry
	ten string
}

const fixTenant = "tenant-livetest"

func newFixEnv(t *testing.T) *fixEnv {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	reg := customers.New(&customers.MemoryStore{})
	p.SetCustomerRegistry(reg)
	return &fixEnv{t: t, p: p, bq: bq, reg: reg, ten: fixTenant}
}

func livetestBytes(t *testing.T, name string) []byte {
	b, err := os.ReadFile(filepath.Join("testdata", "livetest", name))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func (e *fixEnv) upload(name string, raw []byte, chain string, g UploadGuards) (*IngestionResult, error) {
	if raw == nil {
		raw = livetestBytes(e.t, name)
	}
	return e.p.ProcessSellInPlan(interactive(context.Background(), g), e.ten, name, raw, false, chain)
}

func (e *fixEnv) total(chain, month string) (float64, int) {
	v, n := 0.0, 0
	for _, r := range e.bq.SellInRecordsSnapshot(e.ten) {
		if chain != "" && bigquery.ResolveSellInChain(r.CustomerName, r.RetailerChain) != chain {
			continue
		}
		if month != "" && r.Year*100+r.MonthNum != atoiMonth(month) {
			continue
		}
		v += r.NetValueEGP
		n++
	}
	return math.Round(v*100) / 100, n
}

func atoiMonth(m string) int { // "2026-07" -> 202607
	y, mm := 0, 0
	for _, c := range m[:4] {
		y = y*10 + int(c-'0')
	}
	for _, c := range m[5:7] {
		mm = mm*10 + int(c-'0')
	}
	return y*100 + mm
}

func (e *fixEnv) approve(name, chain string) {
	if _, err := e.reg.Decide(context.Background(), e.ten, name, customers.StatusApproved, chain, "", "test"); err != nil {
		e.t.Fatal(err)
	}
}

// Items 1 + 2: file 08 is saved (no 422) with its unknown customer held out; approving it and
// re-applying for qa_test only adds the 77 EGP, logging the file and its new batch.
func TestLivetestApproveReleasesQuarantine(t *testing.T) {
	e := newFixEnv(t)
	res, err := e.upload("08_unknown_customer.xlsx", nil, "qa_test", UploadGuards{})
	if err != nil {
		t.Fatalf("all-quarantined file must be saved, got %v", err)
	}
	if v, _ := e.total("qa_test", ""); v != 0 {
		t.Fatalf("quarantined rows counted: %v", v)
	}
	if len(res.QuarantinedCustomers) != 1 || res.QuarantinedCustomers[0].Value != 77 {
		t.Fatalf("quarantine: %+v", res.QuarantinedCustomers)
	}
	e.approve(res.QuarantinedCustomers[0].Name, "qa_test")
	applied, errs := e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"08_unknown_customer.xlsx"}, []string{"qa_test"})
	if len(errs) != 0 || len(applied) != 1 || applied[0].File != "08_unknown_customer.xlsx" || applied[0].BatchID == "" || applied[0].BatchID == res.BatchID {
		t.Fatalf("reapply: %+v %v", applied, errs)
	}
	if v, _ := e.total("qa_test", ""); v != 77 {
		t.Fatalf("after approval %v want 77", v)
	}
}

// Item 2 (mixed file): 14 has two pending customers (10 + 20). Approving one counts only its rows;
// the other stays quarantined and uncounted.
func TestLivetestMixedFileApproveOne(t *testing.T) {
	e := newFixEnv(t)
	res, err := e.upload("14_two_fathalla_cities.xlsx", nil, "qa_test", UploadGuards{})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.QuarantinedCustomers) != 2 {
		t.Fatalf("want 2 pending customers, got %+v", res.QuarantinedCustomers)
	}
	var tanta customers.QuarantinedCustomer
	for _, q := range res.QuarantinedCustomers {
		if strings.Contains(q.Name, "طنطا") {
			tanta = q
		}
	}
	if tanta.Value != 20 {
		t.Fatalf("tanta: %+v", res.QuarantinedCustomers)
	}
	e.approve(tanta.Name, "qa_test")
	if _, errs := e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"14_two_fathalla_cities.xlsx"}, []string{"qa_test"}); len(errs) != 0 {
		t.Fatal(errs)
	}
	if v, n := e.total("qa_test", ""); v != 20 {
		t.Fatalf("mixed file: counted %v (%d rows), want 20 (الغردقة stays quarantined)", v, n)
	}
}

// Item 3: 05a's rows are all quarantined, yet 05b (smaller, same chain+month) still asks to
// confirm; confirming marks 05a's month superseded (by/at, nothing deleted), and after approval the
// month is 100 (05b), never 3,100.
func TestLivetestPartialMonthQuarantined(t *testing.T) {
	e := newFixEnv(t)
	if _, err := e.upload("05a_full_month.xlsx", nil, "qa_test", UploadGuards{}); err != nil {
		t.Fatal(err)
	}
	_, err := e.upload("05b_partial_month.xlsx", nil, "qa_test", UploadGuards{})
	if c, ok := AsConfirmationRequired(err); !ok || c.Kind != "partial_month" {
		t.Fatalf("05b must ask partial_month, got %v", err)
	}
	res, err := e.upload("05b_partial_month.xlsx", nil, "qa_test", UploadGuards{ReplaceConfirmed: true})
	if err != nil {
		t.Fatal(err)
	}
	var superseded bool
	for _, en := range e.reg.List(context.Background(), e.ten, "", false) {
		for _, f := range en.Quarantine {
			if f.File == "05a_full_month.xlsx" {
				if len(f.Superseded) == 0 || f.Superseded[0].By != "05b_partial_month.xlsx" || f.Superseded[0].At.IsZero() || f.Live() {
					t.Fatalf("05a not marked superseded: %+v", f)
				}
				superseded = true
			}
		}
	}
	if !superseded {
		t.Fatalf("05a quarantine stat missing (must be kept, only marked)")
	}
	e.approve(res.QuarantinedCustomers[0].Name, "qa_test")
	if _, errs := e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"05b_partial_month.xlsx"}, []string{"qa_test"}); len(errs) != 0 {
		t.Fatal(errs)
	}
	if v, _ := e.total("qa_test", "2026-07"); v != 100 {
		t.Fatalf("July = %v, want 100", v)
	}
}

// Item 6: the unknown-item warning is reported even when the rows are quarantined.
func TestLivetestUnknownBarcodeReported(t *testing.T) {
	e := newFixEnv(t)
	res, err := e.upload("12_unknown_barcode.xlsx", nil, "qa_test", UploadGuards{})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.UnknownBarcodes) == 0 {
		t.Fatalf("no unknown-barcode warning for 12")
	}
}

// Item 10/07: a fully quarantined 2027 file adds no year; after approve + reapply 2027 appears.
func TestLivetestYear2027AfterApproval(t *testing.T) {
	e := newFixEnv(t)
	res, err := e.upload("07_year_2027.xlsx", nil, "qa_test", UploadGuards{})
	if err != nil {
		t.Fatal(err)
	}
	has := func() bool {
		for _, y := range e.p.SellInYears(e.ten) {
			if y == 2027 {
				return true
			}
		}
		return false
	}
	if has() {
		t.Fatalf("2027 shown with no counted rows")
	}
	e.approve(res.QuarantinedCustomers[0].Name, "qa_test")
	if _, errs := e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"07_year_2027.xlsx"}, []string{"qa_test"}); len(errs) != 0 {
		t.Fatal(errs)
	}
	if !has() {
		t.Fatalf("2027 missing after approval: %v", e.p.SellInYears(e.ten))
	}
}

// Item 8c: saving the same bytes again (replay / reapply) keeps uploaded_at.
func TestArchiveKeepsUploadedAtOnReplay(t *testing.T) {
	e := newFixEnv(t)
	raw := livetestBytes(t, "05a_full_month.xlsx")
	a := e.p.SaveArchivedFile(e.ten, "b1", "05a_full_month.xlsx", raw, "qa_test", "2026", "07", 30, 1, 3000)
	first := a.UploadedAt
	b := e.p.SaveArchivedFile(e.ten, "b2", "05a_full_month.xlsx", raw, "qa_test", "2026", "07", 30, 1, 3000)
	if b.UploadedAt != first || b.ID != a.ID {
		t.Fatalf("uploaded_at changed on identical replay: %v -> %v", first, b.UploadedAt)
	}
}

// Reviewer case: confirming a customer for Fathalla re-runs only the fathalla rows; another chain's
// rows from the same month are untouched, and a month owned by a later file is never wiped.
func TestFathallaConfirmationScopedToChain(t *testing.T) {
	e := newFixEnv(t)
	e.ten = "tenant-adeco" // the approved Fathalla customer seed applies to Adeco
	fileA := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-03-02", "FG-1", "صنف", "CTN", "2", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "100", "ALX"},
		[]string{"Invoice", "2", "2026-03-03", "FG-1", "صنف", "CTN", "1", "L", "C2", "QA عميل فتح الله جديد", "KA", "70", "ALX"},
	)
	fileB := sopWorkbook(t,
		[]string{"Invoice", "3", "2026-03-04", "FG-1", "صنف", "CTN", "1", "L", "C3", "QA عميل سلسلة تانية", "KA", "50", "ALX"},
	)
	if _, err := e.upload("fat_a.xlsx", fileA, "fathalla", UploadGuards{}); err != nil {
		t.Fatal(err)
	}
	resB, err := e.upload("qa_b.xlsx", fileB, "qa_test", UploadGuards{})
	if err != nil {
		t.Fatal(err)
	}
	e.approve(resB.QuarantinedCustomers[0].Name, "qa_test")
	if _, errs := e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"qa_b.xlsx"}, []string{"qa_test"}); len(errs) != 0 {
		t.Fatal(errs)
	}
	qaBefore, qaRows := e.total("qa_test", "")
	if v, _ := e.total("fathalla", ""); v != 100 {
		t.Fatalf("fathalla before %v", v)
	}
	e.approve("QA عميل فتح الله جديد", "fathalla")
	applied, errs := e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"fat_a.xlsx"}, []string{"fathalla"})
	if len(errs) != 0 || len(applied) == 0 || applied[0].File != "fat_a.xlsx" || applied[0].Rows != 2 {
		t.Fatalf("reapply: %+v %v", applied, errs)
	}
	for _, a := range applied[1:] {
		if a.Rows != 0 { // a later overlapping file of another chain contributes no fathalla rows
			t.Fatalf("non-fathalla rows re-run: %+v", a)
		}
	}
	if v, _ := e.total("fathalla", ""); v != 170 {
		t.Fatalf("fathalla after confirmation %v want 170", v)
	}
	if v, n := e.total("qa_test", ""); v != qaBefore || n != qaRows {
		t.Fatalf("other chain changed: %v/%d -> %v/%d", qaBefore, qaRows, v, n)
	}

	// A later Fathalla file replaces March (confirmed). Re-applying the older file must not wipe it.
	fileC := sopWorkbook(t, []string{"Invoice", "9", "2026-03-09", "FG-1", "صنف", "CTN", "3", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "300", "ALX"},
		[]string{"Invoice", "10", "2026-03-10", "FG-1", "صنف", "CTN", "3", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "1", "ALX"})
	if _, err := e.upload("fat_c.xlsx", fileC, "fathalla", UploadGuards{ReplaceConfirmed: true}); err != nil {
		t.Fatal(err)
	}
	_, _ = e.p.ReapplySellInFiles(context.Background(), e.ten, []string{"fat_a.xlsx"}, []string{"fathalla"})
	if v, _ := e.total("fathalla", "2026-03"); v != 301 {
		t.Fatalf("March after re-applying the older file = %v, want 301 (fat_c)", v)
	}
	if v, n := e.total("qa_test", ""); v != qaBefore || n != qaRows {
		t.Fatalf("other chain changed after replacement")
	}
}

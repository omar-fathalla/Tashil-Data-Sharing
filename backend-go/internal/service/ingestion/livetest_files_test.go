package ingestion

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// The synthetic QA workbooks from the live test (testdata/livetest, built by build.py, see PLAN.md)
// run through the real Sell-In / Sell-Out entry points in dry-run mode with in-memory repositories.
// No client data: every customer and item starts with "QA".
func TestLivetestFilesMatchPlan(t *testing.T) {
	type want struct {
		reject string   // substring of the rejection; "" means accepted
		months []string // sorted "YYYY-MM" of the accepted rows
		value  float64
	}
	plan := map[string]want{
		"01_month_formats.xlsx":         {months: []string{"2026-01", "2026-02", "2026-03", "2026-04", "2026-05", "2026-06"}, value: 600},
		"02_bad_month.xlsx":             {reject: "شهر"},
		"03_empty_year.xlsx":            {reject: "سن"},
		"04_empty_year_qa_2026.xlsx":    {months: []string{"2026-03"}, value: 100},
		"05a_full_month.xlsx":           {months: []string{"2026-07"}, value: 3000},
		"05b_partial_month.xlsx":        {months: []string{"2026-07"}, value: 100},
		"06_form_vs_sheet.xlsx":         {months: []string{"2026-08", "2026-09"}, value: 200},
		"07_year_2027.xlsx":             {months: []string{"2027-01"}, value: 100},
		"08_unknown_customer.xlsx":      {months: []string{"2026-10"}, value: 77},
		"09_reordered_columns.xlsx":     {months: []string{"2026-03"}, value: 100},
		"10_missing_value_column.xlsx":  {reject: "Extended Price"},
		"11_formula_cells.xlsx":         {reject: "احفظه"},
		"12_unknown_barcode.xlsx":       {months: []string{"2026-10"}, value: 55},
		"13_fuzzy_near_match.xlsx":      {months: []string{"2026-10"}, value: 33},
		"14_two_fathalla_cities.xlsx":   {months: []string{"2026-10"}, value: 30},
		"15_sellout_form_vs_sheet.xlsx": {months: []string{"2026-08", "2026-09"}},
	}
	files, _ := filepath.Glob("testdata/livetest/*.xlsx")
	if len(files) != len(plan) {
		t.Fatalf("expected %d live-test files, found %d", len(plan), len(files))
	}
	for _, f := range files {
		name := filepath.Base(f)
		w, ok := plan[name]
		if !ok {
			t.Errorf("%s: not in PLAN.md", name)
			continue
		}
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(f)
			if err != nil {
				t.Fatal(err)
			}
			p := newTestProcessor(t, t.TempDir())
			// Interactive, like an upload from the UI (no replay).
			ctx := interactive(context.Background(), UploadGuards{})
			var res *IngestionResult
			if strings.HasPrefix(name, "15_") {
				res, err = p.ProcessUploadWithDryRun(ctx, "tenant-livetest", name, raw, true, "qa_test")
			} else {
				res, err = p.ProcessSellInPlan(ctx, "tenant-livetest", name, raw, true, "qa_test")
			}
			if w.reject != "" {
				if err == nil {
					t.Fatalf("expected rejection containing %q, got accepted", w.reject)
				}
				if !strings.Contains(err.Error(), w.reject) {
					t.Fatalf("rejection %q does not mention %q", err, w.reject)
				}
				return
			}
			if err != nil {
				t.Fatalf("expected accepted, got %v", err)
			}
			seen := map[string]bool{}
			total := 0.0
			p.stagedMu.Lock()
			st := p.staged[res.BatchID]
			p.stagedMu.Unlock()
			if st == nil {
				t.Fatalf("nothing staged for batch %q", res.BatchID)
			}
			if strings.HasPrefix(name, "15_") {
				for _, r := range st.ValidNormalizedRecords {
					if len(r.TransactionDate) >= 7 {
						seen[r.TransactionDate[:7]] = true
					}
				}
			} else {
				for _, r := range st.SellInRecords {
					if r.RetailerChain != "qa_test" {
						t.Fatalf("row attributed to %q, want qa_test", r.RetailerChain)
					}
					seen[fmt.Sprintf("%04d-%02d", r.Year, r.MonthNum)] = true
					total += r.NetValueEGP
				}
			}
			var got []string
			for m := range seen {
				got = append(got, m)
			}
			sort.Strings(got)
			if strings.Join(got, ",") != strings.Join(w.months, ",") {
				t.Fatalf("months %v, want %v", got, w.months)
			}
			if w.value != 0 && (total < w.value-0.001 || total > w.value+0.001) {
				t.Fatalf("value %.2f, want %.2f", total, w.value)
			}
		})
	}
}

// TOP RULE: an interactive Sell-In upload without an explicit chain is refused (no fathalla default).
func TestSellInUploadRequiresExplicitChain(t *testing.T) {
	raw, err := os.ReadFile("testdata/livetest/01_month_formats.xlsx")
	if err != nil {
		t.Fatal(err)
	}
	p := newTestProcessor(t, t.TempDir())
	ctx := interactive(context.Background(), UploadGuards{})
	for _, chain := range []string{"", "all", "الكل", "  "} {
		if err := p.PrecheckSellIn(ctx, "tenant-livetest", "01_month_formats.xlsx", raw, chain); err == nil {
			t.Fatalf("precheck with chain %q must be refused", chain)
		}
		_, err := p.ProcessSellInPlan(ctx, "tenant-livetest", "01_month_formats.xlsx", raw, true, chain)
		c, ok := AsConfirmationRequired(err)
		if !ok || c.Kind != "chain_required" || len(c.Options) != 0 {
			t.Fatalf("chain %q: want chain_required with no suggested chain, got %v", chain, err)
		}
	}
	if _, err := p.ProcessSellInPlan(ctx, "tenant-livetest", "01_month_formats.xlsx", raw, true, "qa_test"); err != nil {
		t.Fatalf("explicit chain must be accepted: %v", err)
	}
}

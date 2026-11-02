package gemini

import (
	"archive/zip"
	"bytes"
	"errors"
	"strings"
	"testing"
)

func TestParseMonthTokenFormats(t *testing.T) {
	cases := map[string][2]int{ // raw -> {month, year}
		"January": {1, 0}, "jan": {1, 0}, "Sept": {9, 0}, "SEP": {9, 0},
		"يناير": {1, 0}, "فبراير": {2, 0}, "أغسطس": {8, 0}, "اغسطس": {8, 0},
		"كانون الثاني": {1, 0}, "شباط": {2, 0}, "آذار": {3, 0}, "تشرين الأول": {10, 0}, // Levantine
		"جانفي": {1, 0}, "فيفري": {2, 0}, "ماي": {5, 0}, "جويلية": {7, 0}, "أوت": {8, 0}, // Maghrebi
		"3": {3, 0}, "03": {3, 0}, "١٢": {12, 0}, "7.0": {7, 0},
		"2026-03": {3, 2026}, "2025/11": {11, 2025}, "2026-03-15": {3, 2026}, "15/04/2026": {4, 2026},
		"46082":  {3, 2026}, // Excel serial 2026-03-01
		"Jan-26": {1, 2026}, "يناير 2026": {1, 2026},
	}
	for raw, want := range cases {
		m, y, ok := ParseMonthToken(raw)
		if !ok || m != want[0] || y != want[1] {
			t.Errorf("ParseMonthToken(%q) = %d,%d,%v want %v", raw, m, y, ok, want)
		}
	}
	for _, bad := range []string{"", "#N/A", "13", "0", "Q1", "شهر", "abc", "2026-13"} {
		if m, _, ok := ParseMonthToken(bad); ok {
			t.Errorf("ParseMonthToken(%q) must be rejected, got month %d (no January default)", bad, m)
		}
	}
}

func TestYearTokensAndFilename(t *testing.T) {
	if y, ok := ParseYearToken("2027"); !ok || y != 2027 {
		t.Fatal("2027 must be accepted")
	}
	if y, ok := ParseYearToken("٢٠٢٦"); !ok || y != 2026 {
		t.Fatal("Arabic digits")
	}
	for _, bad := range []string{"", "26", "1999", "abc", "2026.5"} {
		if _, ok := ParseYearToken(bad); ok {
			t.Errorf("ParseYearToken(%q) must fail", bad)
		}
	}
	good := map[string]int{"in26.xlsx": 2026, "Sell_In_2025.xlsx": 2025, "plan 2027 final.xlsx": 2027}
	for f, want := range good {
		if y, ok := YearFromFilename(f); !ok || y != want {
			t.Errorf("YearFromFilename(%q) = %d,%v want %d", f, y, ok, want)
		}
	}
	for _, f := range []string{"plan.xlsx", "compare 2025 vs 2026.xlsx"} {
		if y, ok := YearFromFilename(f); ok {
			t.Errorf("YearFromFilename(%q) ambiguous/absent must fail, got %d", f, y)
		}
	}
}

func TestPeriodResolverNeverDefaults(t *testing.T) {
	p := newSellInPeriodResolver(0)
	p.startRow()
	if _, _, ok := p.resolve(2, "", "", "March", ""); ok || p.accept(2) {
		t.Fatal("month without any year must be rejected (no 2026 default)")
	}
	p.startRow()
	if _, _, ok := p.resolve(3, "2026", "", "xyz", ""); ok || p.accept(3) {
		t.Fatal("unparseable month must be rejected (no January default)")
	}
	p.startRow()
	if _, _, ok := p.resolve(4, "2026", "4", "May", ""); ok || p.accept(4) {
		t.Fatal("month number vs name conflict must be rejected")
	}
	p.startRow()
	if y, m, ok := p.resolve(5, "", "", "", "2027-02-10"); !ok || y != 2027 || m != 2 || !p.accept(5) {
		t.Fatal("year and month from the row date")
	}
	err := p.err("x.xlsx")
	var pe *SellInPeriodError
	if !errors.As(err, &pe) || pe.BadMonthRows != 1 || pe.NoYearRows != 1 || pe.ConflictRows != 1 {
		t.Fatalf("expected counted rejection, got %#v", err)
	}
	if !strings.Contains(err.Error(), "اترفض") {
		t.Fatal("Arabic rejection text expected")
	}
	f := newSellInPeriodResolver(2025) // year from an unambiguous filename only as a fallback
	f.startRow()
	if y, m, ok := f.resolve(2, "", "", "نوفمبر", ""); !ok || y != 2025 || m != 11 {
		t.Fatal("filename year fallback")
	}
}

func TestRawPlanHeaderMapReorderedAndMissing(t *testing.T) {
	header := []string{"Customer", "net V", "Item 1", "Year", "Month", "net Q"}
	idx, missing := buildRawPlanHeaderMap(header)
	if len(missing) != 0 || idx["customer"] != 0 || idx["net_v"] != 1 || idx["month"] != 4 || idx["net_q"] != 5 || idx["year"] != 3 {
		t.Fatalf("reordered headers must map by name: %v missing=%v", idx, missing)
	}
	_, missing = buildRawPlanHeaderMap([]string{"Customer", "Item 1", "Month", "net Q"})
	if len(missing) != 1 || missing[0] != "net V" {
		t.Fatalf("missing value column must be reported, got %v", missing)
	}
}

var sopHeader = []string{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", "Extended Price", "TO", "Net Q", "Branch"}

func sopRow(date, item, cust, qty, val string) []string {
	return []string{"Invoice", "INV1", date, item, "صنف تجريبي", "CTN", qty, "L1", "C1", cust, "KA", val, val, qty, "ALX"}
}

func TestGPSOPParserByHeaderNames(t *testing.T) {
	rows := [][]string{{"report"}, {""}, sopHeader,
		sopRow("2026-03-02", "FG-1", "QA عميل تجريبي", "2", "100"),
		sopRow("2026-03-09", "FG-2", "QA عميل تجريبي", "3", "50.5"),
	}
	// Same data, columns reversed: totals must not change.
	rev := make([][]string, len(rows))
	for i, r := range rows {
		c := append([]string(nil), r...)
		for a, b := 0, len(c)-1; a < b; a, b = a+1, b-1 {
			c[a], c[b] = c[b], c[a]
		}
		rev[i] = c
	}
	for name, data := range map[string][][]string{"in26.xlsx": rows, "in26_rev.xlsx": rev} {
		x := buildMultiSheetXLSX(t, []string{"Sheet1"}, map[string][][]string{"Sheet1": data})
		recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", name, x, "fathalla")
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		var v, q float64
		for _, r := range recs {
			v += r.NetValueEGP
			q += r.NetQtyCases
			if r.Year != 2026 || r.MonthNum != 3 {
				t.Fatalf("%s: period %d-%d", name, r.Year, r.MonthNum)
			}
		}
		if v != 150.5 || q != 5 || rep == nil || rep.Layout == "" {
			t.Fatalf("%s: value %v qty %v rep %+v", name, v, q, rep)
		}
	}
	// Changed layout (no Extended Price) is rejected, never guessed.
	bad := [][]string{{"SOP Type", "SOP Number", "Document Date", "Item Number", "QTY", "Customer Name"}, {"Invoice", "1", "2026-03-02", "FG", "1", "x"}}
	x := buildMultiSheetXLSX(t, []string{"Sheet1"}, map[string][][]string{"Sheet1": bad})
	_, _, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.xlsx", x, "fathalla")
	var le *SellInLayoutError
	if !errors.As(err, &le) {
		t.Fatalf("expected layout rejection, got %v", err)
	}
}

func TestUncachedFormulaCells(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create("xl/worksheets/sheet1.xml")
	_, _ = w.Write([]byte(`<worksheet><sheetData><row r="1"><c r="A1"><v>1</v></c><c r="B1"><f>A1*2</f><v>2</v></c><c r="C1"><f>A1*3</f></c><c r="D1"/></row></sheetData></worksheet>`))
	_ = zw.Close()
	rep := FindUncachedFormulaCells(buf.Bytes())
	if rep.Count != 1 || len(rep.Cells) != 1 || rep.Cells[0] != "sheet1!C1" {
		t.Fatalf("got %+v", rep)
	}
	if !strings.Contains(UncachedFormulaMessageAR(rep), "افتح الملف في إكسل واحفظه مرة تانية") {
		t.Fatal("Arabic re-save instruction expected")
	}
}

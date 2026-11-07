package preupload

import (
	"archive/zip"
	"bytes"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func TestCheckEmptyFile(t *testing.T) {
	rep := Check("empty.xlsx", nil, Options{})
	if rep.OK || !rep.WroteNothing || rep.Blocking < 1 {
		t.Fatalf("empty must block with wrote_nothing: %+v", rep)
	}
	if rep.Fixes[0].Code != CodeEmptyFile {
		t.Fatalf("code=%s", rep.Fixes[0].Code)
	}
	if !strings.Contains(rep.Fixes[0].MessageAR, "فاضي") {
		t.Fatalf("Arabic empty message: %s", rep.Fixes[0].MessageAR)
	}
}

func TestCheckMissingSellInColumn(t *testing.T) {
	// Raw plan missing net V → layout rejection with missing column fix.
	csv := []byte("Customer,Item 1,Month,Year,net Q\nQA,ItemA,3,2026,2\n")
	rep := Check("raw_plan.csv", csv, Options{TenantID: "tenant-adeco", Chain: "fathalla"})
	if rep.OK || rep.Kind != "sell_in" || !rep.WroteNothing {
		t.Fatalf("expected sell_in blocking report: %+v", rep)
	}
	found := false
	for _, f := range rep.Fixes {
		if f.Code == CodeMissingColumn {
			found = true
			if !strings.Contains(strings.ToLower(f.Column+f.MessageAR), "net") &&
				!strings.Contains(f.MessageAR, "عمود") {
				t.Fatalf("missing column Arabic fix: %+v", f)
			}
			if f.HowToFixAR == "" {
				t.Fatal("how_to_fix_ar required")
			}
		}
	}
	if !found {
		t.Fatalf("expected missing_column fix, got %+v", rep.Fixes)
	}
}

func TestCheckUnclearSellInMonth(t *testing.T) {
	csv := []byte("Customer,Item 1,Month,Year,net Q,net V\nQA Store,ItemA,مش-مفهوم,2026,2,100\n")
	rep := Check("months.csv", csv, Options{TenantID: "tenant-adeco", Chain: "fathalla"})
	if rep.OK || !rep.WroteNothing {
		t.Fatalf("unclear month must block: %+v", rep)
	}
	found := false
	for _, f := range rep.Fixes {
		if f.Code == CodeUnclearMonth {
			found = true
			if !strings.Contains(f.MessageAR, "شهر") && !strings.Contains(f.MessageAR, "اترفض") {
				t.Fatalf("Arabic unclear month: %s", f.MessageAR)
			}
		}
	}
	if !found {
		t.Fatalf("expected unclear_month, got %+v", rep.Fixes)
	}
}

func TestCheckUnreadableFormulaCells(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create("xl/worksheets/sheet1.xml")
	_, _ = w.Write([]byte(`<worksheet><sheetData><row r="1"><c r="A1"><v>1</v></c><c r="B1"><f>A1*3</f></c></row></sheetData></worksheet>`))
	_ = zw.Close()
	rep := Check("formulas.xlsx", buf.Bytes(), Options{})
	if rep.OK || !rep.WroteNothing {
		t.Fatalf("uncached formula must block: %+v", rep)
	}
	found := false
	for _, f := range rep.Fixes {
		if f.Code == CodeUnreadableCell {
			found = true
			if f.Count < 1 || !strings.Contains(f.MessageAR, "معادلة") {
				t.Fatalf("unreadable Arabic: %+v", f)
			}
			if !strings.Contains(f.HowToFixAR, "Excel") && !strings.Contains(f.HowToFixAR, "احفظ") {
				t.Fatalf("how to fix must mention save: %s", f.HowToFixAR)
			}
		}
	}
	if !found {
		t.Fatalf("expected unreadable_cell, got %+v", rep.Fixes)
	}
}

func TestCheckCleanSellOutOK(t *testing.T) {
	rows := [][]string{
		{"Barcode", "Store Name", "Item", "Qty", "Net Amount", "Month", "Year"},
		{"123", "سموحة", "صنف", "2", "50", "3", "2026"},
	}
	x, err := gemini.BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	rep := Check("ok.xlsx", x, Options{TenantID: "tenant-adeco"})
	if !rep.OK || rep.Blocking != 0 || !rep.WroteNothing {
		t.Fatalf("clean file must pass: %+v", rep)
	}
	if rep.Kind != "sell_out" {
		t.Fatalf("kind=%s", rep.Kind)
	}
}

func TestCheckSellOutMissingStoreAndUnclearMonth(t *testing.T) {
	rows := [][]string{
		{"Barcode", "Item", "Qty", "Net Amount"},
		{"123", "صنف", "2", "50"},
	}
	x, err := gemini.BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	rep := Check("bad_sellout.xlsx", x, Options{})
	if rep.OK || !rep.WroteNothing {
		t.Fatalf("must block: %+v", rep)
	}
	codes := map[string]bool{}
	for _, f := range rep.Fixes {
		codes[f.Code] = true
		if f.MessageAR == "" || f.HowToFixAR == "" {
			t.Fatalf("Arabic fields required: %+v", f)
		}
	}
	if !codes[CodeMissingColumn] || !codes[CodeUnclearMonth] {
		t.Fatalf("expected missing_column + unclear_month, got %v fixes=%+v", codes, rep.Fixes)
	}
}

func TestCheckNeverClaimsWrite(t *testing.T) {
	rep := Check("x.csv", []byte("a,b\n1,2\n"), Options{})
	if !rep.WroteNothing {
		t.Fatal("wrote_nothing must always be true")
	}
}

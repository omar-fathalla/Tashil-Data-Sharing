package gemini

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
)

// buildMultiSheetXLSX writes a workbook with named sheets using inline strings (synthetic fixture, no client data).
func buildMultiSheetXLSX(t *testing.T, sheets []string, data map[string][][]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	write := func(name, content string) {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = w.Write([]byte(content))
	}
	var wb, rels strings.Builder
	wb.WriteString(`<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>`)
	rels.WriteString(`<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`)
	for i, name := range sheets {
		wb.WriteString(fmt.Sprintf(`<sheet name="%s" sheetId="%d" r:id="rId%d"/>`, xmlEscape(name), i+1, i+1))
		rels.WriteString(fmt.Sprintf(`<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>`, i+1, i+1))
		var sh strings.Builder
		sh.WriteString(`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`)
		for r, row := range data[name] {
			sh.WriteString(fmt.Sprintf(`<row r="%d">`, r+1))
			for c, cell := range row {
				ref := fmt.Sprintf("%s%d", xlsxColLetters(c), r+1)
				sh.WriteString(fmt.Sprintf(`<c r="%s" t="inlineStr"><is><t>%s</t></is></c>`, ref, xmlEscape(cell)))
			}
			sh.WriteString(`</row>`)
		}
		sh.WriteString(`</sheetData></worksheet>`)
		write(fmt.Sprintf("xl/worksheets/sheet%d.xml", i+1), sh.String())
	}
	wb.WriteString(`</sheets></workbook>`)
	rels.WriteString(`</Relationships>`)
	write("[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>`)
	write("xl/workbook.xml", wb.String())
	write("xl/_rels/workbook.xml.rels", rels.String())
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

var wideHeader = []string{"المجموعة", "المورد", "الباركود", "الصنف", " سموحة", " ستانلى", "الاجمالى", "MONTH", "كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR"}

func TestLayoutGuardRejectsUnrecognisedPivot(t *testing.T) {
	// Pivot export whose branch columns are not in the recognised wide layout (no الاجمالى/MONTH/quantity block).
	rows := [][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026, MONTH: JAN"},
		{""},
		{"المجموعة", "المورد", "الباركود", "الصنف", "سموحة", "ستانلى", "العجمى"},
		{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "10", "20", "30"},
	}
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	err = checkSellOutLayout("Book3.xlsx", x)
	if err == nil || !errors.Is(err, ErrUploadValidation) || !strings.Contains(err.Error(), "Pivot") {
		t.Fatalf("expected Arabic pivot rejection, got %v", err)
	}
	if _, aerr := (&Client{useMock: true}).AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x); aerr == nil {
		t.Fatal("upload must fail instead of ingesting with a fabricated store")
	}
}

func TestLayoutGuardRejectsMissingStoreAndValue(t *testing.T) {
	rows := [][]string{
		{"Barcode", "Item Description", "Qty"},
		{"6223000233726", "فلفيتا", "12"},
	}
	x, _ := BuildSampleXLSX(rows)
	if err := checkSellOutLayout("units.xlsx", x); err == nil || !strings.Contains(err.Error(), "عمود للفرع") {
		t.Fatalf("expected missing store/value rejection, got %v", err)
	}
}

func TestLayoutGuardAcceptsKnownLayouts(t *testing.T) {
	tabular, _ := BuildSampleXLSX([][]string{
		{"Store_Name", "Barcode", "Item_Description", "Qty_Sold", "Net_Amount", "Date"},
		{"فتح الله سموحة", "6223000233726", "فلفيتا", "5", "500", "2026-01-31"},
	})
	if err := checkSellOutLayout("t.xlsx", tabular); err != nil {
		t.Fatalf("tabular rejected: %v", err)
	}
	pivotWide, _ := BuildSampleXLSX([][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026"}, {""}, wideHeader,
		{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "4380", "1679", "6059", "jan", "60", "23", "83", "2026"},
	})
	if err := checkSellOutLayout("Book3.xlsx", pivotWide); err != nil {
		t.Fatalf("recognised wide export rejected: %v", err)
	}
}

func TestWideWorkbookSkipsOtherYearSheet(t *testing.T) {
	row25 := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "100", "100", "200", "jan", "1", "1", "2", "2025"}
	row26 := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "300", "300", "600", "jan", "3", "3", "6", "2026"}
	x := buildMultiSheetXLSX(t, []string{"sale out2025", "sale out2026"}, map[string][][]string{
		"sale out2025": {wideHeader, row25},
		"sale out2026": {wideHeader, row26},
	})
	p, ok := parseWideMatrixXLSX("2026 out.xlsx", x)
	if !ok || p == nil {
		t.Fatal("expected wide workbook to parse")
	}
	var rev float64
	for _, r := range p.NormalizedRecords {
		rev += r.NetRevenue
		if !strings.HasPrefix(r.TransactionDate, "2026") {
			t.Errorf("2025 sheet leaked into 2026 out.xlsx: %+v", r)
		}
	}
	if rev != 600 {
		t.Errorf("expected only the 2026 sheet (600), got %v", rev)
	}
}

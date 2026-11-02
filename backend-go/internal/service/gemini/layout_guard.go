package gemini

import (
	"archive/zip"
	"bytes"
	"fmt"
	"strings"
)

const layoutGuardSampleRows = wideMatrixHeaderScanRows + 2

// UnsupportedLayoutError explains, in Arabic, why a sell-out file was rejected before ingestion.
func unsupportedLayoutError(filename, reason string) error {
	return fmt.Errorf("%w: تعذّر قراءة الملف %q ولم يتم حفظه: %s", ErrUploadValidation, filename, reason)
}

// checkSellOutLayout rejects sell-out files whose layout cannot be read faithfully, instead of letting
// a later fallback invent a store name and ingest quantities with zero value (the Book3.xlsx incident).
// It only inspects a small sample of each sheet. A nil result means "continue with normal parsing".
func checkSellOutLayout(filename string, rawContent []byte) error {
	for _, sample := range layoutSamples(rawContent) {
		if len(sample) < 2 {
			continue
		}
		if _, _, ok := findWideMatrixHeaderRow(sample, "fathalla"); ok {
			return nil
		}
		cols, hIdx, ok := findHeaderRow(sample)
		// A pivot title row ("Details for Sum of الاجمالى ...") must not be mistaken for a value header.
		if ok && hIdx >= 0 && hIdx < len(sample) && isPivotTitleRow(sample[hIdx]) {
			ok = false
		}
		if ok && (cols.storeNameIdx >= 0 || cols.revIdx >= 0) {
			return nil
		}
		if isPivotExport(sample) {
			return unsupportedLayoutError(filename, "الملف تقرير Pivot (\"Details for Sum of ...\") بأعمدة فروع غير متعرّف عليها. صدّر الملف بصيغة شيت المبيعات المعتادة (المجموعة، المورد، الباركود، الصنف، أعمدة الفروع، الاجمالى، MONTH، كميات الفروع، YEAR) ثم ارفعه مرة أخرى.")
		}
		if ok {
			return unsupportedLayoutError(filename, "لا يوجد عمود للفرع ولا عمود لقيمة المبيعات، فلا يمكن توزيع الكميات على الفروع أو حساب الإيراد. أضف عمود اسم الفرع وعمود صافي القيمة ثم ارفع الملف مرة أخرى.")
		}
	}
	return nil
}

func isPivotExport(rows [][]string) bool {
	for i := 0; i < len(rows) && i < 3; i++ {
		if isPivotTitleRow(rows[i]) {
			return true
		}
	}
	return false
}

func isPivotTitleRow(row []string) bool {
	joined := strings.ToLower(strings.Join(row, " "))
	return strings.Contains(joined, "details for") || strings.Contains(joined, "sum of")
}

// layoutSamples returns the first rows of every worksheet (XLSX) or of the CSV body.
func layoutSamples(rawContent []byte) [][][]string {
	if !isZipArchive(rawContent) {
		rows, err := parseCSVRows(rawContent)
		if err != nil {
			return nil
		}
		if len(rows) > layoutGuardSampleRows {
			rows = rows[:layoutGuardSampleRows]
		}
		return [][][]string{rows}
	}
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return nil
	}
	var sharedStrings []string
	fileByName := make(map[string]*zip.File)
	for _, f := range zr.File {
		lower := strings.ToLower(f.Name)
		fileByName[lower] = f
		if lower == "xl/sharedstrings.xml" {
			sharedStrings = readSharedStringsXML(f)
		}
	}
	var out [][][]string
	for _, entry := range listOrderedWorkbookSheets(zr, fileByName) {
		if rows, err := readWorksheetSampleRows(entry.file, sharedStrings, layoutGuardSampleRows); err == nil {
			out = append(out, rows)
		}
	}
	return out
}

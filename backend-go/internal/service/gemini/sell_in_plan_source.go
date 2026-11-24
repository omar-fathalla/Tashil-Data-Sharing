package gemini

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"io"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// A Plan workbook (Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx, first sheet «Sell_In_Plan_2026») is the
// supplier's plan, not Sell-In actuals. It is recognised only by its file name or first sheet name.

type workbookSheets struct {
	Sheets []struct {
		Name string `xml:"name,attr"`
	} `xml:"sheets>sheet"`
}

// firstSheetName is the name of the workbook's first sheet ("" for CSV or an unreadable workbook).
func firstSheetName(raw []byte) string {
	if !isZipArchive(raw) {
		return ""
	}
	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return ""
	}
	for _, f := range zr.File {
		if !strings.EqualFold(f.Name, "xl/workbook.xml") {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return ""
		}
		data, err := io.ReadAll(rc)
		_ = rc.Close()
		if err != nil {
			return ""
		}
		var wb workbookSheets
		if xml.Unmarshal(data, &wb) != nil || len(wb.Sheets) == 0 {
			return ""
		}
		return wb.Sheets[0].Name
	}
	return ""
}

// IsSellInPlanWorkbookSource reports whether a workbook is a Plan: its file name or first sheet name
// carries «Sell_In_Plan». Row values are never inspected.
func IsSellInPlanWorkbookSource(filename string, raw []byte) bool {
	return domain.IsSellInPlanName(filename) || domain.IsSellInPlanName(firstSheetName(raw))
}

func stampSellInPlanSource(recs []domain.SellInRecord, report *SellInParseReport) {
	report.PlanSource = true
	for i := range recs {
		recs[i].SourceKind = domain.SellInSourceKindPlan
	}
}

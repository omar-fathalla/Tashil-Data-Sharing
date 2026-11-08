package gemini

// sheetSelectionPlan decides which workbook sheets to ingest so monthly tabs and
// leftover full-year dumps for the same period are never summed twice.
type sheetSelectionPlan struct {
	fileYear                 int
	hasMatchingFileYearSheet bool
	yearsWithMonthly         map[int]bool
}

// buildSheetSelectionPlan inspects sheet names only (no cell scan) and records:
//   - explicit year from the upload filename (when present)
//   - whether any sheet name matches that file year
//   - which years already have at least one month-named sheet
func buildSheetSelectionPlan(filename string, sheetNames []string) sheetSelectionPlan {
	plan := sheetSelectionPlan{
		fileYear:         inferYearFromText(filename, 0),
		yearsWithMonthly: make(map[int]bool),
	}
	for _, name := range sheetNames {
		yr := inferYearFromText(name, 0)
		if plan.fileYear >= 2020 && yr == plan.fileYear {
			plan.hasMatchingFileYearSheet = true
		}
		if yr >= 2020 && parseSmartMonthToken(name) > 0 {
			plan.yearsWithMonthly[yr] = true
		}
	}
	return plan
}

// shouldIncludeSheet reports whether a worksheet should contribute rows to
// normalized ingestion. Rules (no double counting):
//  1. When the filename targets year Y and a Y sheet exists, skip leftover
//     full-year sheets from other years (e.g. "sale out2025" inside "2026 out.xlsx").
//  2. When year Y already has month-named sheets (e.g. "يناير 26"), skip the
//     same year's full-year dump ("sale out2026") so months are not counted twice.
// Month-named sheets across years stay included for MoM/YoY trends.
func (p sheetSelectionPlan) shouldIncludeSheet(sheetName string) bool {
	yr := inferYearFromText(sheetName, 0)
	month := parseSmartMonthToken(sheetName)
	isFullYearSheet := yr >= 2020 && month == 0
	if !isFullYearSheet {
		return true
	}
	if p.hasMatchingFileYearSheet && yr != p.fileYear {
		return false
	}
	if p.yearsWithMonthly[yr] {
		return false
	}
	return true
}

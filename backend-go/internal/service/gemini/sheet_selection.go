package gemini

// sheetSelectionPlan decides which physical workbook sheets to open.
// Same-year monthly tabs never silently drop a full-year sheet here — overlapping
// periods are resolved later by dedupeSheetsByPeriodCoverage after parse.
type sheetSelectionPlan struct {
	fileYear                 int
	hasMatchingFileYearSheet bool
}

// buildSheetSelectionPlan inspects sheet names only (no cell scan).
func buildSheetSelectionPlan(filename string, sheetNames []string) sheetSelectionPlan {
	plan := sheetSelectionPlan{
		fileYear: inferYearFromText(filename, 0),
	}
	for _, name := range sheetNames {
		yr := inferYearFromText(name, 0)
		if plan.fileYear >= 2020 && yr == plan.fileYear {
			plan.hasMatchingFileYearSheet = true
		}
	}
	return plan
}

// isFullYearSheetName is a year-labeled tab with no month token (e.g. "sale out2026").
func isFullYearSheetName(sheetName string) bool {
	yr := inferYearFromText(sheetName, 0)
	return yr >= 2020 && parseSmartMonthToken(sheetName) == 0
}

// isMonthNamedSheetName is a tab whose name encodes a calendar month (e.g. "يناير 26").
func isMonthNamedSheetName(sheetName string) bool {
	return parseSmartMonthToken(sheetName) > 0 && inferYearFromText(sheetName, 0) >= 2020
}

// shouldIncludeSheet reports whether a physical worksheet should be opened.
// Only leftover other-year full-year dumps are excluded when the filename already
// targets a year that has a matching sheet. Month-named tabs never suppress a
// same-year full-year sheet at this stage.
func (p sheetSelectionPlan) shouldIncludeSheet(sheetName string) bool {
	if !isFullYearSheetName(sheetName) {
		return true
	}
	yr := inferYearFromText(sheetName, 0)
	if p.hasMatchingFileYearSheet && yr != p.fileYear {
		return false
	}
	return true
}

// periodKeyFromSheetDate returns "YYYY-MM" when sheetDate is ISO-like.
func periodKeyFromSheetDate(sheetDate string) string {
	if len(sheetDate) >= 7 && sheetDate[4] == '-' {
		return sheetDate[:7]
	}
	return ""
}

// sheetSummaryHasUsableData is true when the sheet has at least one non-empty data row.
func sheetSummaryHasUsableData(sh parsedSheetSummary) bool {
	if len(sh.rows) < 2 {
		return false
	}
	for i := 1; i < len(sh.rows); i++ {
		if !isRowEmpty(sh.rows[i]) {
			return true
		}
	}
	return false
}

// dedupeSheetsByPeriodCoverage prefers valid month-named periods over overlapping
// full-year / split periods for the same YYYY-MM. Periods present only on the
// full-year side stay. Empty or invalid monthly sheets do not claim coverage, so
// the yearly sheet is not dropped for those months.
func dedupeSheetsByPeriodCoverage(sheets []parsedSheetSummary) []parsedSheetSummary {
	if len(sheets) < 2 {
		return sheets
	}
	covered := make(map[string]bool)
	for _, sh := range sheets {
		if !sh.preferOverFullYear || !sheetSummaryHasUsableData(sh) {
			continue
		}
		if pk := periodKeyFromSheetDate(sh.sheetDate); pk != "" {
			covered[pk] = true
		}
	}
	if len(covered) == 0 {
		return sheets
	}
	out := make([]parsedSheetSummary, 0, len(sheets))
	for _, sh := range sheets {
		pk := periodKeyFromSheetDate(sh.sheetDate)
		if !sh.preferOverFullYear && pk != "" && covered[pk] {
			continue
		}
		out = append(out, sh)
	}
	return out
}

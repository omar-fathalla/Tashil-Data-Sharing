// Package preupload inspects Excel/CSV bytes before staging or committing.
// It never writes archives, BigQuery, Firestore, or staged files — only returns
// an Arabic fix list for missing columns, unclear months, and unreadable cells.
package preupload

import (
	"errors"
	"fmt"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Issue codes returned to the UI (stable API contract).
const (
	CodeMissingColumn  = "missing_column"
	CodeUnclearMonth   = "unclear_month"
	CodeUnreadableCell = "unreadable_cell"
	CodeEmptyFile      = "empty_file"
)

// FixItem is one actionable Arabic fix the uploader should apply before retrying.
type FixItem struct {
	Code       string   `json:"code"`
	Severity   string   `json:"severity"` // "error" blocks upload; "warning" is advisory
	MessageAR  string   `json:"message_ar"`
	HowToFixAR string   `json:"how_to_fix_ar"`
	Column     string   `json:"column,omitempty"`
	Samples    []string `json:"samples,omitempty"`
	Count      int      `json:"count,omitempty"`
}

// Report is the pre-upload checker response. WroteNothing is always true.
type Report struct {
	OK           bool      `json:"ok"`
	Filename     string    `json:"filename"`
	Kind         string    `json:"kind,omitempty"` // sell_in | sell_out | product_master | unknown
	WroteNothing bool      `json:"wrote_nothing"`
	Blocking     int       `json:"blocking_count"`
	Fixes        []FixItem `json:"fixes"`
}

// Options control how the checker classifies the workbook.
type Options struct {
	TenantID string
	Chain    string
}

// Check inspects raw file bytes and returns an Arabic fix list. It never mutates
// durable state and does not call Gemini.
func Check(filename string, raw []byte, opts Options) Report {
	rep := Report{
		Filename:     filename,
		WroteNothing: true,
		Fixes:        nil,
	}
	if len(raw) == 0 {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeEmptyFile,
			Severity:   "error",
			MessageAR:  "الملف فاضي أو مفيش بايتات اتبعتت.",
			HowToFixAR: "اختار ملف Excel أو CSV فيه بيانات، بعدين اعمل فحص تاني قبل الرفع.",
		})
		return finalize(rep)
	}

	// 1) Unreadable formula cells (any XLSX) — always check first.
	if formulas := gemini.FindUncachedFormulaCells(raw); formulas.Count > 0 {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeUnreadableCell,
			Severity:   "error",
			MessageAR:  gemini.UncachedFormulaMessageAR(formulas),
			HowToFixAR: "افتح الملف في Microsoft Excel أو Google Sheets، استنى المعادلات تتحسب، احفظه (Save)، بعدين ارفعه من تاني.",
			Samples:    formulas.Cells,
			Count:      formulas.Count,
		})
	}

	tenant := strings.TrimSpace(opts.TenantID)
	if tenant == "" {
		tenant = "preupload"
	}
	chain := strings.TrimSpace(opts.Chain)

	switch {
	case gemini.IsProductMasterWorkbook(raw):
		rep.Kind = "product_master"
		// Product master has its own parser; surface formula issues only here.
	case gemini.IsSellInPlanWorkbook(raw) || looksLikeSellInCandidate(raw):
		rep.Kind = "sell_in"
		appendSellInFixes(&rep, tenant, filename, raw, chain)
	default:
		rep.Kind = "sell_out"
		appendSellOutFixes(&rep, filename, raw)
	}

	return finalize(rep)
}

func finalize(rep Report) Report {
	blocking := 0
	for _, f := range rep.Fixes {
		if f.Severity == "error" {
			blocking++
		}
	}
	rep.Blocking = blocking
	rep.OK = blocking == 0
	if rep.Fixes == nil {
		rep.Fixes = []FixItem{}
	}
	return rep
}

func appendSellInFixes(rep *Report, tenant, filename string, raw []byte, chain string) {
	// Incomplete raw-plan headers (e.g. net Q without net V) are rejected before the parser
	// builds SellInLayoutError — surface them here so the Arabic fix list stays useful.
	if missing := incompleteRawPlanMissingColumns(raw); len(missing) > 0 {
		for _, col := range missing {
			rep.Fixes = append(rep.Fixes, FixItem{
				Code:       CodeMissingColumn,
				Severity:   "error",
				Column:     col,
				MessageAR:  fmt.Sprintf("عمود مطلوب مش موجود: %s", col),
				HowToFixAR: "ضيف عنوان العمود ده في صف العناوين (بالاسم الصحيح) من غير ما تعتمد على ترتيب الأعمدة، بعدين احفظ الملف وافحصه تاني.",
			})
		}
		return
	}

	_, _, err := gemini.ParseSellInPlanWorkbookWithReport(tenant, filename, raw, chain)
	if err == nil {
		return
	}
	var layoutErr *gemini.SellInLayoutError
	if errors.As(err, &layoutErr) {
		for _, col := range layoutErr.Missing {
			rep.Fixes = append(rep.Fixes, FixItem{
				Code:       CodeMissingColumn,
				Severity:   "error",
				Column:     col,
				MessageAR:  fmt.Sprintf("عمود مطلوب مش موجود: %s", col),
				HowToFixAR: "ضيف عنوان العمود ده في صف العناوين (بالاسم الصحيح) من غير ما تعتمد على ترتيب الأعمدة، بعدين احفظ الملف وافحصه تاني.",
			})
		}
		if len(layoutErr.Missing) == 0 {
			rep.Fixes = append(rep.Fixes, FixItem{
				Code:       CodeMissingColumn,
				Severity:   "error",
				MessageAR:  layoutErr.Error(),
				HowToFixAR: "صحّح عناوين الأعمدة الناقصة في الصف الأول، احفظ الملف، وافحصه قبل الرفع.",
			})
		}
		return
	}
	var periodErr *gemini.SellInPeriodError
	if errors.As(err, &periodErr) {
		samples := periodErr.MonthSamples
		if len(samples) > 5 {
			samples = samples[:5]
		}
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeUnclearMonth,
			Severity:   "error",
			MessageAR:  periodErr.Error(),
			HowToFixAR: "اكتب الشهر برقم من 1 لـ 12 أو باسم واضح (يناير / Jan) والسنة في كل صف، من غير خلايا فاضي أو قيم زي #N/A.",
			Samples:    samples,
			Count:      periodErr.BadMonthRows + periodErr.NoYearRows + periodErr.ConflictRows,
		})
		return
	}
	var chainErr *gemini.SellInChainRequiredError
	if errors.As(err, &chainErr) {
		// Chain selection is a form issue, not a workbook column fix — leave to upload guards.
		return
	}
	// Unknown layout: do not invent AI fixes; upload path decides later.
}

// looksLikeSellInCandidate catches incomplete Sell-In / GP SOP workbooks that IsSellInPlanWorkbook
// would miss (e.g. raw plan missing net V, or SOP missing Extended Price).
func looksLikeSellInCandidate(raw []byte) bool {
	rows, err := gemini.ExtractXLSXOrCSVRows(raw)
	if err != nil || len(rows) == 0 {
		return false
	}
	limit := 15
	if len(rows) < limit {
		limit = len(rows)
	}
	for i := 0; i < limit; i++ {
		j := strings.ToLower(strings.Join(rows[i], " | "))
		if strings.Contains(j, "sop number") && strings.Contains(j, "customer name") {
			return true
		}
		if strings.Contains(j, "net q") && (strings.Contains(j, "item 1") || strings.Contains(j, "customer")) {
			return true
		}
		if strings.Contains(j, "sell_in_cases") || strings.Contains(j, "كمية التوريد بالكرتونة") ||
			strings.Contains(j, "retail_chain") || strings.Contains(j, "سلسلة التجزئة") {
			return true
		}
	}
	return false
}

func incompleteRawPlanMissingColumns(raw []byte) []string {
	rows, err := gemini.ExtractXLSXOrCSVRows(raw)
	if err != nil || len(rows) == 0 {
		return nil
	}
	header, headerIdx := findRawPlanHeader(rows)
	if headerIdx < 0 {
		return nil
	}
	j := strings.ToLower(strings.Join(header, " | "))
	// Only for narrow raw-plan style headers (not guided / clean / SOP).
	if strings.Contains(j, "sell_in") || strings.Contains(j, "كمية التوريد") ||
		strings.Contains(j, "sop number") || strings.Contains(j, "net_qty_cases") {
		return nil
	}
	if !(strings.Contains(j, "net q") || strings.Contains(j, "item 1") || strings.Contains(j, "customer")) {
		return nil
	}
	required := []struct {
		name string
		pred func(string) bool
	}{
		{"Customer", func(h string) bool { return strings.Contains(h, "customer") || strings.Contains(h, "عميل") }},
		// Exact "Item 1" / "item1" only — never match a generic "item" / "Item Description".
		{"Item 1", isItem1Header},
		{"Month", func(h string) bool { return strings.Contains(h, "month") || strings.Contains(h, "شهر") }},
		{"Year", func(h string) bool { return strings.Contains(h, "year") || strings.Contains(h, "سنة") || strings.Contains(h, "عام") }},
		{"net Q", func(h string) bool { return strings.Contains(h, "net q") || strings.Contains(h, "net_q") }},
		{"net V", func(h string) bool { return strings.Contains(h, "net v") || strings.Contains(h, "net_v") }},
	}
	var missing []string
	for _, req := range required {
		found := false
		for _, cell := range header {
			if req.pred(strings.ToLower(strings.TrimSpace(cell))) {
				found = true
				break
			}
		}
		if !found {
			missing = append(missing, req.name)
		}
	}
	return missing
}

func isItem1Header(h string) bool {
	h = strings.TrimSpace(strings.ToLower(h))
	switch h {
	case "item 1", "item1", "item_1":
		return true
	}
	return strings.HasPrefix(h, "item 1 ") || strings.HasPrefix(h, "item1 ")
}

// findRawPlanHeader prefers a real raw-plan header over a title/preamble row.
func findRawPlanHeader(rows [][]string) ([]string, int) {
	limit := 15
	if len(rows) < limit {
		limit = len(rows)
	}
	bestIdx, bestScore := -1, 0
	var best []string
	for i := 0; i < limit; i++ {
		if rowEmpty(rows[i]) {
			continue
		}
		score := 0
		joined := strings.ToLower(strings.Join(rows[i], " | "))
		for _, kw := range []string{"customer", "item 1", "net q", "net v", "month", "year", "عميل"} {
			if strings.Contains(joined, kw) {
				score++
			}
		}
		if score > bestScore {
			bestScore, bestIdx, best = score, i, rows[i]
		}
	}
	if bestScore >= 2 {
		return best, bestIdx
	}
	return nil, -1
}

func appendSellOutFixes(rep *Report, filename string, raw []byte) {
	rows, err := gemini.ExtractXLSXOrCSVRows(raw)
	if err != nil {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeUnreadableCell,
			Severity:   "error",
			MessageAR:  fmt.Sprintf("تعذّر قراءة الملف %q: %v", filename, err),
			HowToFixAR: "تأكد إن الملف Excel (.xlsx) أو CSV سليم ومش مكسور، بعدين حاول تاني.",
		})
		return
	}
	if len(rows) == 0 {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeEmptyFile,
			Severity:   "error",
			MessageAR:  "الملف مفيهوش صفوف مقروءة.",
			HowToFixAR: "تأكد إن الشيت فيه عناوين وصفوف بيانات، بعدين ارفعه تاني.",
		})
		return
	}

	header, headerIdx := findLikelyHeader(rows)
	if headerIdx < 0 {
		// Parser could not locate a header — blocking.
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeMissingColumn,
			Severity:   "error",
			MessageAR:  "مفيش صف عناوين واضح في أول الملف.",
			HowToFixAR: "خلّي الصف الأول (أو قريب منه) فيه أسماء الأعمدة: الفرع، الباركود، الصنف، الكمية، القيمة، الشهر/التاريخ.",
		})
		return
	}

	// Fathalla / Adco wide branch-pivot: branch columns replace a single store column.
	// Never block these workbooks for "missing store".
	wide := isWideMatrixHeader(header)
	joined := strings.ToLower(strings.Join(header, " "))
	hasStore := wide || containsAny(joined, []string{"store", "branch", "فرع", "معرض", "outlet"})
	hasValue := wide || containsAny(joined, []string{
		"revenue", "amount", "value", "sales", "net", "price", "قيمة", "مبيعات", "إيراد", "اجمالي", "إجمالي", "الاجمالى", "الاجمالي",
	})
	hasMonthOrDate := containsAny(joined, []string{"month", "date", "year", "شهر", "تاريخ", "سنة", "عام"})

	// Heuristic gaps are warnings; dry-run/parser decides hard failures.
	if !hasStore && !wide {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeMissingColumn,
			Severity:   "warning",
			Column:     "store/branch",
			MessageAR:  "عمود اسم الفرع / المعرض مش موجود أو مش متعرّف عليه.",
			HowToFixAR: "ضيف عمود واضح لاسم الفرع (مثلاً «اسم الفرع» أو Store Name) في صف العناوين.",
		})
	}
	if !hasValue && !wide {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeMissingColumn,
			Severity:   "warning",
			Column:     "value/revenue",
			MessageAR:  "عمود قيمة المبيعات مش موجود أو مش متعرّف عليه.",
			HowToFixAR: "ضيف عمود لصافي القيمة أو المبيعات (مثلاً «صافي قيمة المبيعات» أو Net Amount).",
		})
	}

	monthIdx, dateIdx, yearIdx := -1, -1, -1
	for i, h := range header {
		n := strings.ToLower(strings.TrimSpace(h))
		switch {
		case monthIdx < 0 && (strings.Contains(n, "month") || n == "شهر" || strings.Contains(n, "الشهر")):
			monthIdx = i
		case dateIdx < 0 && (strings.Contains(n, "date") || strings.Contains(n, "تاريخ")):
			dateIdx = i
		case yearIdx < 0 && (n == "year" || n == "سنة" || n == "السنة" || n == "عام"):
			yearIdx = i
		}
	}

	if !hasMonthOrDate && monthIdx < 0 && dateIdx < 0 {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeUnclearMonth,
			Severity:   "warning",
			MessageAR:  "مفيش عمود شهر أو تاريخ واضح، فمش هينفع نحدد فترة الصفوف.",
			HowToFixAR: "ضيف عمود Month/الشهر أو Date/التاريخ (وسنة لو مش جوه التاريخ)، واملأ كل صف بقيمة مفهومة.",
		})
		return
	}

	bad := 0
	var samples []string
	scanLimit := headerIdx + 1 + 40
	if scanLimit > len(rows) {
		scanLimit = len(rows)
	}
	for r := headerIdx + 1; r < scanLimit; r++ {
		row := rows[r]
		if rowEmpty(row) {
			continue
		}
		ok := false
		if dateIdx >= 0 && dateIdx < len(row) {
			if _, _, parsed := gemini.ParseDateToken(row[dateIdx]); parsed {
				ok = true
			}
		}
		if !ok && monthIdx >= 0 && monthIdx < len(row) {
			if m, y, parsed := gemini.ParseMonthToken(row[monthIdx]); parsed {
				if y > 0 || yearIdx < 0 {
					ok = true
				} else if yearIdx < len(row) {
					if _, yOK := gemini.ParseYearToken(row[yearIdx]); yOK || m > 0 {
						ok = m > 0
					}
				} else {
					ok = m > 0
				}
			}
		}
		if ok {
			continue
		}
		if monthIdx >= 0 || dateIdx >= 0 {
			bad++
			if len(samples) < 5 {
				rawVal := ""
				if monthIdx >= 0 && monthIdx < len(row) {
					rawVal = strings.TrimSpace(row[monthIdx])
				}
				if rawVal == "" && dateIdx >= 0 && dateIdx < len(row) {
					rawVal = strings.TrimSpace(row[dateIdx])
				}
				if rawVal == "" {
					rawVal = "(فاضي)"
				}
				samples = append(samples, fmt.Sprintf("صف %d: %q", r+1, rawVal))
			}
		}
	}
	if bad > 0 {
		rep.Fixes = append(rep.Fixes, FixItem{
			Code:       CodeUnclearMonth,
			Severity:   "warning",
			MessageAR:  fmt.Sprintf("%d صف الشهر أو التاريخ فيه مش مفهوم في عيّنة أول الملف.", bad),
			HowToFixAR: "صحّح قيم الشهر/التاريخ في الصفوف دي (رقم 1–12 أو اسم الشهر، أو تاريخ كامل)، من غير #N/A أو خلايا فاضي في عمود الفترة.",
			Samples:    samples,
			Count:      bad,
		})
	}
}

// isWideMatrixHeader detects Fathalla/Adco wide branch-pivot headers (branch columns + totals + MONTH).
func isWideMatrixHeader(header []string) bool {
	if len(header) < 8 {
		return false
	}
	joined := strings.ToLower(strings.Join(header, " | "))
	hasMonth := strings.Contains(joined, "month") || strings.Contains(joined, "شهر")
	hasYear := strings.Contains(joined, "year") || strings.Contains(joined, "سنة") || strings.Contains(joined, "عام")
	hasTotal := strings.Contains(joined, "الاجمالى") || strings.Contains(joined, "الاجمالي") ||
		strings.Contains(joined, "total") || strings.Contains(joined, "اجمالى")
	hasBarcodeOrItem := strings.Contains(joined, "باركود") || strings.Contains(joined, "barcode") ||
		strings.Contains(joined, "الصنف") || strings.Contains(joined, "صنف")
	return hasMonth && (hasYear || hasTotal) && hasBarcodeOrItem && (hasTotal || hasYear)
}

func findLikelyHeader(rows [][]string) ([]string, int) {
	limit := 15
	if len(rows) < limit {
		limit = len(rows)
	}
	bestIdx, bestScore := -1, 0
	var best []string
	for i := 0; i < limit; i++ {
		if rowEmpty(rows[i]) {
			continue
		}
		score := 0
		joined := strings.ToLower(strings.Join(rows[i], " "))
		for _, kw := range []string{
			"barcode", "باركود", "store", "فرع", "quantity", "كمية", "month", "شهر",
			"date", "تاريخ", "value", "قيمة", "sku", "صنف", "year", "سنة", "branch",
			"الاجمالى", "الاجمالي", "المورد", "المجموعة",
		} {
			if strings.Contains(joined, kw) {
				score++
			}
		}
		if score > bestScore {
			bestScore, bestIdx, best = score, i, rows[i]
		}
	}
	if bestScore >= 2 {
		return best, bestIdx
	}
	if len(rows) > 0 && !rowEmpty(rows[0]) {
		return rows[0], 0
	}
	return nil, -1
}

func rowEmpty(row []string) bool {
	for _, c := range row {
		if strings.TrimSpace(c) != "" {
			return false
		}
	}
	return true
}

func containsAny(hay string, needles []string) bool {
	for _, n := range needles {
		if strings.Contains(hay, n) {
			return true
		}
	}
	return false
}

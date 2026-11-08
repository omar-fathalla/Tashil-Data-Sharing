// Package totalsxplain builds Arabic explanations of Excel totals differences
// from already-computed validation numbers. It does not re-run honesty thresholds.
package totalsxplain

import (
	"fmt"
	"math"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Reason codes attached to IngestionValidation.DiffReasons.
const (
	ReasonReturns         = "returns"
	ReasonRounding        = "rounding"
	ReasonMissingMonth    = "missing_month"
	ReasonUnreadColumns   = "unread_columns"
	ReasonSheetColumnGap  = "sheet_column_gap"
	ReasonSourceCellGap   = "source_cell_gap"
	ReasonZeroValue       = "zero_value"
	ReasonNoRecords       = "no_records"
	ReasonMatched         = "matched"
)

// Provenance locates the numbers in the workbook (sheet / column / rows).
// Indices are 0-based as produced by the mapping plan; Arabic text uses 1-based Excel columns/rows.
//
// Known must be set true by builders that actually resolved location. Builders that only
// fill -1 sentinels with Known=false must not invent "Sheet1" or a matched confirmation.
type Provenance struct {
	Known                  bool // false → no location clause / no quiet "matched" text
	SheetName              string
	HeaderRowIndex         int // 0-based; -1 if unknown
	DataRowFirst           int // 0-based inclusive; -1 if unknown
	DataRowLast            int // 0-based inclusive; -1 if unknown
	Layout                 string
	ValueColumnIndex       int // primary mapped value col, or -1
	UnitsColumnIndex       int // primary mapped units col, or -1
	SheetTotalValueColIdx  int
	SheetTotalUnitsColIdx  int
	ValueColumnHeader      string
	UnitsColumnHeader      string
	SheetTotalValueHeader  string
	SheetTotalUnitsHeader  string
	NegativeValueCells     int
	NegativeUnitsCells     int
	FractionalQtyCells     int
}

// Outcome is the Arabic narrative plus machine-readable reason codes.
type Outcome struct {
	ExplanationAR string
	Reasons       []string
}

// Explain builds an Arabic explanation grounded in v's computed totals.
// Returns an empty Outcome when v is nil or there is nothing useful to say.
func Explain(v *domain.IngestionValidation, p Provenance) Outcome {
	if v == nil {
		return Outcome{}
	}
	var reasons []string
	var parts []string

	loc := locationClause(p)
	if loc != "" {
		parts = append(parts, loc)
	}

	// Structural / missing issues first (from validation status + issues + numbers).
	if v.RecordCount == 0 || containsIssue(v.Issues, "no records") {
		reasons = append(reasons, ReasonNoRecords)
		parts = append(parts, "لم يُستخرج أي سجل من الملف.")
	}
	if containsIssue(v.Issues, "no month") || (len(v.MonthsDetected) == 0 && v.Status == "rejected") {
		reasons = appendUnique(reasons, ReasonMissingMonth)
		parts = append(parts, "لم يُكتشف عمود/قيمة شهر في الصفوف المقروءة، لذلك لا يمكن اعتماد الإجمالي لفترة محددة.")
	}
	if containsIssue(v.Issues, "columns were not read") || containsIssue(v.Issues, "row count") {
		reasons = appendUnique(reasons, ReasonUnreadColumns)
		parts = append(parts, fmt.Sprintf(
			"أعمدة الكمية/القيمة لم تُقرأ بشكل صحيح: عدد الوحدات المستخرجة (%d) يساوي عدد الصفوف والقيمة صفر.",
			v.ExtractedUnits))
	}
	if containsIssue(v.Issues, "value total is zero") || (v.ExtractedValue == 0 && v.ExtractedUnits > 0 && v.RecordCount >= 20) {
		reasons = appendUnique(reasons, ReasonZeroValue)
		parts = append(parts, fmt.Sprintf("إجمالي القيمة المستخرجة صفر بينما الوحدات = %d.", v.ExtractedUnits))
	}

	valueSheetDiff := absDiff(v.ExtractedValue, v.SheetTotalValue)
	unitsSheetDiff := absDiff(float64(v.ExtractedUnits), v.SheetTotalUnits)
	valueSourceDiff := absDiff(v.ExtractedValue, v.SourceValue)
	unitsSourceDiff := absDiff(float64(v.ExtractedUnits), v.SourceUnits)

	hasSheetValue := v.SheetTotalValue != 0
	hasSheetUnits := v.SheetTotalUnits != 0
	hasSourceValue := v.SourceValue != 0
	hasSourceUnits := v.SourceUnits != 0

	if hasSourceValue && valueSourceDiff > 0.01 && rel(v.ExtractedValue, v.SourceValue) > 0.01 {
		reasons = appendUnique(reasons, ReasonSourceCellGap)
		parts = append(parts, fmt.Sprintf(
			"فرق عن خلايا المصدر: القيمة المستخرجة %.2f ج.م مقابل مجموع خلايا القيمة الموجبة %.2f ج.م (فرق %.2f).",
			v.ExtractedValue, v.SourceValue, valueSourceDiff))
	}
	if hasSourceUnits && unitsSourceDiff >= 1 && rel(float64(v.ExtractedUnits), v.SourceUnits) > 0.01 {
		reasons = appendUnique(reasons, ReasonSourceCellGap)
		parts = append(parts, fmt.Sprintf(
			"فرق عن خلايا المصدر: الوحدات المستخرجة %d مقابل مجموع خلايا الكمية الموجبة %.0f (فرق %.0f).",
			v.ExtractedUnits, v.SourceUnits, unitsSourceDiff))
	}

	if hasSheetValue && valueSheetDiff > 0.01 && rel(v.ExtractedValue, v.SheetTotalValue) > 0.01 {
		reasons = appendUnique(reasons, ReasonSheetColumnGap)
		col := columnPhrase(p.SheetTotalValueColIdx, p.SheetTotalValueHeader, "إجمالي القيمة")
		parts = append(parts, fmt.Sprintf(
			"مقارنة بعمود %s: المستخرج %.2f ج.م، عمود الإجمالي في الورقة %.2f ج.م (فرق %.2f / %.1f%%).",
			col, v.ExtractedValue, v.SheetTotalValue, valueSheetDiff, rel(v.ExtractedValue, v.SheetTotalValue)*100))
	}
	if hasSheetUnits && unitsSheetDiff >= 1 && rel(float64(v.ExtractedUnits), v.SheetTotalUnits) > 0.01 {
		reasons = appendUnique(reasons, ReasonSheetColumnGap)
		col := columnPhrase(p.SheetTotalUnitsColIdx, p.SheetTotalUnitsHeader, "إجمالي الكمية")
		parts = append(parts, fmt.Sprintf(
			"مقارنة بعمود %s: الوحدات المستخرجة %d، عمود الإجمالي %.0f (فرق %.0f / %.1f%%).",
			col, v.ExtractedUnits, v.SheetTotalUnits, unitsSheetDiff, rel(float64(v.ExtractedUnits), v.SheetTotalUnits)*100))
	}

	// Returns: positives-only extraction vs sheet total that includes negatives.
	sheetLowerValue := hasSheetValue && hasSourceValue &&
		v.SheetTotalValue < v.SourceValue-0.01 &&
		valueSourceDiff <= math.Max(0.01, 0.01*math.Abs(v.SourceValue))
	sheetLowerUnits := hasSheetUnits && hasSourceUnits &&
		v.SheetTotalUnits < v.SourceUnits-0.5 &&
		unitsSourceDiff <= math.Max(1, 0.01*math.Abs(v.SourceUnits))
	if (sheetLowerValue || sheetLowerUnits) && (p.NegativeValueCells > 0 || p.NegativeUnitsCells > 0 ||
		(hasSheetValue && valueSheetDiff > 0.01) || (hasSheetUnits && unitsSheetDiff >= 1)) {
		reasons = appendUnique(reasons, ReasonReturns)
		negParts := []string{}
		if p.NegativeValueCells > 0 {
			negParts = append(negParts, fmt.Sprintf("%d خلية قيمة سالبة", p.NegativeValueCells))
		}
		if p.NegativeUnitsCells > 0 {
			negParts = append(negParts, fmt.Sprintf("%d خلية كمية سالبة", p.NegativeUnitsCells))
		}
		detail := "مرتجعات/قيم سالبة: الاستخراج يجمع الخلايا الموجبة فقط بينما عمود إجمالي الورقة يشمل السالب."
		if len(negParts) > 0 {
			detail += " وُجدت " + strings.Join(negParts, " و") + "."
		}
		if sheetLowerValue {
			detail += fmt.Sprintf(" فرق القيمة المنسوب للمرتجعات ≈ %.2f ج.م.", v.SourceValue-v.SheetTotalValue)
		}
		parts = append(parts, detail)
	}

	// Rounding: small units gap with fractional qty cells, or absolute units gap < 1% and < few units.
	if p.FractionalQtyCells > 0 && hasSheetUnits && unitsSheetDiff > 0 && unitsSheetDiff < 5 {
		reasons = appendUnique(reasons, ReasonRounding)
		parts = append(parts, fmt.Sprintf(
			"تقريب الكميات: %d خلية كمية كسرية؛ الفرق بعد التقريب إلى أقرب عدد صحيح ≈ %.0f وحدة.",
			p.FractionalQtyCells, unitsSheetDiff))
	} else if hasSheetUnits && unitsSheetDiff > 0 && unitsSheetDiff < 3 &&
		rel(float64(v.ExtractedUnits), v.SheetTotalUnits) <= 0.01 {
		reasons = appendUnique(reasons, ReasonRounding)
		parts = append(parts, fmt.Sprintf(
			"فرق وحدات صغير (%.0f) يُرجَّح أنه من تقريب الكميات الكسرية إلى أعداد صحيحة.",
			unitsSheetDiff))
	}

	if len(reasons) == 0 {
		if v.Status == "ok" && len(v.Issues) == 0 {
			// Quiet success — optional short confirmation only when provenance exists.
			if loc == "" {
				return Outcome{}
			}
			reasons = []string{ReasonMatched}
			parts = append(parts, fmt.Sprintf(
				"إجماليات متطابقة ضمن الهامش: قيمة %.2f ج.م ووحدات %d عبر %d سجل.",
				v.ExtractedValue, v.ExtractedUnits, v.RecordCount))
		} else if len(v.Issues) > 0 {
			// Fallback: surface issues with numbers even if codes were not classified.
			parts = append(parts, fmt.Sprintf(
				"حالة التحقق: %s — المستخرج %.2f ج.م / %d وحدة؛ مصدر %.2f / %.0f؛ إجمالي الورقة %.2f / %.0f.",
				v.Status, v.ExtractedValue, v.ExtractedUnits, v.SourceValue, v.SourceUnits, v.SheetTotalValue, v.SheetTotalUnits))
		} else {
			return Outcome{}
		}
	}

	text := strings.TrimSpace(strings.Join(parts, " "))
	return Outcome{ExplanationAR: text, Reasons: reasons}
}

func locationClause(p Provenance) string {
	if !p.Known {
		return ""
	}
	var bits []string
	if strings.TrimSpace(p.SheetName) != "" {
		bits = append(bits, fmt.Sprintf("الورقة «%s»", strings.TrimSpace(p.SheetName)))
	}
	if p.Layout != "" {
		bits = append(bits, fmt.Sprintf("التخطيط %s", p.Layout))
	}
	if p.HeaderRowIndex >= 0 {
		bits = append(bits, fmt.Sprintf("صف العناوين %d", p.HeaderRowIndex+1))
	}
	if p.DataRowFirst >= 0 && p.DataRowLast >= p.DataRowFirst {
		bits = append(bits, fmt.Sprintf("صفوف البيانات %d–%d", p.DataRowFirst+1, p.DataRowLast+1))
	}
	if p.ValueColumnIndex >= 0 || p.ValueColumnHeader != "" {
		bits = append(bits, "عمود القيمة "+columnPhrase(p.ValueColumnIndex, p.ValueColumnHeader, "القيمة"))
	}
	if p.UnitsColumnIndex >= 0 || p.UnitsColumnHeader != "" {
		bits = append(bits, "عمود الكمية "+columnPhrase(p.UnitsColumnIndex, p.UnitsColumnHeader, "الكمية"))
	}
	if p.SheetTotalValueColIdx >= 0 || p.SheetTotalValueHeader != "" {
		bits = append(bits, "عمود إجمالي القيمة "+columnPhrase(p.SheetTotalValueColIdx, p.SheetTotalValueHeader, "الإجمالي"))
	}
	if len(bits) == 0 {
		return ""
	}
	return "الموضع: " + strings.Join(bits, "، ") + "."
}

func columnPhrase(idx int, header, fallback string) string {
	label := strings.TrimSpace(header)
	if label == "" {
		label = fallback
	}
	if idx >= 0 {
		return fmt.Sprintf("«%s» (عمود %d)", label, idx+1)
	}
	return fmt.Sprintf("«%s»", label)
}

func containsIssue(issues []string, needle string) bool {
	n := strings.ToLower(needle)
	for _, i := range issues {
		if strings.Contains(strings.ToLower(i), n) {
			return true
		}
	}
	return false
}

func appendUnique(xs []string, s string) []string {
	for _, x := range xs {
		if x == s {
			return xs
		}
	}
	return append(xs, s)
}

func absDiff(a, b float64) float64 {
	return math.Abs(a - b)
}

func rel(a, b float64) float64 {
	if b == 0 {
		if a == 0 {
			return 0
		}
		return 1
	}
	return math.Abs(a-b) / math.Abs(b)
}

// Apply writes ExplanationAR / DiffReasons onto v when Explain produces content.
func Apply(v *domain.IngestionValidation, p Provenance) {
	if v == nil {
		return
	}
	out := Explain(v, p)
	if out.ExplanationAR == "" {
		return
	}
	v.ExplanationAR = out.ExplanationAR
	v.DiffReasons = out.Reasons
}

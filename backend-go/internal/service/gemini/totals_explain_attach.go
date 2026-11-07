package gemini

import (
	"math"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/totalsxplain"
)

// attachTotalsExplanation fills ExplanationAR / DiffReasons without changing honesty status.
func attachTotalsExplanation(v *domain.IngestionValidation, p totalsxplain.Provenance) {
	totalsxplain.Apply(v, p)
}

// provenanceFromPlan builds sheet/column/row context for Arabic totals explanations.
// It inspects mapped columns only; it does not alter extraction or validation thresholds.
func provenanceFromPlan(rows [][]string, plan *ColumnMapPlan) totalsxplain.Provenance {
	p := totalsxplain.Provenance{
		SheetName:             "Sheet1",
		HeaderRowIndex:        -1,
		DataRowFirst:          -1,
		DataRowLast:           -1,
		ValueColumnIndex:      -1,
		UnitsColumnIndex:      -1,
		SheetTotalValueColIdx: -1,
		SheetTotalUnitsColIdx: -1,
	}
	if plan == nil || len(rows) == 0 {
		return p
	}
	p.Layout = plan.Layout
	p.HeaderRowIndex = plan.HeaderRowIndex
	data := rows
	if plan.HeaderRowIndex >= 0 && plan.HeaderRowIndex < len(rows) {
		data = rows[plan.HeaderRowIndex:]
	}
	if len(data) >= 2 {
		p.DataRowFirst = plan.HeaderRowIndex + 1
		p.DataRowLast = plan.HeaderRowIndex + len(data) - 1
	}
	header := data[0]
	cell := func(idx int) string {
		if idx < 0 || idx >= len(header) {
			return ""
		}
		return strings.TrimSpace(header[idx])
	}
	p.SheetTotalValueColIdx = plan.firstIdx(roleTotalValue)
	p.SheetTotalUnitsColIdx = plan.firstIdx(roleTotalQuantity)
	p.SheetTotalValueHeader = cell(p.SheetTotalValueColIdx)
	p.SheetTotalUnitsHeader = cell(p.SheetTotalUnitsColIdx)

	if plan.Layout == "wide" {
		if cols := plan.rolesOf(roleStoreValue); len(cols) > 0 {
			p.ValueColumnIndex = cols[0].Index
			p.ValueColumnHeader = firstNonEmpty(cols[0].Branch, cell(cols[0].Index))
		}
		if cols := plan.rolesOf(roleStoreQuantity); len(cols) > 0 {
			p.UnitsColumnIndex = cols[0].Index
			p.UnitsColumnHeader = firstNonEmpty(cols[0].Branch, cell(cols[0].Index))
		}
	} else {
		p.ValueColumnIndex = plan.firstIdx(roleValue)
		p.UnitsColumnIndex = plan.firstIdx(roleQuantity)
		p.ValueColumnHeader = cell(p.ValueColumnIndex)
		p.UnitsColumnHeader = cell(p.UnitsColumnIndex)
	}

	body := data
	if len(body) > 1 {
		body = body[1:]
	}
	// Count negatives / fractional qty on mapped columns (returns & rounding signals).
	valueIdxs := columnIndexes(plan, roleStoreValue, roleValue)
	unitsIdxs := columnIndexes(plan, roleStoreQuantity, roleQuantity)
	for _, idx := range valueIdxs {
		p.NegativeValueCells += countNegativeCells(body, idx)
	}
	for _, idx := range unitsIdxs {
		p.NegativeUnitsCells += countNegativeCells(body, idx)
		p.FractionalQtyCells += countFractionalCells(body, idx)
	}
	return p
}

func provenanceFromPayload(payload *domain.NormalizedRetailIngestionPayload) totalsxplain.Provenance {
	p := totalsxplain.Provenance{
		HeaderRowIndex:        -1,
		DataRowFirst:          -1,
		DataRowLast:           -1,
		ValueColumnIndex:      -1,
		UnitsColumnIndex:      -1,
		SheetTotalValueColIdx: -1,
		SheetTotalUnitsColIdx: -1,
	}
	if payload == nil {
		return p
	}
	if len(payload.SheetsProcessed) > 0 {
		p.SheetName = payload.SheetsProcessed[0]
	} else if len(payload.DetectedSheets) > 0 {
		p.SheetName = payload.DetectedSheets[0].Name
	}
	if payload.IsWideMatrixWorkbook {
		p.Layout = "wide"
	}
	return p
}

func columnIndexes(plan *ColumnMapPlan, roles ...string) []int {
	seen := map[int]bool{}
	var out []int
	for _, role := range roles {
		for _, c := range plan.rolesOf(role) {
			if c.Index < 0 || seen[c.Index] {
				continue
			}
			seen[c.Index] = true
			out = append(out, c.Index)
		}
	}
	return out
}

func countNegativeCells(rows [][]string, idx int) int {
	if idx < 0 {
		return 0
	}
	n := 0
	for _, r := range rows {
		if parseRevenueFloat(getCell(r, idx)) < 0 {
			n++
		}
	}
	return n
}

func countFractionalCells(rows [][]string, idx int) int {
	if idx < 0 {
		return 0
	}
	n := 0
	for _, r := range rows {
		f := parseRevenueFloat(getCell(r, idx))
		if f == 0 {
			continue
		}
		if f != math.Trunc(f) {
			n++
		}
	}
	return n
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

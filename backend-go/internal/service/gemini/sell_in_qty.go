package gemini

import (
	"math"
	"strings"
)

// ConvertSOPQtyToCases is the official Sell-In carton rule:
//   - CRT/CTN (carton) lines: QTY is already cartons.
//   - Each/piece lines: QTY / U of M2 (units per carton from the file).
//   - If U of M2 is missing on a piece line, fallbackUPC (Product Master UnitsPerCarton)
//     is used and usedFallback is true. No invented pack size (never a default of 12).
//
// Sign is preserved so returns stay negative.
func ConvertSOPQtyToCases(qty, uom2, fallbackUPC float64, uom string) (cases float64, unitsPerCarton int, usedFallback bool) {
	if isCartonUOM(uom) {
		upc := 0
		if uom2 >= 1 {
			upc = int(math.Round(uom2))
		}
		return qty, upc, false
	}
	pack := uom2
	fallback := false
	if pack < 1 && isPieceUOM(uom) && fallbackUPC >= 1 {
		pack = fallbackUPC
		fallback = true
	}
	if pack >= 1 && (isPieceUOM(uom) || strings.TrimSpace(uom) == "") {
		// Empty UOM with a file pack size: treat as pieces / U of M2.
		// Empty UOM without a pack is left as-is (caller may apply PM later only for piece UOM).
		if strings.TrimSpace(uom) == "" && uom2 < 1 {
			return qty, 0, false
		}
		return roundCases(qty / pack), int(math.Round(pack)), fallback
	}
	if isPieceUOM(uom) && pack < 1 {
		return qty, 0, false
	}
	return qty, 0, false
}

func roundCases(v float64) float64 {
	return math.Round(v*10000) / 10000
}

func isCartonUOM(uom string) bool {
	s := normalizeUOM(uom)
	switch s {
	case "CRT", "CTN", "CS", "CASE", "CASES", "CARTON", "CARTONS", "KAR",
		"كرتونة", "كرتونه", "كرتون":
		return true
	}
	return false
}

func isPieceUOM(uom string) bool {
	s := normalizeUOM(uom)
	switch s {
	case "EACH", "EA", "PC", "PCS", "PIECE", "PIECES", "UNIT", "UNITS",
		"قطعة", "قطعه", "حبة", "حبه":
		return true
	}
	return false
}

func normalizeUOM(uom string) string {
	s := strings.TrimSpace(uom)
	s = strings.ReplaceAll(s, ".", "")
	return strings.ToUpper(s)
}

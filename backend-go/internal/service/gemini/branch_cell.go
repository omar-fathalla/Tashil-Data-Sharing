package gemini

import (
	"strings"
	"unicode"
)

// spacedDashSeparators are preferred chain/branch splits (Mohamed's real format).
// Bare dashes are a fallback when spaced forms are absent.
var spacedDashSeparators = []string{" - ", " – ", " — "}
var bareDashSeparators = []string{"-", "–", "—"}

// ParseChainBranchCell splits a store/customer cell into chain (left) and branch (right).
// Split is on the FIRST dash separator so a branch may itself contain dashes, e.g.
// "عائله فتح الله ماركت - دمنهور - الاستاد" → chain="عائله فتح الله ماركت", branch="دمنهور - الاستاد".
// Surrounding whitespace is trimmed and collapsed. When no separator is present the whole
// value is the branch.
func ParseChainBranchCell(raw string) (chain, branch string) {
	s := strings.TrimSpace(normalizeInvisibleSpaces(raw))
	if s == "" {
		return "", ""
	}
	idx, sepLen := firstDashSep(s)
	if idx < 0 {
		return "", collapseSpace(s)
	}
	left := collapseSpace(s[:idx])
	right := collapseSpace(s[idx+sepLen:])
	if right == "" {
		return "", left
	}
	return left, right
}

func firstDashSep(s string) (idx, sepLen int) {
	best := -1
	bestLen := 0
	for _, sep := range spacedDashSeparators {
		if i := strings.Index(s, sep); i >= 0 && (best < 0 || i < best) {
			best, bestLen = i, len(sep)
		}
	}
	if best >= 0 {
		return best, bestLen
	}
	for _, sep := range bareDashSeparators {
		if i := strings.Index(s, sep); i >= 0 && (best < 0 || i < best) {
			best, bestLen = i, len(sep)
		}
	}
	return best, bestLen
}

func collapseSpace(s string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(normalizeInvisibleSpaces(s))), " ")
}

// normalizeArabicLabel applies the project's Arabic grouping norms (ه/ة, أ/ا, ى/ي, tatweel,
// digits, whitespace) so "عائلة" and "عائله" group together.
func normalizeArabicLabel(s string) string {
	s = collapseSpace(s)
	s = normalizeArabicDigitsToASCII(s)
	s = strings.Map(func(r rune) rune {
		switch r {
		case 'ـ':
			return -1
		case 'أ', 'إ', 'آ':
			return 'ا'
		case 'ى':
			return 'ي'
		case 'ة':
			return 'ه'
		default:
			if unicode.IsSpace(r) {
				return ' '
			}
			return r
		}
	}, s)
	return strings.Join(strings.Fields(s), " ")
}

func normalizeInvisibleSpaces(s string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case '\u00a0', '\u2007', '\u202f', '\u2009', '\u2008', '\u200a':
			return ' '
		case '\r', '\n', '\t':
			return ' '
		default:
			return r
		}
	}, s)
}

// branchGroupKey is the Arabic-normalized branch label used for distinct-branch grouping.
func branchGroupKey(raw string) string {
	_, branch := ParseChainBranchCell(raw)
	if branch == "" {
		branch = collapseSpace(raw)
	}
	return strings.ToLower(normalizeArabicLabel(branch))
}

// resolveChainCodeFromCustomerLabel maps the left-hand chain/customer label to a retailer
// chain code. Mirrors the unambiguous built-in Sell-In customer→chain needles.
func resolveChainCodeFromCustomerLabel(label, fallback string) string {
	n := strings.ToLower(normalizeArabicLabel(label))
	fb := strings.ToLower(strings.TrimSpace(fallback))
	if n == "" {
		return fb
	}
	rules := []struct{ needle, chain string }{
		{"بيت الجمله", "beet-elgomla"},
		{"عائله فتح الله ماركت", "fathalla"},
		{"فتح الله اسواق", "fathalla"},
		{"فتح الله جمله", "fathalla"},
		{"جمله ماركت", "gomla"},
		{"كارفور", "carrefour"},
		{"سبينيس", "spinneys"},
		{"كازيون", "kazyon"},
	}
	for _, r := range rules {
		if strings.Contains(n, r.needle) {
			return r.chain
		}
	}
	return fb
}

// applySectionHeaderStoreFill carries a branch/section header row forward into following
// data rows whose store cell is blank. A section header is a row with a non-empty store
// cell and no barcode / quantity / value signal.
func applySectionHeaderStoreFill(dataRows [][]string, storeIdx, barcodeIdx, qtyIdx, valueIdx int) {
	if storeIdx < 0 || len(dataRows) == 0 {
		return
	}
	current := ""
	for i, r := range dataRows {
		if isRowEmpty(r) {
			continue
		}
		store := strings.TrimSpace(getCell(r, storeIdx))
		hasSignal := false
		for _, idx := range []int{barcodeIdx, qtyIdx, valueIdx} {
			if idx >= 0 && strings.TrimSpace(getCell(r, idx)) != "" {
				hasSignal = true
				break
			}
		}
		if store != "" && !hasSignal {
			current = store
			continue
		}
		if store == "" && current != "" && hasSignal {
			ensureCol(dataRows, i, storeIdx, current)
		} else if store != "" {
			current = store
		}
	}
}

func ensureCol(rows [][]string, rowIdx, colIdx int, val string) {
	if rowIdx < 0 || rowIdx >= len(rows) || colIdx < 0 {
		return
	}
	r := rows[rowIdx]
	for len(r) <= colIdx {
		r = append(r, "")
	}
	r[colIdx] = val
	rows[rowIdx] = r
}

// collectDistinctBranches scans every data row of the store/customer column and returns
// distinct display values (full cell, whitespace-collapsed). Never inferred from a leading
// sample alone. Arabic-normalized keys collapse ه/ة spelling variants of the same cell.
func collectDistinctBranches(dataRows [][]string, storeIdx int) []string {
	if storeIdx < 0 {
		return nil
	}
	order := make([]string, 0)
	seen := map[string]string{}
	for _, r := range dataRows {
		if isRowEmpty(r) {
			continue
		}
		raw := collapseSpace(getCell(r, storeIdx))
		if raw == "" {
			continue
		}
		key := strings.ToLower(normalizeArabicLabel(raw))
		if key == "" {
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = raw
		order = append(order, raw)
	}
	return order
}

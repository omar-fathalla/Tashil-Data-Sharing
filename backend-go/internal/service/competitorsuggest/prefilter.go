package competitorsuggest

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// SizeBand is the soft similarity band for parsed pack sizes (bonus only).
// Candidates are never dropped solely for size mismatch or missing size tokens
// (~76% of competitor names in Sell-Out have no size token).
const (
	SizeBandMin = 0.5
	SizeBandMax = 2.0
	MaxRank     = 3
)

// SkuCandidate is one Sell-Out / custom competitor row used as a ranking candidate.
type SkuCandidate struct {
	Barcode    string
	SKUName    string
	Category   string
	Supplier   string
	Brand      string
	UnitPrice  float64
	Units      int
	IsOwnBrand bool
	IsCustom   bool // existing custom_competitor_skus row
}

// PrefScore is the deterministic pre-AI score for one candidate vs an own SKU.
type PrefScore struct {
	Candidate     SkuCandidate
	SizeParsed    bool
	SizeSimilar   bool
	SizeLabelOwn  string
	SizeLabelCand string
	VariantBonus  bool
	Score         float64
}

// CategoryEquivalence is an owner-editable map of alias → canonical category.
// Default is empty (exact match only after NormalizeProductCategory). Never auto-merge
// live spelling variants without an explicit entry Mohamed approved.
type CategoryEquivalence map[string]string

// CanonicalCategory applies NormalizeProductCategory then optional owner equivalence.
func CanonicalCategory(raw string, eq CategoryEquivalence) string {
	norm := domain.NormalizeProductCategory(raw)
	if norm == "" {
		return ""
	}
	if eq != nil {
		if canon, ok := eq[norm]; ok && strings.TrimSpace(canon) != "" {
			return strings.TrimSpace(canon)
		}
		if canon, ok := eq[raw]; ok && strings.TrimSpace(canon) != "" {
			return strings.TrimSpace(canon)
		}
	}
	return norm
}

// SameCategory reports whether own and candidate share a category under eq.
func SameCategory(ownCat, candCat string, eq CategoryEquivalence) bool {
	a := CanonicalCategory(ownCat, eq)
	b := CanonicalCategory(candCat, eq)
	if a == "" || b == "" {
		return false
	}
	return a == b
}

var sizeTokenRe = regexp.MustCompile(`(?i)(\d+(?:[.,]\d+)?)\s*(كجم|كيلو|كغ|kg|جم|جرام|g|لتر|لت|ل\b|L|ml|مل)`)

// ParsedSize is a pack size extracted from a SKU name (grams or millilitres base).
type ParsedSize struct {
	Value float64 // base units: grams or ml
	Unit  string  // "g" or "ml"
	Label string  // original matched label e.g. "3 كجم"
}

// ParseSizeFromName extracts the first size token from a SKU name.
// Missing tokens are common — callers treat size as a soft bonus, never a hard filter.
func ParseSizeFromName(name string) (ParsedSize, bool) {
	m := sizeTokenRe.FindStringSubmatch(name)
	if len(m) < 3 {
		return ParsedSize{}, false
	}
	numStr := strings.ReplaceAll(m[1], ",", ".")
	n, err := strconv.ParseFloat(numStr, 64)
	if err != nil || n <= 0 {
		return ParsedSize{}, false
	}
	unitRaw := strings.ToLower(strings.TrimSpace(m[2]))
	label := strings.TrimSpace(m[0])
	switch unitRaw {
	case "كجم", "كيلو", "كغ", "kg":
		return ParsedSize{Value: n * 1000, Unit: "g", Label: label}, true
	case "جم", "جرام", "g":
		return ParsedSize{Value: n, Unit: "g", Label: label}, true
	case "لتر", "لت", "ل", "l":
		return ParsedSize{Value: n * 1000, Unit: "ml", Label: label}, true
	case "مل", "ml":
		return ParsedSize{Value: n, Unit: "ml", Label: label}, true
	default:
		return ParsedSize{}, false
	}
}

// SizeSimilar returns whether two parsed sizes fall inside the soft band (ratio ≤ 2×).
func SizeSimilar(a, b ParsedSize) bool {
	if a.Value <= 0 || b.Value <= 0 {
		return false
	}
	ratio := a.Value / b.Value
	if ratio < 1 {
		ratio = 1 / ratio
	}
	return ratio <= SizeBandMax
}

var scentTokens = []string{
	"ليمون", "lemon", "لافندر", "lavender", "ورد", "rose",
	"تفاح", "apple", "صنوبر", "pine", "ياسمين",
	"بلس", "plus", "جل", "جيل", "gel", "سائل", "اوتوماتيك", "اتوماتيك", "يدوى", "يدوي",
}

// VariantBonus reports a soft match on shared scent/variant tokens in both names.
func VariantBonus(ownName, candName string) bool {
	o := strings.ToLower(ownName)
	c := strings.ToLower(candName)
	for _, tok := range scentTokens {
		t := strings.ToLower(tok)
		if strings.Contains(o, t) && strings.Contains(c, t) {
			return true
		}
	}
	return false
}

// PreFilterCandidates keeps same-category non-own candidates. Size is a soft bonus,
// never a hard drop. Own SKUs and empty barcodes are excluded.
func PreFilterCandidates(own SkuCandidate, pool []SkuCandidate, eq CategoryEquivalence) []PrefScore {
	out := make([]PrefScore, 0)
	ownSize, ownOK := ParseSizeFromName(own.SKUName)
	for _, cand := range pool {
		if cand.IsOwnBrand {
			continue
		}
		if strings.TrimSpace(cand.Barcode) == "" {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(cand.Barcode), strings.TrimSpace(own.Barcode)) {
			continue
		}
		if !SameCategory(own.Category, cand.Category, eq) {
			continue
		}
		ps := PrefScore{Candidate: cand, SizeLabelOwn: ownSize.Label}
		candSize, candOK := ParseSizeFromName(cand.SKUName)
		ps.SizeLabelCand = candSize.Label
		ps.SizeParsed = ownOK && candOK
		if ps.SizeParsed && SizeSimilar(ownSize, candSize) {
			ps.SizeSimilar = true
			ps.Score += 2
		}
		if VariantBonus(own.SKUName, cand.SKUName) {
			ps.VariantBonus = true
			ps.Score += 1.5
		}
		if cand.Units > 0 {
			ps.Score += 0.1
		}
		if cand.IsCustom {
			ps.Score += 0.25
		}
		out = append(out, ps)
	}
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j].Score > out[i].Score ||
				(out[j].Score == out[i].Score && out[j].Candidate.Barcode < out[i].Candidate.Barcode) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

// DetectedCategoryVariants returns pairs of live categories that look related
// (shared stem tokens) but are NOT equivalent under eq — for owner review only.
// Never auto-merged.
func DetectedCategoryVariants(categories []string, eq CategoryEquivalence) [][2]string {
	canon := make([]string, 0, len(categories))
	seen := map[string]bool{}
	for _, c := range categories {
		n := CanonicalCategory(c, eq)
		if n == "" || seen[n] {
			continue
		}
		seen[n] = true
		canon = append(canon, n)
	}
	var pairs [][2]string
	for i := 0; i < len(canon); i++ {
		for j := i + 1; j < len(canon); j++ {
			if relatedCategoryNames(canon[i], canon[j]) {
				pairs = append(pairs, [2]string{canon[i], canon[j]})
			}
		}
	}
	return pairs
}

func relatedCategoryNames(a, b string) bool {
	if a == b {
		return false
	}
	ta := categoryTokens(a)
	tb := categoryTokens(b)
	if len(ta) == 0 || len(tb) == 0 {
		return false
	}
	shared := 0
	for t := range ta {
		if tb[t] {
			shared++
		}
	}
	return shared >= 2
}

func categoryTokens(s string) map[string]bool {
	out := map[string]bool{}
	for _, p := range strings.Fields(s) {
		p = strings.TrimSpace(p)
		if len([]rune(p)) < 2 {
			continue
		}
		out[p] = true
	}
	return out
}

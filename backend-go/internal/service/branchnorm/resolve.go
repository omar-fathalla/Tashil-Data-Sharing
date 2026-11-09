package branchnorm

import (
	"fmt"
	"strings"
)

// Match kinds reported on Result.MatchKind and Summary counters.
const (
	KindExact   = "exact"
	KindAlias   = "alias"
	KindEnglish = "english"
	KindAbbrev  = "abbrev"
	KindUnknown = "unknown"
)

// Result is one raw → canonical resolution.
type Result struct {
	Raw         string  `json:"raw"`
	CanonicalAR string  `json:"canonical_ar"`
	CanonicalEN string  `json:"canonical_en,omitempty"`
	Slug        string  `json:"slug,omitempty"`
	Governorate string  `json:"governorate,omitempty"`
	City        string  `json:"city,omitempty"`
	Confidence  float64 `json:"confidence"`
	MatchKind   string  `json:"match_kind"`
	ReasonAR    string  `json:"reason_ar"`
	Changed     bool    `json:"changed"`
}

// Summary aggregates batch normalization for Arabic UI / success metrics.
type Summary struct {
	Total       int    `json:"total"`
	Exact       int    `json:"exact"`
	Alias       int    `json:"alias"`
	English     int    `json:"english"`
	Abbrev      int    `json:"abbrev"`
	Unknown     int    `json:"unknown"`
	Changed     int    `json:"changed"`
	UniqueRaw   int    `json:"unique_raw"`
	UniqueCanon int    `json:"unique_canon"`
	SummaryAR   string `json:"summary_ar"`
	Samples     []Result `json:"samples,omitempty"` // up to a few changed rows for UI
}

// Resolve maps one raw branch label to a canonical form.
// Empty input returns KindUnknown with empty canonical (caller may default).
func Resolve(raw string) Result {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return Result{
			Raw:        raw,
			MatchKind:  KindUnknown,
			Confidence: 0,
			ReasonAR:   "اسم الفرع فارغ — لم يتم التوحيد.",
		}
	}

	stripped := stripChainPrefixes(trimmed)
	key := Key(trimmed)
	entry, ok := byKey[key]
	if !ok {
		// Try again after abbreviation expansion only (Key already expands,
		// but keep a second pass on stripped text for clarity).
		key2 := Key(stripped)
		entry, ok = byKey[key2]
		key = key2
	}

	if !ok {
		return Result{
			Raw:         trimmed,
			CanonicalAR: stripped,
			Confidence:  0.35,
			MatchKind:   KindUnknown,
			ReasonAR:    fmt.Sprintf("لم يُعرف الفرع «%s» في القاموس — سيُنشأ تلقائياً.", stripped),
			Changed:     stripped != trimmed,
		}
	}

	kind, conf, reason := classify(trimmed, stripped, entry)
	return Result{
		Raw:         trimmed,
		CanonicalAR: entry.CanonicalAR,
		CanonicalEN: entry.CanonicalEN,
		Slug:        entry.Slug,
		Governorate: entry.Governorate,
		City:        entry.City,
		Confidence:  conf,
		MatchKind:   kind,
		ReasonAR:    reason,
		Changed:     !sameDisplay(trimmed, entry.CanonicalAR),
	}
}

func sameDisplay(raw, canon string) bool {
	return Key(raw) == Key(canon) && !looksLatin(raw)
}

func looksLatin(s string) bool {
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
			return true
		}
	}
	return false
}

func looksAbbrev(raw string) bool {
	lower := strings.ToLower(strings.TrimSpace(raw))
	if strings.HasPrefix(lower, "فر.") || strings.HasPrefix(lower, "فر ") || strings.HasPrefix(lower, "فر-") {
		return true
	}
	if strings.Contains(lower, "br.") {
		return true
	}
	fields := strings.FieldsFunc(raw, func(r rune) bool {
		return r == ' ' || r == '-' || r == '_' || r == '/' || r == '.'
	})
	for _, f := range fields {
		bare := strings.ToLower(strings.TrimSuffix(f, "."))
		if _, ok := tokenAbbrev[bare]; ok {
			return true
		}
		// Lone short latin tokens like "Oct" / "Gdn" / "Smh"
		if len(bare) <= 3 && looksLatin(bare) {
			if _, ok := byKey[Key(bare)]; ok {
				return true
			}
		}
	}
	return false
}

func classify(raw, stripped string, entry Entry) (kind string, conf float64, reason string) {
	rawKey := Key(raw)
	canonKey := Key(entry.CanonicalAR)
	enKey := Key(entry.CanonicalEN)

	if rawKey == canonKey && !looksLatin(raw) && !looksAbbrev(raw) {
		return KindExact, 1.0, fmt.Sprintf("الاسم مطابق للمعتمد: %s.", entry.CanonicalAR)
	}
	if looksAbbrev(raw) {
		return KindAbbrev, 0.96, fmt.Sprintf("اختصار «%s» وُحِّد إلى «%s».", stripped, entry.CanonicalAR)
	}
	if looksLatin(raw) || rawKey == enKey {
		return KindEnglish, 0.95, fmt.Sprintf("الاسم الإنجليزي «%s» وُحِّد إلى «%s».", stripped, entry.CanonicalAR)
	}
	return KindAlias, 0.93, fmt.Sprintf("التهجئة «%s» وُحِّدت إلى الاسم المعتمد «%s».", stripped, entry.CanonicalAR)
}

// ResolveMany resolves each raw name (order preserved) and builds a Summary.
func ResolveMany(rawNames []string) (results []Result, summary Summary) {
	results = make([]Result, 0, len(rawNames))
	seenRaw := map[string]struct{}{}
	seenCanon := map[string]struct{}{}
	for _, raw := range rawNames {
		r := Resolve(raw)
		results = append(results, r)
		summary.Total++
		switch r.MatchKind {
		case KindExact:
			summary.Exact++
		case KindAlias:
			summary.Alias++
		case KindEnglish:
			summary.English++
		case KindAbbrev:
			summary.Abbrev++
		default:
			summary.Unknown++
		}
		if r.Changed {
			summary.Changed++
			if len(summary.Samples) < 5 {
				summary.Samples = append(summary.Samples, r)
			}
		}
		if k := strings.TrimSpace(r.Raw); k != "" {
			seenRaw[Key(k)] = struct{}{}
		}
		if k := strings.TrimSpace(r.CanonicalAR); k != "" {
			seenCanon[Key(k)] = struct{}{}
		}
	}
	summary.UniqueRaw = len(seenRaw)
	summary.UniqueCanon = len(seenCanon)
	summary.SummaryAR = summary.BuildArabic()
	return results, summary
}

// BuildArabic returns a one-line Arabic success-metrics sentence.
func (s Summary) BuildArabic() string {
	if s.Total == 0 {
		return "لا توجد أسماء فروع لتوحيدها."
	}
	known := s.Exact + s.Alias + s.English + s.Abbrev
	parts := []string{
		fmt.Sprintf("توحيد الفروع: %d/%d معروف", known, s.Total),
	}
	if s.English > 0 {
		parts = append(parts, fmt.Sprintf("%d إنجليزي", s.English))
	}
	if s.Abbrev > 0 {
		parts = append(parts, fmt.Sprintf("%d اختصار", s.Abbrev))
	}
	if s.Alias > 0 {
		parts = append(parts, fmt.Sprintf("%d تهجئة بديلة", s.Alias))
	}
	if s.Changed > 0 {
		parts = append(parts, fmt.Sprintf("%d تغيّر عرضها", s.Changed))
	}
	if s.Unknown > 0 {
		parts = append(parts, fmt.Sprintf("%d غير معروف", s.Unknown))
	}
	if s.UniqueCanon > 0 && s.UniqueRaw > s.UniqueCanon {
		parts = append(parts, fmt.Sprintf("دُمجت إلى %d اسم معتمد", s.UniqueCanon))
	}
	return strings.Join(parts, " • ")
}

// CatalogSize exposes dictionary size for metrics/tests.
func CatalogSize() int { return len(catalog) }

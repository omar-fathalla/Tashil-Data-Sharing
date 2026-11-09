package branchmaster

import "unicode/utf8"

// Confidence thresholds for auto-link vs pending.
const (
	HighConfidenceMin = 0.92
	AmbiguousGapMax   = 0.05 // top two within this gap → ambiguous
	LowConfidenceMin  = 0.55
)

// Similarity is 1 - normalized Levenshtein distance over runes of Normalize(a/b).
func Similarity(a, b string) float64 {
	na, nb := Normalize(a), Normalize(b)
	if na == "" && nb == "" {
		return 1
	}
	if na == "" || nb == "" {
		return 0
	}
	if na == nb {
		return 1
	}
	ra, rb := []rune(na), []rune(nb)
	prev := make([]int, len(rb)+1)
	cur := make([]int, len(rb)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(ra); i++ {
		cur[0] = i
		for j := 1; j <= len(rb); j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			del := prev[j] + 1
			ins := cur[j-1] + 1
			sub := prev[j-1] + cost
			cur[j] = del
			if ins < cur[j] {
				cur[j] = ins
			}
			if sub < cur[j] {
				cur[j] = sub
			}
		}
		prev, cur = cur, prev
	}
	m := len(ra)
	if len(rb) > m {
		m = len(rb)
	}
	if m == 0 {
		return 1
	}
	return 1 - float64(prev[len(rb)])/float64(m)
}

// ContainsBoost bumps score when one normalized name contains the other
// (e.g. "دمنهور" vs "دمنهور الاستاد") — used only as a ranking hint; the
// AmbiguousGapMax check still forces PENDING when two candidates are close.
func ContainsBoost(a, b string) float64 {
	na, nb := Normalize(a), Normalize(b)
	if na == "" || nb == "" || na == nb {
		return 0
	}
	if stringsContainsNorm(na, nb) || stringsContainsNorm(nb, na) {
		// Prefer the longer (more specific) as the intended match by returning
		// a small boost only — never enough alone to auto-link past HighMin.
		return 0.04
	}
	return 0
}

func stringsContainsNorm(a, b string) bool {
	return len(a) >= len(b) && (a == b || (len(b) >= 3 && containsRunes(a, b)))
}

func containsRunes(hay, needle string) bool {
	return len(hay) >= len(needle) && (hay == needle || indexNorm(hay, needle) >= 0)
}

func indexNorm(hay, needle string) int {
	// simple substring on already-normalized strings
	hr, nr := []rune(hay), []rune(needle)
	if len(nr) == 0 || len(nr) > len(hr) {
		return -1
	}
	for i := 0; i+len(nr) <= len(hr); i++ {
		ok := true
		for j := range nr {
			if hr[i+j] != nr[j] {
				ok = false
				break
			}
		}
		if ok {
			return i
		}
	}
	return -1
}

// RuneLen is exposed for tests.
func RuneLen(s string) int { return utf8.RuneCountInString(s) }

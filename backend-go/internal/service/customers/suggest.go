package customers

import (
	"strings"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// Suggestion is advisory only: it is shown to the admin and never attaches rows.
type Suggestion struct {
	Name   string
	Chain  string
	Reason string
}

// familyPrefix is the part before the first " - " (the customer group), e.g. "فتح الله اسواق".
func familyPrefix(key string) string {
	if i := strings.Index(key, " - "); i > 0 {
		return strings.TrimSpace(key[:i])
	}
	return key
}

// SuggestionChain is the chain an approved entry's rows are served under: the chain chosen on
// approval, else the upload chain, else (seed names, all served from Fathalla uploads) the
// customer->chain rules applied to "fathalla". "" means unknown; such entries are never suggested.
func SuggestionChain(e Entry) string {
	if c := strings.ToLower(strings.TrimSpace(e.Chain)); c != "" {
		return c
	}
	if c := strings.TrimSpace(e.UploadChain); c != "" {
		return strings.ToLower(bigquery.ResolveSellInChain(e.Name, c))
	}
	if e.Seeded {
		return strings.ToLower(bigquery.ResolveSellInChain(e.Name, "fathalla"))
	}
	return ""
}

// Suggest returns the closest approved name of the SAME chain (rule 1: a suggestion never crosses
// customers/chains), preferring the same family prefix, then string similarity. An empty chain gets
// no suggestion.
func Suggest(name, chain string, approved []Entry) Suggestion {
	key := NormalizeName(name)
	fam := familyPrefix(key)
	chain = strings.ToLower(strings.TrimSpace(chain))
	best, bestScore := -1, 0.0
	for i, e := range approved {
		if chain == "" || SuggestionChain(e) != chain {
			continue
		}
		s := similarity(key, e.Key)
		if familyPrefix(e.Key) == fam && fam != key {
			s += 0.5
		}
		if s > bestScore {
			best, bestScore = i, s
		}
	}
	if best < 0 || bestScore < 0.55 {
		return Suggestion{Reason: "مفيش اسم معتمد قريب؛ محتاج تحديد يدوي"}
	}
	e := approved[best]
	reason := "اسم قريب من عميل معتمد (اقتراح فقط، مش هيتضاف غير بعد موافقتك)"
	if familyPrefix(e.Key) == fam && fam != key {
		reason = "نفس مجموعة العميل «" + fam + "» لكن فرع جديد (اقتراح فقط)"
	}
	return Suggestion{Name: e.Name, Chain: e.Chain, Reason: reason}
}

// similarity is 1 - normalized Levenshtein distance over runes.
func similarity(a, b string) float64 {
	ra, rb := []rune(a), []rune(b)
	if len(ra) == 0 && len(rb) == 0 {
		return 1
	}
	prev := make([]int, len(rb)+1)
	cur := make([]int, len(rb)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(ra); i++ {
		cur[0] = i
		for j := 1; j <= len(rb); j++ {
			c := 1
			if ra[i-1] == rb[j-1] {
				c = 0
			}
			cur[j] = min(prev[j]+1, cur[j-1]+1, prev[j-1]+c)
		}
		prev, cur = cur, prev
	}
	m := len(ra)
	if len(rb) > m {
		m = len(rb)
	}
	return 1 - float64(prev[len(rb)])/float64(m)
}

package matcher

import (
	"strings"
	"unicode"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func cleanBarcode(raw string) string {
	return domain.CleanBarcode(raw)
}

func normalizeItemCode(code string) string {
	return domain.NormalizeItemCode(code)
}

func normalizeArabicName(s string) string {
	s = strings.ToLower(strings.TrimSpace(strings.TrimLeft(s, "* ")))
	r := strings.NewReplacer(
		"أ", "ا",
		"إ", "ا",
		"آ", "ا",
		"ى", "ي",
		"ة", "ه",
		"ڤ", "ف",
		"ؤ", "و",
		"ئ", "ي",
	)
	s = r.Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

func tokenizeArabic(raw string) []string {
	norm := normalizeArabicName(raw)
	if norm == "" {
		return nil
	}
	var out []string
	var b strings.Builder
	flush := func() {
		if b.Len() == 0 {
			return
		}
		tok := b.String()
		b.Reset()
		if len([]rune(tok)) < 2 {
			return
		}
		out = append(out, tok)
	}
	for _, r := range norm {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
			continue
		}
		flush()
	}
	flush()
	return out
}

var stopWords = map[string]bool{
	"منظف": true, "غسيل": true, "عبوه": true, "عبوة": true, "جديد": true,
	"سائل": true, "شركه": true, "ادكو": true, "لتر": true, "جم": true,
	"كجم": true, "مل": true, "عادي": true, "عادى": true, "قطعه": true, "عدد": true,
	"من": true, "علي": true, "مع": true, "في": true, "و": true,
}

func coreTokens(tokens []string) []string {
	out := make([]string, 0, len(tokens))
	for _, t := range tokens {
		if stopWords[t] {
			continue
		}
		out = append(out, t)
	}
	return out
}

// jaccard is set-based: repeated tokens in either slice do not inflate the score.
// Intersection and union count unique tokens only.
func jaccard(a, b []string) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	setA := make(map[string]struct{}, len(a))
	for _, t := range a {
		setA[t] = struct{}{}
	}
	setB := make(map[string]struct{}, len(b))
	for _, t := range b {
		setB[t] = struct{}{}
	}
	inter := 0
	for t := range setA {
		if _, ok := setB[t]; ok {
			inter++
		}
	}
	union := len(setA) + len(setB) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

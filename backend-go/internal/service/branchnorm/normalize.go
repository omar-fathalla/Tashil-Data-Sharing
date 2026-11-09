// Package branchnorm maps raw retail branch names (Arabic/English abbreviations
// and spelling variants) to a canonical Arabic short name + frozen store slug.
// It does not invent barcodes, write production data, or change Gemini honesty thresholds.
package branchnorm

import (
	"strings"
	"unicode"
)

// Key builds a comparable key: strip chain prefixes, unify Arabic letters,
// drop spaces/punctuation, and lower-case Latin.
func Key(s string) string {
	cleaned := stripChainPrefixes(strings.TrimSpace(s))
	cleaned = expandTokenAbbreviations(cleaned)
	replacer := strings.NewReplacer(
		" ", "",
		"-", "",
		"_", "",
		".", "",
		"،", "",
		",", "",
		"/", "",
		"\\", "",
		"ـ", "",
		"أ", "ا",
		"إ", "ا",
		"آ", "ا",
		"ى", "ي",
		"ة", "ه",
		"ؤ", "و",
		"ئ", "ي",
		"ڤ", "ف",
	)
	return strings.ToLower(replacer.Replace(cleaned))
}

func stripChainPrefixes(s string) string {
	cleaned := strings.TrimSpace(s)
	prefixes := []string{
		"فرع فتح الله -", "فرع فتح الله",
		"فرع كارفور -", "فرع كارفور",
		"فرع جملة ماركت -", "فرع جملة ماركت",
		"فرع بيت الجملة -", "فرع بيت الجملة",
		"فرع سبينيس -", "فرع سبينيس",
		"فرع مترو -", "فرع مترو",
		"فرع سعودي -", "فرع سعودي",
		"فرع كازيون -", "فرع كازيون",
		"فتح الله جملة ماركت -", "فتح الله جملة ماركت",
		"فتح الله -", "كارفور -",
		"fathalla -", "fathalla",
		"carrefour -", "carrefour",
		"gomla market -", "gomla -", "gomla",
		"spinneys -", "spinneys",
		"branch -", "br.", "br ",
		"فرع -", "فرع",
	}
	lower := strings.ToLower(cleaned)
	for _, p := range prefixes {
		pl := strings.ToLower(p)
		if strings.HasPrefix(lower, pl) {
			cleaned = strings.TrimSpace(cleaned[len(p):])
			lower = strings.ToLower(cleaned)
		}
	}
	// Leading "فر." / "فر " abbreviation for فرع
	for _, p := range []string{"فر.", "فر ", "فر-"} {
		if strings.HasPrefix(cleaned, p) {
			cleaned = strings.TrimSpace(cleaned[len(p):])
		}
	}
	return strings.TrimSpace(cleaned)
}

// expandTokenAbbreviations rewrites common short tokens inside a branch label
// (kept space-separated so Key can still collapse them).
func expandTokenAbbreviations(s string) string {
	fields := strings.FieldsFunc(s, func(r rune) bool {
		return unicode.IsSpace(r) || r == '-' || r == '_' || r == '/'
	})
	if len(fields) == 0 {
		return s
	}
	out := make([]string, 0, len(fields))
	for _, f := range fields {
		out = append(out, expandOneToken(f))
	}
	return strings.Join(out, " ")
}

func expandOneToken(tok string) string {
	t := strings.TrimSpace(tok)
	if t == "" {
		return t
	}
	// Strip trailing period used in Latin abbreviations (St. Mn. Oct.).
	bare := strings.TrimSuffix(t, ".")
	key := strings.ToLower(bare)
	if mapped, ok := tokenAbbrev[key]; ok {
		return mapped
	}
	// Arabic short forms without spaces already handled via alias table;
	// keep original token otherwise.
	return t
}

// tokenAbbrev maps short English/Arabic tokens → canonical Arabic fragments.
// tokenAbbrev only expands *short* codes. Full English names (Smouha, Stanley, …)
// resolve via the catalog / alias table so Key("Stanley") stays latin until lookup.
var tokenAbbrev = map[string]string{
	"smh":  "سموحة",
	"gdn":  "جاردينيا",
	"gard": "جاردينيا",
	"oct":  "أكتوبر",
	"6oct": "أكتوبر",
	"mini": "ميني",
	"mn":   "ميني",
	"ميني": "ميني",
}

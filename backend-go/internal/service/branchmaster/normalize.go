// Package branchmaster is the per-tenant master of retail chains, branches, and
// raw-name aliases. Mapping is a query/report-time layer: raw store names in
// Sell-Out / Sell-In / Returns facts are never rewritten.
package branchmaster

import (
	"strings"
	"unicode"
)

// UnallocatedBranchName is the synthetic Sell-Out reconciliation bucket (#49).
// It always stays its own bucket and is never auto-linked to a real branch.
// Must stay identical to gemini.UnallocatedBranchName.
const UnallocatedBranchName = "غير موزع على فرع"

// Normalize builds a stable comparison key:
// strip chain prefixes/separators; Arabic أ/إ/آ→ا, ة→ه, ى→ي; whitespace; digits.
// Trailing branch numbers keep their value: كفر الدوار ≠ كفر الدوار 2 ≠ الغردقة 2,
// but whitespace-only variants of the SAME number merge (كفر الدوار 2 = كفر الدوار2).
func Normalize(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	s = stripChainPrefix(s)
	s = unifyArabic(s)
	s = unifyDigits(s)
	// Collapse separators to spaces, then fields.
	var b strings.Builder
	b.Grow(len(s))
	prevSpace := false
	for _, r := range s {
		switch {
		case r == '-' || r == '_' || r == '/' || r == '\\' || r == '.' || r == '،' || r == ',' || r == 'ـ' || r == '–' || r == '—':
			if !prevSpace {
				b.WriteByte(' ')
				prevSpace = true
			}
		case unicode.IsSpace(r):
			if !prevSpace {
				b.WriteByte(' ')
				prevSpace = true
			}
		default:
			b.WriteRune(unicode.ToLower(r))
			prevSpace = false
		}
	}
	s = strings.Join(strings.Fields(b.String()), " ")
	return unifyTrailingNumberSpacing(s)
}

// unifyTrailingNumberSpacing inserts a single space before a trailing number when it
// was glued to letters (كفر الدوار2 → كفر الدوار 2). Different numbers stay different.
func unifyTrailingNumberSpacing(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	runes := []rune(s)
	// Find trailing digit run.
	i := len(runes) - 1
	for i >= 0 && runes[i] >= '0' && runes[i] <= '9' {
		i--
	}
	if i < 0 || i == len(runes)-1 {
		return s // no trailing digits, or entire string is digits
	}
	// i points at last non-digit. If it is not already a space, insert one.
	if unicode.IsSpace(runes[i]) {
		// Normalize multiple spaces before the number to one (already collapsed).
		return s
	}
	return string(runes[:i+1]) + " " + string(runes[i+1:])
}

// ShortDisplay strips the chain prefix for a human-facing short branch name.
func ShortDisplay(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" {
		return s
	}
	if IsUnallocated(s) {
		return UnallocatedBranchName
	}
	s = stripChainPrefix(s)
	s = strings.TrimSpace(s)
	if s == "" {
		return strings.TrimSpace(raw)
	}
	// Prefer branchnorm-style short Arabic when the remainder still has leading "فرع".
	s = strings.TrimPrefix(s, "فرع")
	s = strings.TrimSpace(strings.TrimPrefix(s, "-"))
	return strings.Join(strings.Fields(s), " ")
}

// IsUnallocated reports the synthetic unallocated bucket (never auto-linked).
func IsUnallocated(name string) bool {
	return Normalize(name) == Normalize(UnallocatedBranchName)
}

func unifyArabic(s string) string {
	return strings.NewReplacer(
		"أ", "ا",
		"إ", "ا",
		"آ", "ا",
		"ى", "ي",
		"ة", "ه",
		"ؤ", "و",
		"ئ", "ي",
		"ڤ", "ف",
		"گ", "ك",
	).Replace(s)
}

func unifyDigits(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		switch {
		case r >= '٠' && r <= '٩':
			b.WriteRune('0' + (r - '٠'))
		case r >= '۰' && r <= '۹':
			b.WriteRune('0' + (r - '۰'))
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

// stripChainPrefix removes known chain banners / "فرع …" wrappers so aliases
// across Sell-Out and Sell-In collapse (e.g. "عائلة فتح الله ماركت - سموحة" → "سموحة").
func stripChainPrefix(s string) string {
	cleaned := strings.TrimSpace(s)
	original := cleaned
	prefixes := []string{
		// Longest legal-entity banners FIRST so "عائله فتح الله ماركت لتصنيع…" is not
		// truncated by the shorter "عائله فتح الله ماركت" grocery prefix.
		"عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م -",
		"عائلة فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م -",
		"عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م",
		"عائلة فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م",
		"فتح الله بيت الجمله للتجاره والتوريدات ش م م -",
		"فتح الله بيت الجملة للتجاره والتوريدات ش م م -",
		"فتح الله بيت الجمله للتجاره والتوريدات ش م م",
		"فتح الله بيت الجملة للتجاره والتوريدات ش م م",
		// Care-line (مواد عناية) before grocery so both collapse to the same short name
		// (owner still decides whether that merge is correct — dry-run flags PENDING).
		"عائله فتح الله ماركت مواد عناية -",
		"عائلة فتح الله ماركت مواد عناية -",
		"عائله فتح الله ماركت مواد عناية",
		"عائلة فتح الله ماركت مواد عناية",
		"عائله فتح الله ماركت -",
		"عائلة فتح الله ماركت -",
		"عائله فتح الله ماركت",
		"عائلة فتح الله ماركت",
		// Legacy KH Gomla Market spellings (not present in current live Adeco BQ).
		"فرع فتح الله - كيه اتش جمله ماركت مواد عناية -",
		"فرع فتح الله - كيه اتش جملة ماركت مواد عناية -",
		"فرع فتح الله - كيه اتش جمله ماركت -",
		"فرع فتح الله - كيه اتش جملة ماركت -",
		"فرع فتح الله - كيه اتش جمله ماركت",
		"فرع فتح الله - كيه اتش جملة ماركت",
		"كيه اتش جمله ماركت مواد عناية -",
		"كيه اتش جملة ماركت مواد عناية -",
		"كيه اتش جمله ماركت مواد عناية",
		"كيه اتش جملة ماركت مواد عناية",
		"كيه اتش جمله ماركت -",
		"كيه اتش جملة ماركت -",
		"كيه اتش جمله ماركت",
		"كيه اتش جملة ماركت",
		"فتح الله اسواق -",
		"فتح الله أسواق -",
		"فتح الله اسواق",
		"فتح الله أسواق",
		"فتح الله جملة ماركت -",
		"فتح الله جملة ماركت",
		"فتح الله -",
		"فرع فتح الله -",
		"فرع فتح الله",
		"فرع كارفور -",
		"فرع كارفور",
		"فرع جملة ماركت -",
		"فرع جملة ماركت",
		"فرع بيت الجملة -",
		"فرع بيت الجملة",
		"فرع سبينيس -",
		"فرع سبينيس",
		"فرع مترو -",
		"فرع مترو",
		"فرع سعودي -",
		"فرع سعودي",
		"فرع كازيون -",
		"فرع كازيون",
		"كارفور -",
		"جملة ماركت -",
		"بيت الجملة -",
		"سبينيس -",
		"fathalla -",
		"fathalla",
		"carrefour -",
		"carrefour",
		"gomla market -",
		"gomla -",
		"gomla",
		"spinneys -",
		"spinneys",
		"branch -",
		"br.",
		"br ",
		"فرع -",
		"فرع",
		"فر.",
		"فر ",
		"فر-",
	}
	lower := strings.ToLower(cleaned)
	changed := true
	for changed {
		changed = false
		for _, p := range prefixes {
			pl := strings.ToLower(p)
			if strings.HasPrefix(lower, pl) {
				cleaned = strings.TrimSpace(cleaned[len(p):])
				cleaned = strings.TrimLeft(cleaned, "-–—/| ")
				lower = strings.ToLower(cleaned)
				changed = true
				break
			}
		}
	}
	cleaned = strings.TrimSpace(cleaned)
	// Trailing legal-entity crumbs after a successful prefix strip.
	for _, suf := range []string{
		"للتجاره والتوريدات ش م م",
		"للتجارة والتوريدات ش م م",
		"لتصنيع وتجاره السلع الغذائيه ش م م",
		"لتصنيع وتجارة السلع الغذائية ش م م",
		"ش م م",
		"مواد عناية",
	} {
		if strings.HasSuffix(cleaned, suf) {
			cleaned = strings.TrimSpace(strings.TrimSuffix(cleaned, suf))
			cleaned = strings.TrimRight(cleaned, "-–—/| ")
		}
	}
	cleaned = strings.TrimSpace(cleaned)
	// Never invent / drop a name: if every banner stripped away, keep the original
	// (e.g. legal-entity-only Sell-In rows with no branch suffix).
	if cleaned == "" {
		return original
	}
	return cleaned
}

// HasCareLine reports whether the raw label is a «مواد عناية» care-line spelling.
func HasCareLine(raw string) bool {
	return strings.Contains(raw, "مواد عناية") || strings.Contains(raw, "مواد عنايه")
}

// HasKHBanner reports «كيه اتش جمله ماركت» (KH Gomla Market) banner.
func HasKHBanner(raw string) bool {
	n := strings.ToLower(raw)
	return strings.Contains(raw, "كيه اتش") || strings.Contains(n, "kh ") || strings.Contains(n, "k.h")
}

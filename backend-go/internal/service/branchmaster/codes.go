package branchmaster

import (
	"fmt"
	"strings"
)

// Known chain slug → internal 2–4 letter code used in branch codes (FTH-001).
var chainCodeBySlug = map[string]string{
	"fathalla":      "FTH",
	"carrefour":     "CRF",
	"gomla":         "GOM",
	"beet-elgomla":  "BET",
	"beet_elgomla":  "BET",
	"spinneys":      "SPI",
	"metro":         "MET",
	"seoudi":        "SEO",
	"kazyon":        "KAZ",
}

var chainNameAR = map[string]string{
	"fathalla":     "فتح الله",
	"carrefour":    "كارفور",
	"gomla":        "جملة ماركت",
	"beet-elgomla": "بيت الجملة",
	"spinneys":     "سبينيس",
	"metro":        "مترو",
	"seoudi":       "سعودي",
	"kazyon":       "كازيون",
}

// ChainCodeForSlug returns the internal chain code (FTH) for a retailer slug.
func ChainCodeForSlug(slug string) string {
	s := strings.ToLower(strings.TrimSpace(slug))
	if s == "" || s == "unknown" {
		s = "fathalla"
	}
	if c, ok := chainCodeBySlug[s]; ok {
		return c
	}
	// Deterministic fallback from slug letters.
	var b strings.Builder
	for _, r := range strings.ToUpper(s) {
		if r >= 'A' && r <= 'Z' {
			b.WriteRune(r)
			if b.Len() == 3 {
				break
			}
		}
	}
	if b.Len() == 0 {
		return "UNK"
	}
	for b.Len() < 3 {
		b.WriteByte('X')
	}
	return b.String()
}

// ChainNameAR returns a short Arabic label for a known slug.
func ChainNameAR(slug string) string {
	s := strings.ToLower(strings.TrimSpace(slug))
	if n, ok := chainNameAR[s]; ok {
		return n
	}
	return s
}

// InferChainSlug guesses the retailer slug from a raw store/customer name.
// KH Gomla Market banners stay under fathalla until the owner decides otherwise
// (they are uploaded under the Fathalla Sell-In file today).
func InferChainSlug(raw string) string {
	rawL := strings.ToLower(raw)
	n := strings.ToLower(Normalize(raw))
	switch {
	case strings.Contains(raw, "كيه اتش") || strings.Contains(rawL, "كيه اتش"):
		return "fathalla"
	case strings.Contains(rawL, "كارفور") || strings.Contains(n, "carrefour"):
		return "carrefour"
	case strings.Contains(rawL, "سبينيس") || strings.Contains(n, "spinney"):
		return "spinneys"
	case strings.Contains(raw, "بيت الجمل") || strings.Contains(raw, "بيت الجملة"):
		return "beet-elgomla"
	case strings.Contains(rawL, "جملة ماركت") || (strings.Contains(raw, "جمله ماركت") && !strings.Contains(raw, "فتح الله") && !strings.Contains(raw, "كيه اتش")):
		return "gomla"
	case strings.Contains(rawL, "مترو") || strings.Contains(n, "metro"):
		return "metro"
	case strings.Contains(rawL, "كازيون") || strings.Contains(n, "kazyon"):
		return "kazyon"
	case strings.Contains(rawL, "سعودي") || strings.Contains(n, "seoudi"):
		return "seoudi"
	default:
		return "fathalla"
	}
}

// NextBranchCode allocates the next FTH-NNN code for a chain given existing branches.
func NextBranchCode(chainCode string, existing []Branch) string {
	cc := strings.ToUpper(strings.TrimSpace(chainCode))
	if cc == "" {
		cc = "FTH"
	}
	max := 0
	prefix := cc + "-"
	for _, b := range existing {
		if !strings.HasPrefix(strings.ToUpper(b.Code), prefix) {
			continue
		}
		var n int
		if _, err := fmt.Sscanf(b.Code[len(prefix):], "%d", &n); err == nil && n > max {
			max = n
		}
	}
	return fmt.Sprintf("%s-%03d", cc, max+1)
}

// UnallocatedCode returns the reserved code for the synthetic unallocated bucket of a chain.
func UnallocatedCode(chainCode string) string {
	cc := strings.ToUpper(strings.TrimSpace(chainCode))
	if cc == "" {
		cc = "FTH"
	}
	return cc + "-UNALLOC"
}

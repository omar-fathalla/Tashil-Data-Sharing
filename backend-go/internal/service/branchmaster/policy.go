package branchmaster

import "strings"

// ChainPolicy configures dry-run / mapping behavior per retailer chain.
// Defaults are chain-agnostic and safe for any future tenant file.
type ChainPolicy struct {
	Slug string `json:"slug"`
	// MergeCareWithGrocery: care-line («مواد عناية») and grocery at the same
	// short location share one branch code. Configurable per chain.
	MergeCareWithGrocery bool `json:"merge_care_with_grocery"`
	// KeepNumberedDistinct: different trailing numbers stay different branches
	// (كفر الدوار ≠ كفر الدوار 2). Same number with whitespace-only variance merges.
	KeepNumberedDistinct bool `json:"keep_numbered_distinct"`
	// QuarantineUnknown: raw names that do not match this chain's known banners
	// are listed as quarantined instead of becoming proposed branches.
	QuarantineUnknown bool `json:"quarantine_unknown"`
	// CareMarkers are substrings that mark a care-line spelling for this chain.
	CareMarkers []string `json:"care_markers,omitempty"`
}

// DefaultChainPolicy returns safe defaults for any slug (including unknown).
func DefaultChainPolicy(slug string) ChainPolicy {
	s := strings.ToLower(strings.TrimSpace(slug))
	if s == "" {
		s = "unknown"
	}
	p := ChainPolicy{
		Slug:                 s,
		MergeCareWithGrocery: true,
		KeepNumberedDistinct: true,
		QuarantineUnknown:    true,
		CareMarkers:          []string{"مواد عناية", "مواد عنايه"},
	}
	// Per-chain overrides (extensible). Unknown chains keep defaults.
	switch s {
	case "fathalla":
		// Owner: care = grocery same location; numbered stay distinct.
	case "acme": // used in unit tests as a second synthetic chain
		p.MergeCareWithGrocery = false
	}
	return p
}

// PolicyForSlug looks up (or builds) the policy for a chain slug.
func PolicyForSlug(slug string) ChainPolicy {
	return DefaultChainPolicy(slug)
}

// IsCareLineForPolicy reports care-line using the chain's configured markers.
func IsCareLineForPolicy(raw string, p ChainPolicy) bool {
	for _, m := range p.CareMarkers {
		if m != "" && strings.Contains(raw, m) {
			return true
		}
	}
	return HasCareLine(raw)
}

// GroupingKey builds the chain-scoped dry-run key respecting care-merge policy.
// When MergeCareWithGrocery is false, care and grocery at the same location stay apart.
func GroupingKey(slug, raw string, p ChainPolicy) string {
	norm := LinkNormalize(raw)
	if norm == "" {
		return ""
	}
	if p.KeepNumberedDistinct {
		// LinkNormalize already applies unifyTrailingNumberSpacing; different
		// numbers remain different keys. No extra merge across numbers.
	}
	cc := ChainCodeForSlug(slug)
	if !p.MergeCareWithGrocery && IsCareLineForPolicy(raw, p) {
		return cc + "|care|" + norm
	}
	return cc + "|" + norm
}

// MatchesKnownChainBanner reports whether raw looks like it belongs to slug.
// Used for quarantine of unknown names under QuarantineUnknown.
// Short Sell-Out location headers (no banner) are accepted when they do not
// look like a *different* known chain — live BQ already tagged chain_key.
func MatchesKnownChainBanner(raw, slug string) bool {
	rawL := strings.ToLower(raw)
	if IsUnallocated(raw) || isRegionalPlanCode(raw) {
		return true
	}
	switch strings.ToLower(strings.TrimSpace(slug)) {
	case "fathalla":
		if strings.Contains(raw, "فتح الله") || strings.Contains(raw, "كيه اتش") {
			return true
		}
		return !looksLikeForeignChain(raw, "fathalla")
	case "beet-elgomla", "beet_elgomla":
		return strings.Contains(raw, "بيت الجمل") || !looksLikeForeignChain(raw, "beet-elgomla")
	case "carrefour":
		return strings.Contains(rawL, "كارفور") || strings.Contains(rawL, "carrefour") ||
			!looksLikeForeignChain(raw, "carrefour")
	case "gomla":
		return strings.Contains(raw, "جملة ماركت") || strings.Contains(raw, "جمله ماركت") ||
			!looksLikeForeignChain(raw, "gomla")
	case "spinneys":
		return strings.Contains(rawL, "سبينيس") || strings.Contains(rawL, "spinney") ||
			!looksLikeForeignChain(raw, "spinneys")
	case "acme":
		// Synthetic test chain: only explicit Acme banners match (unknowns quarantine).
		return strings.Contains(rawL, "acme") || strings.Contains(raw, "أكمي")
	default:
		return InferChainSlug(raw) == strings.ToLower(strings.TrimSpace(slug))
	}
}

func looksLikeForeignChain(raw, self string) bool {
	rawL := strings.ToLower(raw)
	checks := []struct {
		slug string
		hit  bool
	}{
		{"fathalla", strings.Contains(raw, "فتح الله") || strings.Contains(raw, "كيه اتش")},
		{"beet-elgomla", strings.Contains(raw, "بيت الجمل")},
		{"carrefour", strings.Contains(rawL, "كارفور") || strings.Contains(rawL, "carrefour")},
		{"gomla", (strings.Contains(raw, "جملة ماركت") || strings.Contains(raw, "جمله ماركت")) && !strings.Contains(raw, "فتح الله") && !strings.Contains(raw, "كيه اتش")},
		{"spinneys", strings.Contains(rawL, "سبينيس") || strings.Contains(rawL, "spinney")},
		{"acme", strings.Contains(rawL, "acme") || strings.Contains(raw, "أكمي")},
	}
	self = strings.ToLower(self)
	for _, c := range checks {
		if c.slug == self {
			continue
		}
		if c.hit {
			return true
		}
	}
	return false
}

// IsParentLevelRaw reports parent-company / regional / legal-entity rows that must
// not become proposed store branches.
func IsParentLevelRaw(raw string) bool {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return false
	}
	if isRegionalPlanCode(raw) {
		return true
	}
	// Legal-entity parent spellings (with or without «- ميني»).
	if strings.Contains(raw, "لتصنيع وتجاره") || strings.Contains(raw, "لتصنيع وتجارة") ||
		strings.Contains(raw, "للتجاره والتوريدات") || strings.Contains(raw, "للتجارة والتوريدات") {
		return true
	}
	return false
}

// ParentLevelKind classifies a parent-level raw for the dry-run section.
func ParentLevelKind(raw string) string {
	if isRegionalPlanCode(raw) {
		return "regional"
	}
	if strings.Contains(raw, "ميني") || strings.Contains(strings.ToLower(raw), "mini") {
		return "parent_mini"
	}
	return "parent_company"
}

// IsWarehouseRaw reports Sell-In warehouse / مخزن locations (valid SI-only; not POS).
func IsWarehouseRaw(raw string) bool {
	r := strings.ToLower(raw)
	return strings.Contains(raw, "مخزن") || strings.Contains(r, "warehouse") || strings.Contains(r, "whs")
}

// InferLocationType returns store | warehouse from raw spellings in a proposed group.
func InferLocationType(raws []string) string {
	for _, r := range raws {
		if IsWarehouseRaw(r) {
			return "warehouse"
		}
	}
	return "store"
}

// Adeco Plan_2026 archive — excluded from branch unification (owner #70).
// Do NOT delete or modify this archive's rows in BQ/prod.
const (
	ExcludedPlanArchiveID = "arch_sellin_adeco_fathalla_1794179188685072646"
	ExcludedPlanFileName  = "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx"
)

// ExcludedFromUnification reports Plan_2026 / non in26|out26 rows that must not
// enter the Adeco dry-run proposal (parent/mini/Regional/16 codes).
func ExcludedFromUnification(o RawOccurrence) bool {
	file := strings.TrimSpace(o.SourceFile)
	arch := strings.TrimSpace(o.ArchiveID)
	src := strings.ToLower(strings.TrimSpace(o.Source))
	if arch == ExcludedPlanArchiveID ||
		file == ExcludedPlanFileName ||
		strings.Contains(file, "Plan_2026") ||
		strings.Contains(file, "Sell_In_Plan") ||
		src == "plan_branch_code" {
		return true
	}
	lower := strings.ToLower(file)
	if strings.Contains(lower, "in26") || strings.Contains(lower, "out26") {
		return false
	}
	// Unknown files are excluded from unification.
	return file != ""
}

// FilterUnificationSources keeps only in26/out26 rows for Adeco branch unification.
func FilterUnificationSources(in []RawOccurrence) (kept []RawOccurrence, skipped int) {
	for _, o := range in {
		if ExcludedFromUnification(o) {
			skipped++
			continue
		}
		kept = append(kept, o)
	}
	return kept, skipped
}

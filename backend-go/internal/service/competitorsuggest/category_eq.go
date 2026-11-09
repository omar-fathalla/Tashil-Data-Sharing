package competitorsuggest

// DefaultCategoryEquivalence is the owner-approved alias map for competitor
// suggestion pre-filter ONLY (Mohamed, 9 Nov 2026).
//
// Approved (#1 + #2):
//   مسحوق جيل اتوماتيك == مساحيق جيل اتوماتيك
//   مساحيق جيل يدوى == مسحوق جيل يدوى
//
// Other near-duplicates / related lookalikes stay pending in the PR description
// — never auto-merged into this map.
//
// This map must NOT rewrite Sell-Out totals, stored categories, BigQuery rows,
// or any KPI path — only SameCategory / PreFilterCandidates for suggestions.
func DefaultCategoryEquivalence() CategoryEquivalence {
	return CategoryEquivalence{
		// #1 automatic gel powder (singular/plural)
		"مسحوق جيل اتوماتيك":  "مساحيق جيل اتوماتيك",
		"مساحيق جيل اتوماتيك": "مساحيق جيل اتوماتيك",
		// #2 manual gel powder (يدوى as stored in Sell-Out)
		"مساحيق جيل يدوى": "مساحيق جيل يدوى",
		"مسحوق جيل يدوى":  "مساحيق جيل يدوى",
	}
}

// PendingCategoryEquivalencePairs are live lookalikes / related labels that still
// need owner approval. Documented for the PR description; not applied at runtime.
//
// Source scan (read-only): tashil_analytics.sell_out_facts, tenant-adeco, fathalla
// (9 Nov 2026). Distinct categories: 29.
//   - ى/ي + ة/ه fold: no extra pairs beyond approved gel singular/plural.
//   - Token-overlap siblings below are RELATED but not spelling duplicates —
//     owner must decide; do NOT merge into DefaultCategoryEquivalence.
//   - اتوماتيك↔يدوى share tokens but are different product lines (not pending merge).
var PendingCategoryEquivalencePairs = [][2]string{
	// Prefix sibling — may be intentional split
	{"هاند وواش", "هاند وواش مطهر"},
	// Dishwasher accessory/powder family (اقراص / زيت / ملح / مسحوق)
	{"اقراص غسالات اطباق", "زيت غسالات اطباق"},
	{"اقراص غسالات اطباق", "مسحوق غسالات اطباق"},
	{"اقراص غسالات اطباق", "ملح غسالات اطباق"},
	{"زيت غسالات اطباق", "مسحوق غسالات اطباق"},
	{"زيت غسالات اطباق", "ملح غسالات اطباق"},
	{"مسحوق غسالات اطباق", "ملح غسالات اطباق"},
	// If a يدوي (final ي) spelling ever appears — do NOT treat as approved #2
	{"مساحيق جيل يدوى", "مساحيق جيل يدوي"},
	{"مسحوق جيل يدوى", "مسحوق جيل يدوي"},
}

// LiveDistinctCategoriesFathallaAdeco is the 29 distinct category strings observed
// in sell_out_facts (tenant-adeco, fathalla) during the 9 Nov 2026 read-only scan.
// Kept for docs/tests — not used to mutate stored categories.
var LiveDistinctCategoriesFathallaAdeco = []string{
	"اقراص غسالات اطباق",
	"زيت غسالات اطباق",
	"شاور جيل",
	"صابون سائل اطباق",
	"عناية شخصية",
	"كلور ألوان",
	"كلور عادى",
	"مزيلات بقع ملابس",
	"مساحيق جيل اتوماتيك",
	"مساحيق جيل يدوى",
	"مسحوق جيل اتوماتيك",
	"مسحوق جيل يدوى",
	"مسحوق غسالات اطباق",
	"مسلك احواض وبالوعات",
	"مطهر عام",
	"معطر جو",
	"ملح غسالات اطباق",
	"ملمع اخشاب وباركيه",
	"ملمع زجاج وكريستال",
	"ملمع معادن",
	"منظف ارضيات",
	"منظفات تواليت",
	"منظفات حمام",
	"منظفات سجاد ومفروشات",
	"منظفات متعدده",
	"منظفات مطبخ",
	"منعمات ملابس",
	"هاند وواش",
	"هاند وواش مطهر",
}

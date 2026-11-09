package competitorsuggest

// DefaultCategoryEquivalence is the owner-approved alias map for competitor
// suggestion pre-filter ONLY (Mohamed, 9 Nov 2026).
//
// Approved:
//  1. مسحوق جيل اتوماتيك == مساحيق جيل اتوماتيك
//  2. ONE group (all four):
//       مساحيق جيل يدوى = مسحوق جيل يدوى = مساحيق جيل يدوي = مسحوق جيل يدوي
//
// Explicitly REJECTED (keep separate — see RejectedCategoryEquivalencePairs):
//   - هاند وواش vs هاند وواش مطهر
//   - all pairs among اقراص/زيت/مسحوق/ملح غسالات اطباق
//
// This map must NOT rewrite Sell-Out totals, stored categories, BigQuery rows,
// or any KPI path — only SameCategory / PreFilterCandidates for suggestions.
func DefaultCategoryEquivalence() CategoryEquivalence {
	const manualGel = "مساحيق جيل يدوى"
	return CategoryEquivalence{
		// #1 automatic gel powder (singular/plural)
		"مسحوق جيل اتوماتيك":  "مساحيق جيل اتوماتيك",
		"مساحيق جيل اتوماتيك": "مساحيق جيل اتوماتيك",
		// #2 manual gel powder — full ى/ي × singular/plural group
		"مساحيق جيل يدوى": manualGel,
		"مسحوق جيل يدوى":  manualGel,
		"مساحيق جيل يدوي": manualGel,
		"مسحوق جيل يدوي":  manualGel,
	}
}

// RejectedCategoryEquivalencePairs are owner-rejected merges: keep categories
// separate in pre-filter. Removed from PendingCategoryEquivalencePairs.
// Documented for the PR; not applied at runtime (absence from Default is enough).
var RejectedCategoryEquivalencePairs = [][2]string{
	{"هاند وواش", "هاند وواش مطهر"},
	{"اقراص غسالات اطباق", "زيت غسالات اطباق"},
	{"اقراص غسالات اطباق", "مسحوق غسالات اطباق"},
	{"اقراص غسالات اطباق", "ملح غسالات اطباق"},
	{"زيت غسالات اطباق", "مسحوق غسالات اطباق"},
	{"زيت غسالات اطباق", "ملح غسالات اطباق"},
	{"مسحوق غسالات اطباق", "ملح غسالات اطباق"},
}

// PendingCategoryEquivalencePairs are live lookalikes still awaiting owner decision.
// Empty after Mohamed's 9 Nov approvals/rejections for the fathalla scan set.
var PendingCategoryEquivalencePairs = [][2]string{}

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

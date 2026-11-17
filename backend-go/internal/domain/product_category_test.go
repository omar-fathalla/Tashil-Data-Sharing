package domain

import "testing"

func TestNormalizeProductCategorySpellingOnly(t *testing.T) {
	kept := map[string]string{
		"  كلور   الوان  ": "كلور ألوان",
		"كلور ألوان":       "كلور ألوان",
		"كلور عادي":        "كلور عادى",
		"كلور عادى":        "كلور عادى",
		"مطهرعام":          "مطهر عام",
		"مطهر عام":         "مطهر عام",
		"صابون سائل أطباق": "صابون سائل اطباق",
		"مساحيق جيل يدوي":  "مساحيق جيل يدوى",
	}
	for raw, want := range kept {
		if got := NormalizeProductCategory(raw); got != want {
			t.Errorf("NormalizeProductCategory(%q) = %q, want %q", raw, got, want)
		}
	}

	// Different names, singular/plural, and shortened labels stay as written
	// (after spelling fold only).
	separate := []string{
		"كلور ارضيات",
		"كلور أرضيات",
		"مطهر ارضيات",
		"منظف ارضيات",
		"صابون سائل للارضيات",
		"صابون سائل اطباق",
		"صابون سائل للاطباق",
		"سائل اطباق",
		"مسحوق جيل اتوماتيك",
		"مساحيق جيل اتوماتيك",
		"مساحيق جيل اوتوماتيك",
		"مسحوق جيل",
		"منعم ملابس",
		"منعمات ملابس",
		"هاند ووش",
		"هاند وواش",
		"مسحوق بودر غسالات اطباق",
		"مسحوق غسالات اطباق",
	}
	for _, raw := range separate {
		got := NormalizeProductCategory(raw)
		folded := foldCategorySpelling(collapseCategoryWhitespace(raw))
		if alias, ok := spellingCategoryAliases[folded]; ok {
			folded = alias
		}
		if got != folded {
			t.Errorf("NormalizeProductCategory(%q) = %q, want spelling-only %q", raw, got, folded)
		}
	}
	if NormalizeProductCategory("كلور ارضيات") == NormalizeProductCategory("منظف ارضيات") {
		t.Fatal("كلور ارضيات must not merge into منظف ارضيات")
	}
	if NormalizeProductCategory("كلور ألوان") == NormalizeProductCategory("كلور عادى") {
		t.Fatal("color bleach and regular bleach must stay separate")
	}
	if NormalizeProductCategory("مسحوق جيل اتوماتيك") == NormalizeProductCategory("مساحيق جيل اتوماتيك") {
		t.Fatal("singular/plural gel names must stay separate")
	}
	if NormalizeProductCategory("صابون سائل للاطباق") == NormalizeProductCategory("صابون سائل اطباق") {
		t.Fatal("dish-liquid wording must stay separate across chains")
	}
}

func TestProductCategoryMatchValuesSpellingOnly(t *testing.T) {
	vals := ProductCategoryMatchValues("كلور ألوان")
	got := map[string]bool{}
	for _, v := range vals {
		got[v] = true
		if NormalizeProductCategory(v) != "كلور ألوان" {
			t.Errorf("alias %q does not normalize to كلور ألوان", v)
		}
	}
	if !got["كلور ألوان"] || !got["كلور الوان"] {
		t.Errorf("missing hamza spelling in %#v", vals)
	}
	floor := ProductCategoryMatchValues("منظف ارضيات")
	for _, v := range floor {
		if v == "كلور ارضيات" || v == "مطهر ارضيات" {
			t.Errorf("type alias %q still attached to منظف ارضيات", v)
		}
	}
	yeh := ProductCategoryMatchValues("كلور عادى")
	found := false
	for _, v := range yeh {
		if v == "كلور عادي" {
			found = true
		}
	}
	if !found {
		t.Errorf("missing ى/ي spelling in %#v", yeh)
	}
}

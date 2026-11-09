package domain

import "testing"

func TestProductCategoryMatchValuesIncludesAliases(t *testing.T) {
	vals := ProductCategoryMatchValues("صابون سائل اطباق")
	want := map[string]bool{
		"صابون سائل اطباق": true,
		"صابون سائل للاطباق": true,
		"سائل اطباق":         true,
	}
	got := map[string]bool{}
	for _, v := range vals {
		got[v] = true
	}
	for w := range want {
		if !got[w] {
			t.Errorf("missing alias %q in %#v", w, vals)
		}
	}
	for _, v := range vals {
		if NormalizeProductCategory(v) != "صابون سائل اطباق" {
			t.Errorf("alias %q does not normalize to dish liquid", v)
		}
	}
}

func TestNormalizeProductCategoryWhitespace(t *testing.T) {
	got := NormalizeProductCategory("  كلور   الوان  ")
	if got != "كلور ألوان" {
		t.Errorf("got %q", got)
	}
}

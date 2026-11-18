package competitorsuggest

import "testing"

func TestParseSizeFromName(t *testing.T) {
	cases := []struct {
		name string
		ok   bool
		val  float64
		unit string
	}{
		{"فيبا صابون سائل اطباق 3 كجم", true, 3000, "g"},
		{"بريل 4 kg", true, 4000, "g"},
		{"منظف 750 مل", true, 750, "ml"},
		{"جل 1.5 لتر", true, 1500, "ml"},
		{"منتج بدون حجم", false, 0, ""},
		{"عناية شخصية شامبو", false, 0, ""},
	}
	for _, c := range cases {
		got, ok := ParseSizeFromName(c.name)
		if ok != c.ok {
			t.Fatalf("%q: ok=%v want %v", c.name, ok, c.ok)
		}
		if !c.ok {
			continue
		}
		if got.Value != c.val || got.Unit != c.unit {
			t.Fatalf("%q: got %+v want val=%v unit=%s", c.name, got, c.val, c.unit)
		}
	}
}

func TestSizeIsSoftBonusNotHardFilter(t *testing.T) {
	own := SkuCandidate{
		Barcode: "OWN1", SKUName: "فيبا 3 كجم", Category: "صابون سائل اطباق", IsOwnBrand: true,
	}
	pool := []SkuCandidate{
		{Barcode: "C1", SKUName: "بريل بدون حجم مذكور", Category: "صابون سائل اطباق", Supplier: "هنكل"},
		{Barcode: "C2", SKUName: "منافس 10 كجم بعيد الحجم", Category: "صابون سائل اطباق", Supplier: "X"},
		{Barcode: "C3", SKUName: "منافس 3 كجم", Category: "صابون سائل اطباق", Supplier: "Y", Units: 10},
		{Barcode: "C4", SKUName: "فئة أخرى 3 كجم", Category: "كلور ألوان", Supplier: "Z"},
		{Barcode: "OWN1", SKUName: "نفس الباركود", Category: "صابون سائل اطباق", IsOwnBrand: false},
	}
	got := PreFilterCandidates(own, pool, nil)
	if len(got) != 3 {
		t.Fatalf("want 3 same-category candidates (size soft), got %d %#v", len(got), got)
	}
	// Similar size should rank above missing/far size when scores differ.
	if got[0].Candidate.Barcode != "C3" {
		t.Fatalf("expected size-similar C3 first, got %s", got[0].Candidate.Barcode)
	}
	barcodes := map[string]bool{}
	for _, g := range got {
		barcodes[g.Candidate.Barcode] = true
	}
	if !barcodes["C1"] || !barcodes["C2"] {
		t.Fatal("missing-size and far-size must still be candidates (soft signal)")
	}
	if barcodes["C4"] {
		t.Fatal("different category must be hard-filtered")
	}
}

func TestCategoryExactMatchWithoutEquivalence(t *testing.T) {
	own := SkuCandidate{Barcode: "O", SKUName: "جيل ادكو", Category: "مساحيق جيل اتوماتيك", IsOwnBrand: true}
	pool := []SkuCandidate{
		{Barcode: "A", SKUName: "منافس", Category: "مسحوق جيل اتوماتيك"},
		{Barcode: "B", SKUName: "نفس الفئة", Category: "مساحيق جيل اتوماتيك"},
	}
	got := PreFilterCandidates(own, pool, nil)
	if len(got) != 1 || got[0].Candidate.Barcode != "B" {
		t.Fatalf("nil eq = exact match only, got %#v", got)
	}
}

func TestDetectedCategoryVariantsSurfacedNotMerged(t *testing.T) {
	cats := []string{"مساحيق جيل اتوماتيك", "مسحوق جيل اتوماتيك", "عناية شخصية", "صابون سائل اطباق"}
	pairs := DetectedCategoryVariants(cats, nil)
	found := false
	for _, p := range pairs {
		if (p[0] == "مساحيق جيل اتوماتيك" && p[1] == "مسحوق جيل اتوماتيك") ||
			(p[1] == "مساحيق جيل اتوماتيك" && p[0] == "مسحوق جيل اتوماتيك") {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected gel-powder spelling variants surfaced, got %#v", pairs)
	}
	// With owner eq mapping one→other, they collapse and should not appear as a pair.
	eq := CategoryEquivalence{"مسحوق جيل اتوماتيك": "مساحيق جيل اتوماتيك"}
	pairs = DetectedCategoryVariants(cats, eq)
	for _, p := range pairs {
		if p[0] == "مسحوق جيل اتوماتيك" || p[1] == "مسحوق جيل اتوماتيك" {
			t.Fatalf("merged alias should not surface: %#v", pairs)
		}
	}
}

func TestNoCompetitorsInCategoryNoCandidates(t *testing.T) {
	own := SkuCandidate{Barcode: "P1", SKUName: "عناية شخصية 1", Category: "عناية شخصية", IsOwnBrand: true}
	pool := []SkuCandidate{
		{Barcode: "X", SKUName: "منافس اطباق", Category: "صابون سائل اطباق"},
	}
	got := PreFilterCandidates(own, pool, nil)
	if len(got) != 0 {
		t.Fatalf("عناية شخصية has 0 competitors in data — want empty, got %#v", got)
	}
}

func TestVariantBonus(t *testing.T) {
	if !VariantBonus("فيبا ليمون 3 كجم", "بريل ليمون 4 كجم") {
		t.Fatal("expected lemon variant bonus")
	}
	if VariantBonus("فيبا 3 كجم", "بريل 4 كجم") {
		t.Fatal("no shared scent token")
	}
}

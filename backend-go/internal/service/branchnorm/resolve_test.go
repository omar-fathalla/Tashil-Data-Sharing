package branchnorm

import (
	"strings"
	"testing"
)

func TestResolveArabicExact(t *testing.T) {
	r := Resolve("سموحة")
	if r.MatchKind != KindExact || r.Slug != "smouha" || r.CanonicalAR != "سموحة" {
		t.Fatalf("exact: %+v", r)
	}
	if r.Confidence != 1.0 || r.Changed {
		t.Fatalf("exact confidence/changed: %+v", r)
	}
	if !strings.Contains(r.ReasonAR, "مطابق") {
		t.Fatalf("reason: %s", r.ReasonAR)
	}
}

func TestResolveEnglishToArabic(t *testing.T) {
	cases := []struct {
		raw, slug, kind string
	}{
		{"Smouha", "smouha", KindEnglish},
		{"Gardenia", "gardenia", KindEnglish},
		{"Stanley", "stanley", KindEnglish},
		{"Tanta", "tanta", KindEnglish},
		{"Maadi", "maadi", KindEnglish},
		{"Carrefour Maadi", "maadi", KindEnglish},
		{"Nasr City", "nasr_city", KindEnglish},
		{"Hanoville", "hanoville", KindEnglish},
	}
	for _, c := range cases {
		r := Resolve(c.raw)
		if r.Slug != c.slug || r.MatchKind != c.kind {
			t.Errorf("%q → slug=%s kind=%s want %s/%s (%s)", c.raw, r.Slug, r.MatchKind, c.slug, c.kind, r.ReasonAR)
		}
		if r.CanonicalAR == "" || !r.Changed {
			t.Errorf("%q should change to Arabic canonical: %+v", c.raw, r)
		}
		if !strings.Contains(r.ReasonAR, "الإنجليزي") && !strings.Contains(r.ReasonAR, "وُحِّد") {
			t.Errorf("%q reason missing Arabic: %s", c.raw, r.ReasonAR)
		}
	}
}

func TestResolveAbbreviations(t *testing.T) {
	cases := []struct {
		raw, slug string
	}{
		{"فر. سموحة", "smouha"},
		{"فر سموحة", "smouha"},
		{"Smh", "smouha"},
		{"Gdn", "gardenia"},
		{"St. Stanley", "stanley"},
		{"Oct", "october"},
		{"6 اكتوبر", "october"},
		{"6th October", "october"},
		{"Smouha Mini", "smouha_mini"},
		{"سموحة mini", "smouha_mini"},
		{"Tanta Outlet", "tanta_outlet"},
	}
	for _, c := range cases {
		r := Resolve(c.raw)
		if r.Slug != c.slug {
			t.Errorf("%q → %s (%s) want %s", c.raw, r.Slug, r.MatchKind, c.slug)
		}
		if r.Slug == "" {
			t.Errorf("%q empty slug kind=%s", c.raw, r.MatchKind)
		}
		// Abbrev / English / Alias are preferred; Exact is OK when strip leaves the canonical form.
		switch r.MatchKind {
		case KindAbbrev, KindEnglish, KindAlias, KindExact:
		default:
			t.Errorf("%q unexpected kind %s", c.raw, r.MatchKind)
		}
	}
}

func TestResolveArabicAliases(t *testing.T) {
	cases := map[string]string{
		"نهال فيل":     "hanoville",
		"ستانلى":       "stanley",
		"المحلة":       "mahalla",
		"المحله الكبري": "mahalla",
		"امواج":        "amwaj_north_coast",
		"فرع سموحة":    "smouha",
		"فرع فتح الله - سموحة": "smouha",
		"فتح الله - ستانلي":    "stanley",
	}
	for raw, slug := range cases {
		r := Resolve(raw)
		if r.Slug != slug {
			t.Errorf("%q → %s want %s (%s)", raw, r.Slug, slug, r.ReasonAR)
		}
	}
}

func TestResolveUnknownKeepsRaw(t *testing.T) {
	r := Resolve("فرع العلمين الجديدة")
	if r.MatchKind != KindUnknown {
		t.Fatalf("want unknown: %+v", r)
	}
	if r.Slug != "" {
		t.Fatalf("unknown must not invent slug: %+v", r)
	}
	if !strings.Contains(r.CanonicalAR, "العلمين") {
		t.Fatalf("should keep stripped raw: %+v", r)
	}
	if !strings.Contains(r.ReasonAR, "لم يُعرف") {
		t.Fatalf("reason: %s", r.ReasonAR)
	}
}

func TestResolveEmpty(t *testing.T) {
	r := Resolve("  ")
	if r.MatchKind != KindUnknown || r.Confidence != 0 {
		t.Fatalf("%+v", r)
	}
}

func TestResolveManySummaryArabic(t *testing.T) {
	raws := []string{"سموحة", "Smouha", "فر. سموحة", "نهال فيل", "Unknown Branch X", "Gardenia"}
	_, sum := ResolveMany(raws)
	if sum.Total != 6 {
		t.Fatalf("total=%d", sum.Total)
	}
	if sum.Exact < 1 || sum.English < 1 || sum.Abbrev < 1 || sum.Alias < 1 || sum.Unknown < 1 {
		t.Fatalf("counters: %+v", sum)
	}
	// Smouha + فر. سموحة + سموحة collapse to one canonical
	if sum.UniqueCanon < 3 {
		t.Fatalf("unique_canon=%d want >=3: %+v", sum.UniqueCanon, sum)
	}
	ar := sum.SummaryAR
	for _, needle := range []string{"توحيد الفروع", "إنجليزي", "اختصار", "غير معروف"} {
		if !strings.Contains(ar, needle) {
			t.Errorf("summary missing %q: %s", needle, ar)
		}
	}
	if len(sum.Samples) == 0 {
		t.Fatal("expected changed samples")
	}
}

func TestFrozenSlugsUnchanged(t *testing.T) {
	// Must match historical BuildBranchStoreMetadata slugs for known branches.
	want := map[string]string{
		"سموحة":          "smouha",
		"سموحة ميني":     "smouha_mini",
		"جاردينيا":       "gardenia",
		"هانوفيل":        "hanoville",
		"نهال فيل":       "hanoville",
		"أكتوبر":         "october",
		"طنطا":           "tanta",
		"طنطا - اوت ليت مول": "tanta_outlet",
		"ستانلى":         "stanley",
		"المحلة الكبرى":  "mahalla",
		"دمياط الجديدة":  "new_damietta",
	}
	for raw, slug := range want {
		r := Resolve(raw)
		if r.Slug != slug {
			t.Errorf("%q slug=%s want %s", raw, r.Slug, slug)
		}
	}
}

func TestCatalogSizePositive(t *testing.T) {
	if CatalogSize() < 30 {
		t.Fatalf("catalog too small: %d", CatalogSize())
	}
}

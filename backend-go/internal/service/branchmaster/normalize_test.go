package branchmaster

import "testing"

func TestNormalize_ArabicAndPrefix(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"عائلة فتح الله ماركت - مخزن الافوكاتو", "مخزن الافوكاتو"},
		{"عائله فتح الله ماركت - مخزن الافوجادو", "مخزن الافوجادو"},
		{"فتح الله - سموحة", "سموحه"},
		{"فرع سموحة", "سموحه"},
		{"أكتوبر", "اكتوبر"},
		{"إبراهيمية", "ابراهيميه"},
		{"آمال", "امال"},
		{"دمنهور  الاستاد", "دمنهور الاستاد"},
		{"٦ اكتوبر", "6 اكتوبر"},
		{"غير موزع على فرع", "غير موزع علي فرع"},
	}
	for _, c := range cases {
		got := Normalize(c.in)
		if got != c.want {
			t.Errorf("Normalize(%q)=%q want %q", c.in, got, c.want)
		}
	}
}

func TestShortDisplay(t *testing.T) {
	got := ShortDisplay("عائلة فتح الله ماركت - سموحة")
	if got != "سموحة" {
		t.Fatalf("ShortDisplay=%q", got)
	}
	if ShortDisplay(UnallocatedBranchName) != UnallocatedBranchName {
		t.Fatal("unallocated display")
	}
}

func TestIsUnallocated(t *testing.T) {
	if !IsUnallocated("غير موزع على فرع") {
		t.Fatal("expected unallocated")
	}
	if IsUnallocated("سموحة") {
		t.Fatal("smouha is not unallocated")
	}
}

func TestNormalize_KHAndCarePrefixes(t *testing.T) {
	cases := []struct{ in, want string }{
		{"كيه اتش جمله ماركت - العصافرة 45", "العصافره 45"},
		{"فرع فتح الله - كيه اتش جمله ماركت - العصافرة 45", "العصافره 45"},
		{"كيه اتش جمله ماركت مواد عناية - العصافرة 45", "العصافره 45"},
		{"عائله فتح الله ماركت مواد عناية - سموحة", "سموحه"},
	}
	for _, c := range cases {
		if got := Normalize(c.in); got != c.want {
			t.Errorf("Normalize(%q)=%q want %q", c.in, got, c.want)
		}
	}
}

func TestNormalize_LegalEntityBeforeShortBanner(t *testing.T) {
	full := "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م"
	if got := Normalize(full); got == "" {
		t.Fatalf("legal-entity-only must not normalize to empty")
	}
	mini := "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م - ميني"
	if got := Normalize(mini); got != "ميني" {
		t.Fatalf("Normalize(legal-mini)=%q want ميني", got)
	}
}

func TestNormalize_TrailingNumberWhitespaceOnly(t *testing.T) {
	// Same number, whitespace variants → merge.
	a := LinkNormalize("عائله فتح الله ماركت - كفر الدوار 2")
	b := LinkNormalize("عائله فتح الله ماركت مواد عناية - كفر الدوار2")
	if a != b {
		t.Fatalf("same-number whitespace must merge: %q vs %q", a, b)
	}
	if a != "كفر الدوار 2" {
		t.Fatalf("normalized=%q want كفر الدوار 2", a)
	}
	// Different numbers (or number vs none) → never merge.
	pairs := [][2]string{
		{"كفر الدوار", "كفر الدوار 2"},
		{"الغردقة", "الغردقة 2"},
		{"نيس", "نيس2"},
		{"كفر الدوار 2", "كفر الدوار 3"},
	}
	for _, p := range pairs {
		x, y := LinkNormalize("عائله فتح الله ماركت - "+p[0]), LinkNormalize("عائله فتح الله ماركت - "+p[1])
		if x == y {
			t.Fatalf("different numbers must stay distinct: %q and %q both → %q", p[0], p[1], x)
		}
	}
}

func TestLinkNormalize_HanovilleBridge(t *testing.T) {
	a := LinkNormalize("هانوفيل")
	b := LinkNormalize("عائله فتح الله ماركت - الهانوفيل")
	if a != b {
		t.Fatalf("hanoville bridge: %q vs %q", a, b)
	}
}

func TestDryRunSellOutSources(t *testing.T) {
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "عائله فتح الله ماركت - سموحة", ChainSlug: "fathalla", Source: "sell_in"},
		{RawName: "عائله فتح الله ماركت - سموحة", ChainSlug: "fathalla", Source: "returns"},
		{RawName: "سموحة", ChainSlug: "fathalla", Source: "sell_out"},
		{RawName: "هانوفيل", ChainSlug: "fathalla", Source: "sell_out"},
		{RawName: "عائله فتح الله ماركت - الهانوفيل", ChainSlug: "fathalla", Source: "sell_in"},
		{RawName: "الأنفوشي", ChainSlug: "fathalla", Source: "sell_out"},
	})
	if report.SellInAndOut < 2 {
		t.Fatalf("expected smouha+hanoville matched, got si+so=%d so_only=%d", report.SellInAndOut, report.SellOutOnly)
	}
	// SO-only (الأنفوشي) is normal — counted, shown, never flagged.
	if report.SellOutOnly < 1 {
		t.Fatalf("expected ≥1 sell-out-only row, got so_only=%d", report.SellOutOnly)
	}
	if len(report.UnmatchedSellOut) != 0 {
		t.Fatalf("SO-only must not be flagged unmatched: %v", report.UnmatchedSellOut)
	}
	if len(report.OwnerQuestions) != 0 {
		t.Fatalf("SO-only must not create owner questions: %v", report.OwnerQuestions)
	}
	foundAnf := false
	for _, r := range report.Rows {
		if containsSub(r.DisplayName, "الأنفوشي") || containsSub(stringsJoin(r.RawNames), "الأنفوشي") {
			foundAnf = true
		}
	}
	if !foundAnf {
		t.Fatal("الأنفوشي SO-only row must stay visible in proposed branches")
	}
	var smouhaSrc string
	for _, r := range report.Rows {
		if r.DisplayName == "سموحة" || r.NormalizedKey == LinkNormalize("سموحة") || containsSub(r.NormalizedKey, "سموحه") {
			smouhaSrc = r.SourceHint
		}
	}
	if smouhaSrc != "sell_in+sell_out+returns" && smouhaSrc != "sell_in+sell_out" {
		// returns included in this fixture
		if smouhaSrc != "sell_in+sell_out+returns" {
			t.Fatalf("smouha sources=%q", smouhaSrc)
		}
	}
}

func containsSub(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 || stringIndex(s, sub) >= 0)
}

func stringIndex(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

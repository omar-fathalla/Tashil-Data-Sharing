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

func TestLinkNormalize_IbrahimiehEqualsRiviera(t *testing.T) {
	so := LinkNormalize("فرع فتح الله - الإبراهيمية")
	si := LinkNormalize("عائله فتح الله ماركت - الابراهيمية ريفيرا")
	care := LinkNormalize("عائله فتح الله ماركت مواد عناية - الابراهيمية ريفيرا")
	mini := LinkNormalize("فرع فتح الله - الإبراهيمية ميني")
	if so != si || so != care {
		t.Fatalf("إبراهيمية must equal ريفيرا: so=%q si=%q care=%q", so, si, care)
	}
	if mini == so {
		t.Fatalf("الإبراهيمية ميني must stay separate from ريفيرا, got %q", mini)
	}
}

func TestLinkNormalize_OwnerConfirmedBridges(t *testing.T) {
	plainD := LinkNormalize("عائله فتح الله ماركت - دمنهور")
	careD := LinkNormalize("عائله فتح الله ماركت مواد عناية - دمنهور")
	andlus := LinkNormalize("فرع فتح الله - دمنهور الأندلس")
	stad := LinkNormalize("عائله فتح الله ماركت - دمنهور - الاستاد")
	if plainD != andlus || careD != andlus {
		t.Fatalf("دمنهور must equal الأندلس: plain=%q care=%q andlus=%q", plainD, careD, andlus)
	}
	if stad == plainD {
		t.Fatalf("دمنهور الاستاد must stay separate, got %q", stad)
	}

	plainS := LinkNormalize("عائله فتح الله ماركت - سيدي جابر")
	careS := LinkNormalize("عائله فتح الله ماركت مواد عناية - سيدي جابر")
	station := LinkNormalize("فرع فتح الله - سيدي جابر المحطة")
	miniS := LinkNormalize("فرع فتح الله - سيدي جابر ميني")
	if plainS != station || careS != station {
		t.Fatalf("سيدي جابر must equal المحطة: plain=%q care=%q station=%q", plainS, careS, station)
	}
	if miniS == plainS {
		t.Fatalf("سيدي جابر ميني must stay separate, got %q", miniS)
	}
}

func TestDryRun_OwnerConfirmedFTHMerges(t *testing.T) {
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "فرع فتح الله - الإبراهيمية", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
		{RawName: "عائله فتح الله ماركت - الابراهيمية ريفيرا", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "عائله فتح الله ماركت مواد عناية - الابراهيمية ريفيرا", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "فرع فتح الله - الإبراهيمية ميني", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
		{RawName: "فرع فتح الله - دمنهور الأندلس", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
		{RawName: "عائله فتح الله ماركت - دمنهور", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "عائله فتح الله ماركت مواد عناية - دمنهور", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "عائله فتح الله ماركت - دمنهور - الاستاد", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "فرع فتح الله - دمنهور - الاستاد", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
		{RawName: "فرع فتح الله - سيدي جابر المحطة", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
		{RawName: "عائله فتح الله ماركت - سيدي جابر", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "عائله فتح الله ماركت مواد عناية - سيدي جابر", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "فرع فتح الله - سيدي جابر ميني", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
	})
	if len(report.UnmatchedSellOut) != 0 || len(report.OwnerQuestions) != 0 {
		t.Fatalf("no missing-SI flags: unmatched=%v q=%v", report.UnmatchedSellOut, report.OwnerQuestions)
	}

	find := func(pred func(r ProposalRow) bool) *ProposalRow {
		for i := range report.Rows {
			if pred(report.Rows[i]) {
				return &report.Rows[i]
			}
		}
		return nil
	}
	riviera := find(func(r ProposalRow) bool {
		j := stringsJoin(r.RawNames)
		return containsSub(j, "ريفيرا") && !containsSub(j, "ميني")
	})
	miniIbr := find(func(r ProposalRow) bool {
		j := stringsJoin(r.RawNames) + r.DisplayName
		return containsSub(j, "ميني") && (containsSub(j, "براهيم") || containsSub(j, "براهيم"))
	})
	andlus := find(func(r ProposalRow) bool {
		j := stringsJoin(r.RawNames)
		return containsSub(j, "أندلس") || containsSub(j, "الأندلس") || containsSub(j, "الاندلس") ||
			(containsSub(j, "دمنهور") && containsSub(r.SourceHint, "sell_out") && !containsSub(j, "استاد"))
	})
	stad := find(func(r ProposalRow) bool {
		return containsSub(stringsJoin(r.RawNames), "استاد")
	})
	station := find(func(r ProposalRow) bool {
		j := stringsJoin(r.RawNames)
		return (containsSub(j, "المحطة") || containsSub(j, "المحطه") || containsSub(j, "سيدي جابر")) &&
			!containsSub(j, "ميني") && containsSub(r.SourceHint, "sell_out")
	})
	miniS := find(func(r ProposalRow) bool {
		j := stringsJoin(r.RawNames) + r.DisplayName
		return containsSub(j, "سيدي جابر") && containsSub(j, "ميني")
	})

	if riviera == nil || !containsSub(riviera.SourceHint, "sell_in") || !containsSub(riviera.SourceHint, "sell_out") {
		t.Fatalf("إبراهيمية/ريفيرا merge missing: %+v rows=%+v", riviera, report.Rows)
	}
	if !riviera.HasCareLine {
		t.Fatalf("ريفيرا care must merge: %+v", riviera)
	}
	if andlus == nil || !containsSub(andlus.SourceHint, "sell_in") || !containsSub(andlus.SourceHint, "sell_out") {
		t.Fatalf("دمنهور=الأندلس merge missing: %+v", andlus)
	}
	if !andlus.HasCareLine {
		t.Fatalf("دمنهور care must merge into الأندلس: %+v", andlus)
	}
	if station == nil || !containsSub(station.SourceHint, "sell_in") || !containsSub(station.SourceHint, "sell_out") {
		t.Fatalf("سيدي جابر=المحطة merge missing: %+v", station)
	}
	if !station.HasCareLine {
		t.Fatalf("سيدي جابر care must merge into المحطة: %+v", station)
	}
	for _, p := range []struct {
		name string
		row  *ProposalRow
	}{
		{"إبراهيمية ميني", miniIbr},
		{"الاستاد", stad},
		{"سيدي جابر ميني", miniS},
	} {
		if p.row == nil {
			t.Fatalf("missing separate branch %s in %+v", p.name, report.Rows)
		}
	}
	codes := map[string]string{}
	for _, p := range []*ProposalRow{riviera, miniIbr, andlus, stad, station, miniS} {
		if prev, ok := codes[p.BranchCode]; ok {
			t.Fatalf("codes collided: %s and %s both %s", prev, p.DisplayName, p.BranchCode)
		}
		codes[p.BranchCode] = p.DisplayName
	}
	if report.BranchCount != 6 {
		t.Fatalf("want 6 proposed branches (3 merges + 3 separate), got %d rows=%+v", report.BranchCount, report.Rows)
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

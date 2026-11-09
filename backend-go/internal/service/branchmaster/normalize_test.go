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

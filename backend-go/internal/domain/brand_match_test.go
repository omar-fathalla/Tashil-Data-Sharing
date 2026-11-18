package domain

import "testing"

func TestBrandLabelMatches(t *testing.T) {
	cases := []struct {
		inferred, filter string
		want             bool
	}{
		{"ديفا (Diva)", "ديفا (Diva)", true},
		{"ديفا (Diva)", "Diva", true},
		{"ديفا (Diva)", "ديفا", true},
		{"ديفا (Diva)", "diva", true},
		{"فلڤيتا (Velveta)", "فلفيتا", true},
		{"فلڤيتا (Velveta)", "Velveta", true},
		{"فلڤيتا (Velveta)", "فلڤيتا (Velveta)", true},
		{"كلوريل (Clorel)", "Clorel", true},
		{"ماكسيل (Maxell)", "Maxell", true},
		{"فيبا (Feba)", "Feba", true},
		{"ديفا (Diva)", "Velveta", false},
		{"فلڤيتا (Velveta)", "Diva", false},
		{"ديفا (Diva)", "ديفاتول", false},
		{"ديفا (Diva)", "all", true},
		{"ديفا (Diva)", "", true},
		{"أصناف عامة", "Diva", false},
	}
	for _, tc := range cases {
		got := BrandLabelMatches(tc.inferred, tc.filter)
		if got != tc.want {
			t.Errorf("BrandLabelMatches(%q, %q)=%v want %v", tc.inferred, tc.filter, got, tc.want)
		}
	}
}

func TestInferBrandFromItemName_DivatolMapsToDiva(t *testing.T) {
	got := InferBrandFromItemName("ديفاتول مطهر 750 مل", "")
	if got != "ديفا (Diva)" {
		t.Fatalf("Divatol SKU should map to Diva brand, got %q", got)
	}
	got = InferBrandFromItemName("شامبو ديفا للشعر 400 مل", "")
	if got != "ديفا (Diva)" {
		t.Fatalf("Diva SKU: got %q", got)
	}
	got = InferBrandFromItemName("فلفيتا جيل للحرير 750 مل", "")
	if got != "فلڤيتا (Velveta)" {
		t.Fatalf("Velveta SKU: got %q", got)
	}
}

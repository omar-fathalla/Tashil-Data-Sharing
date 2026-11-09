package competitorsuggest

import (
	"strings"
	"testing"
)

func TestManualGelFourWayGroupApproved(t *testing.T) {
	eq := DefaultCategoryEquivalence()
	variants := []string{
		"مساحيق جيل يدوى",
		"مسحوق جيل يدوى",
		"مساحيق جيل يدوي",
		"مسحوق جيل يدوي",
	}
	canon := CanonicalCategory(variants[0], eq)
	for _, v := range variants {
		if CanonicalCategory(v, eq) != canon {
			t.Fatalf("%q should canonicalize with group to %q, got %q", v, canon, CanonicalCategory(v, eq))
		}
	}
	own := SkuCandidate{Barcode: "O", SKUName: "جيل يدوى", Category: "مساحيق جيل يدوى", IsOwnBrand: true}
	pool := []SkuCandidate{
		{Barcode: "A", SKUName: "مسحوق يدوى", Category: "مسحوق جيل يدوى"},
		{Barcode: "B", SKUName: "مساحيق يدوي", Category: "مساحيق جيل يدوي"},
		{Barcode: "C", SKUName: "مسحوق يدوي", Category: "مسحوق جيل يدوي"},
		{Barcode: "X", SKUName: "اتوماتيك", Category: "مساحيق جيل اتوماتيك"},
	}
	got := PreFilterCandidates(own, pool, eq)
	if len(got) != 3 {
		t.Fatalf("want 3 manual-gel candidates, got %#v", got)
	}
	for _, g := range got {
		if g.Candidate.Barcode == "X" {
			t.Fatal("اتوماتيك must stay a different category")
		}
	}
}

func TestRejectedEquivalencePairsStaySeparate(t *testing.T) {
	eq := DefaultCategoryEquivalence()
	cases := []struct {
		own, other string
	}{
		{"هاند وواش", "هاند وواش مطهر"},
		{"اقراص غسالات اطباق", "زيت غسالات اطباق"},
		{"اقراص غسالات اطباق", "مسحوق غسالات اطباق"},
		{"اقراص غسالات اطباق", "ملح غسالات اطباق"},
		{"زيت غسالات اطباق", "مسحوق غسالات اطباق"},
		{"زيت غسالات اطباق", "ملح غسالات اطباق"},
		{"مسحوق غسالات اطباق", "ملح غسالات اطباق"},
	}
	for _, c := range cases {
		if SameCategory(c.own, c.other, eq) {
			t.Fatalf("rejected merge must stay separate: %q vs %q", c.own, c.other)
		}
		own := SkuCandidate{Barcode: "O", SKUName: "own", Category: c.own, IsOwnBrand: true}
		pool := []SkuCandidate{{Barcode: "C", SKUName: "cand", Category: c.other}}
		if got := PreFilterCandidates(own, pool, eq); len(got) != 0 {
			t.Fatalf("pre-filter must drop rejected pair %q/%q, got %#v", c.own, c.other, got)
		}
	}
	if len(RejectedCategoryEquivalencePairs) != 7 {
		t.Fatalf("want 7 documented rejected pairs, got %d", len(RejectedCategoryEquivalencePairs))
	}
	for _, p := range PendingCategoryEquivalencePairs {
		for _, r := range RejectedCategoryEquivalencePairs {
			if (p[0] == r[0] && p[1] == r[1]) || (p[0] == r[1] && p[1] == r[0]) {
				t.Fatalf("rejected pair still in pending: %#v", p)
			}
		}
		joined := p[0] + "|" + p[1]
		if strings.Contains(joined, "يدو") {
			t.Fatalf("manual gel يدوى/يدوي must be approved, not pending: %#v", p)
		}
	}
}

func TestPendingEmptyAfterOwnerDecisions(t *testing.T) {
	if len(PendingCategoryEquivalencePairs) != 0 {
		t.Fatalf("pending should be empty after owner decisions, got %#v", PendingCategoryEquivalencePairs)
	}
}

package competitorsuggest

import (
	"context"
	"testing"
)

func TestParseAndValidateRankRejectsHallucinated(t *testing.T) {
	allowed := map[string]bool{"C1": true, "C2": true}
	raw := `{"suggestions":[
		{"competitor_barcode":"C1","reason_ar":"مناسب","confidence":0.9,"rank":1},
		{"competitor_barcode":"HALLUCINATED","reason_ar":"مخترع","confidence":0.99,"rank":2},
		{"competitor_barcode":"C2","reason_ar":"ثاني","confidence":0.7,"rank":3},
		{"competitor_barcode":"C1","reason_ar":"مكرر","confidence":0.5,"rank":4}
	]}`
	got, err := ParseAndValidateRank(raw, allowed)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 after dropping hallucinated+dup, got %#v", got)
	}
	if got[0].CompetitorBarcode != "C1" || got[1].CompetitorBarcode != "C2" {
		t.Fatalf("order/barcodes: %#v", got)
	}
	if got[0].Rank != 1 || got[1].Rank != 2 {
		t.Fatalf("ranks renumbered: %#v", got)
	}
}

func TestRankNoAIWhenNoCandidates(t *testing.T) {
	called := false
	r := &GeminiRanker{
		UseMock: true,
		CallJSON: func(ctx context.Context, model, prompt string) (string, TokenUsage, error) {
			called = true
			return "", TokenUsage{}, nil
		},
	}
	own := SkuCandidate{Barcode: "O", SKUName: "عناية شخصية", Category: "عناية شخصية"}
	got, _, err := r.Rank(context.Background(), own, nil)
	if err != nil {
		t.Fatal(err)
	}
	if called {
		t.Fatal("must not call AI when candidate list empty (e.g. عناية شخصية)")
	}
	if len(got) != 0 {
		t.Fatalf("want empty, got %#v", got)
	}
}

func TestMockRankOnlyFromCandidates(t *testing.T) {
	r := &GeminiRanker{UseMock: true}
	own := SkuCandidate{Barcode: "O", SKUName: "فيبا 3 كجم", Category: "صابون سائل اطباق"}
	cands := []PrefScore{
		{Candidate: SkuCandidate{Barcode: "A", SKUName: "بريل"}},
		{Candidate: SkuCandidate{Barcode: "B", SKUName: "فييري"}},
		{Candidate: SkuCandidate{Barcode: "C", SKUName: "وافر"}},
		{Candidate: SkuCandidate{Barcode: "D", SKUName: "زيادة"}},
	}
	got, _, err := r.Rank(context.Background(), own, cands)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != MaxRank {
		t.Fatalf("want %d, got %d", MaxRank, len(got))
	}
	for _, s := range got {
		if s.CompetitorBarcode != "A" && s.CompetitorBarcode != "B" && s.CompetitorBarcode != "C" {
			t.Fatalf("unexpected barcode %s", s.CompetitorBarcode)
		}
	}
}

func TestDefaultCategoryEquivalenceApprovedPairs(t *testing.T) {
	eq := DefaultCategoryEquivalence()
	// #1 اتوماتيك
	ownAuto := SkuCandidate{Barcode: "O", SKUName: "جيل", Category: "مساحيق جيل اتوماتيك", IsOwnBrand: true}
	poolAuto := []SkuCandidate{
		{Barcode: "A", SKUName: "منافس مسحوق", Category: "مسحوق جيل اتوماتيك"},
		{Barcode: "B", SKUName: "يدوى", Category: "مساحيق جيل يدوى"},
		{Barcode: "C", SKUName: "يدوي", Category: "مساحيق جيل يدوي"},
	}
	got := PreFilterCandidates(ownAuto, poolAuto, eq)
	if len(got) != 1 || got[0].Candidate.Barcode != "A" {
		t.Fatalf("approved gel-auto pair only, got %#v", got)
	}
	// #2 يدوى (approved spelling) — يدوي (dot ي) still NOT merged
	ownManual := SkuCandidate{Barcode: "M", SKUName: "جيل يدوى", Category: "مساحيق جيل يدوى", IsOwnBrand: true}
	poolManual := []SkuCandidate{
		{Barcode: "D", SKUName: "منافس مسحوق يدوى", Category: "مسحوق جيل يدوى"},
		{Barcode: "E", SKUName: "منافس يدوي", Category: "مساحيق جيل يدوي"},
		{Barcode: "F", SKUName: "اتوماتيك", Category: "مساحيق جيل اتوماتيك"},
	}
	got = PreFilterCandidates(ownManual, poolManual, eq)
	if len(got) != 1 || got[0].Candidate.Barcode != "D" {
		t.Fatalf("approved gel-manual pair only (not يدوي/اتوماتيك), got %#v", got)
	}
	if len(PendingCategoryEquivalencePairs) == 0 {
		t.Fatal("unapproved يدوي lookalikes must remain listed as pending")
	}
}

package competitorsuggest

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestGeminiRankerTrimsAPIKeyNewlineBeforeHeader(t *testing.T) {
	var gotKey string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("x-goog-api-key")
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"candidates":[{"content":{"parts":[{"text":"{\"suggestions\":[{\"competitor_barcode\":\"A\",\"reason_ar\":\"مناسب\",\"confidence\":0.9,\"rank\":1}]}"}]}}]}`)
	}))
	defer srv.Close()

	r := &GeminiRanker{
		APIKey:     "secret-key-with-newline\n",
		Model:      "gemini-3.8-flash",
		APIBase:    srv.URL,
		HTTPClient: srv.Client(),
	}
	own := SkuCandidate{Barcode: "O", SKUName: "فيبا", Category: "صابون سائل اطباق"}
	cands := []PrefScore{{Candidate: SkuCandidate{Barcode: "A", SKUName: "بريل"}}}
	got, _, err := r.Rank(context.Background(), own, cands)
	if err != nil {
		t.Fatalf("Rank with trailing newline key should trim and succeed: %v", err)
	}
	if gotKey != "secret-key-with-newline" {
		t.Fatalf("header key not trimmed: %q", gotKey)
	}
	if len(got) != 1 || got[0].CompetitorBarcode != "A" {
		t.Fatalf("unexpected rank result: %#v", got)
	}
}

func TestGeminiRankerFallsBackOnModelNotFound(t *testing.T) {
	var models []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// path: /v1beta/models/{model}:generateContent
		path := r.URL.Path
		models = append(models, path)
		if strings.Contains(path, "missing-model") {
			w.WriteHeader(http.StatusNotFound)
			_, _ = io.WriteString(w, `{"error":{"message":"models/missing-model is not found"}}`)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"candidates":[{"content":{"parts":[{"text":"{\"suggestions\":[{\"competitor_barcode\":\"A\",\"reason_ar\":\"مناسب\",\"confidence\":0.8,\"rank\":1}]}"}]}}]}`)
	}))
	defer srv.Close()

	r := &GeminiRanker{
		APIKey:     "k",
		Model:      "missing-model",
		Tier2Model: "gemini-pro-latest",
		APIBase:    srv.URL,
		HTTPClient: srv.Client(),
	}
	own := SkuCandidate{Barcode: "O", SKUName: "فيبا", Category: "صابون سائل اطباق"}
	cands := []PrefScore{{Candidate: SkuCandidate{Barcode: "A", SKUName: "بريل"}}}
	got, _, err := r.Rank(context.Background(), own, cands)
	if err != nil {
		t.Fatal(err)
	}
	if len(models) != 2 {
		t.Fatalf("want primary then tier2, got %v", models)
	}
	if !strings.Contains(models[0], "missing-model") || !strings.Contains(models[1], "gemini-pro-latest") {
		t.Fatalf("fallback order: %v", models)
	}
	if len(got) != 1 {
		t.Fatalf("want 1 suggestion after fallback, got %#v", got)
	}
}

func TestGeminiRankerFallsBackOnPrimaryTimeout(t *testing.T) {
	var models []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		models = append(models, path)
		if strings.Contains(path, "slow-primary") {
			// Simulate a slow/hung primary without blocking httptest.Close.
			select {
			case <-r.Context().Done():
			case <-time.After(2 * time.Second):
			}
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"candidates":[{"content":{"parts":[{"text":"{\"suggestions\":[{\"competitor_barcode\":\"A\",\"reason_ar\":\"مناسب\",\"confidence\":0.8,\"rank\":1}]}"}]}}]}`)
	}))
	defer srv.Close()

	r := &GeminiRanker{
		APIKey:     "k",
		Model:      "slow-primary",
		Tier2Model: "gemini-pro-latest",
		APIBase:    srv.URL,
		HTTPClient: srv.Client(),
	}
	own := SkuCandidate{Barcode: "O", SKUName: "فيبا", Category: "صابون سائل اطباق"}
	cands := []PrefScore{{Candidate: SkuCandidate{Barcode: "A", SKUName: "بريل"}}}
	ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
	defer cancel()
	got, _, err := r.Rank(ctx, own, cands)
	if err != nil {
		t.Fatalf("tier2 should succeed after primary timeout: %v (models=%v)", err, models)
	}
	if len(models) < 2 {
		t.Fatalf("want primary then tier2, got %v", models)
	}
	if !strings.Contains(models[0], "slow-primary") || !strings.Contains(models[len(models)-1], "gemini-pro-latest") {
		t.Fatalf("fallback order: %v", models)
	}
	if len(got) != 1 || got[0].CompetitorBarcode != "A" {
		t.Fatalf("unexpected result: %#v", got)
	}
}

func TestGeminiRankerOmitsTemperatureAndSetsThinkingLow(t *testing.T) {
	var rawBody []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rawBody, _ = io.ReadAll(io.LimitReader(r.Body, 1<<20))
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"candidates":[{"content":{"parts":[{"text":"{\"suggestions\":[]}"}]}}]}`)
	}))
	defer srv.Close()

	r := &GeminiRanker{
		APIKey:     "k",
		Model:      "gemini-3.8-flash",
		APIBase:    srv.URL,
		HTTPClient: srv.Client(),
	}
	own := SkuCandidate{Barcode: "O", SKUName: "فيبا", Category: "صابون سائل اطباق"}
	cands := []PrefScore{{Candidate: SkuCandidate{Barcode: "A", SKUName: "بريل"}}}
	_, _, err := r.Rank(context.Background(), own, cands)
	if err != nil {
		t.Fatal(err)
	}
	body := string(rawBody)
	if strings.Contains(body, `"temperature"`) {
		t.Fatalf("Gemini 3.x request must omit temperature, got %s", body)
	}
	if !strings.Contains(body, `"thinkingLevel":"low"`) {
		t.Fatalf("want thinkingLevel=low for latency-critical rank, got %s", body)
	}
}

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
	// #2 full manual gel group (يدوى/يدوي × singular/plural)
	ownManual := SkuCandidate{Barcode: "M", SKUName: "جيل يدوى", Category: "مساحيق جيل يدوى", IsOwnBrand: true}
	poolManual := []SkuCandidate{
		{Barcode: "D", SKUName: "منافس مسحوق يدوى", Category: "مسحوق جيل يدوى"},
		{Barcode: "E", SKUName: "منافس يدوي", Category: "مساحيق جيل يدوي"},
		{Barcode: "F", SKUName: "اتوماتيك", Category: "مساحيق جيل اتوماتيك"},
	}
	got = PreFilterCandidates(ownManual, poolManual, eq)
	if len(got) != 2 {
		t.Fatalf("manual gel group should include يدوى+يدوي, got %#v", got)
	}
	for _, g := range got {
		if g.Candidate.Barcode == "F" {
			t.Fatal("اتوماتيك must not merge with يدوى")
		}
	}
}

package sellinassist

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestSuggestLayoutDeterministicGPSOP(t *testing.T) {
	s := New("", "", true)
	sample := [][]string{
		{"SOP Number", "Document Date", "Customer Name", "Item Number", "Item Description", "QTY", "Extended Price"},
		{"SOP-1", "2026-01-15", "عائله فتح الله ماركت - مخزن", "6223000231500", "Maxell", "10", "1000"},
	}
	sug, err := s.SuggestLayout(context.Background(), "tenant-adeco", "in26.xlsx", sample)
	if err != nil {
		t.Fatal(err)
	}
	if sug.Kind != KindLayout || sug.Status != StatusPending {
		t.Fatalf("unexpected suggestion: %+v", sug)
	}
	if sug.MappingSource != SourceDeterministic {
		t.Fatalf("source=%s want deterministic", sug.MappingSource)
	}
	if sug.Layout != "gp_sop" {
		t.Fatalf("layout=%s want gp_sop", sug.Layout)
	}
	if sug.Confidence < 0.5 {
		t.Fatalf("confidence too low: %v", sug.Confidence)
	}
	if !strings.Contains(sug.ReasonAR, "اقتراح") && !strings.Contains(sug.ReasonAR, "مقترح") {
		t.Fatalf("reason should be Arabic advisory: %s", sug.ReasonAR)
	}
}

func TestSuggestLayoutAIEscalation(t *testing.T) {
	s := New("fake-key", "tier1-model", false).WithCaller(func(ctx context.Context, model, prompt string) (string, error) {
		if model != "tier1-model" {
			t.Fatalf("unexpected model %s", model)
		}
		if !strings.Contains(prompt, "Sell-In") {
			t.Fatal("prompt missing Sell-In context")
		}
		body, _ := json.Marshal(layoutAIResponse{
			HeaderRowIndex: 1,
			Layout:         "raw_plan",
			Confidence:     0.91,
			ReasonAR:       "صف العناوين في الصف التاني",
			Columns: []ColumnRole{
				{Index: 0, Role: roleMonth, Label: "Month"},
				{Index: 1, Role: roleCustomer, Label: "Customer"},
				{Index: 2, Role: roleNetQ, Label: "Net Q"},
				{Index: 3, Role: roleNetV, Label: "Net V"},
			},
		})
		return string(body), nil
	})
	// Ambiguous sample so deterministic confidence is low / unknown.
	sample := [][]string{
		{"A", "B", "C", "D"},
		{"x", "y", "z", "w"},
	}
	sug, err := s.SuggestLayout(context.Background(), "tenant-adeco", "plan.xlsx", sample)
	if err != nil {
		t.Fatal(err)
	}
	if sug.MappingSource != SourceAI || sug.Layout != "raw_plan" || sug.ModelUsed != "tier1-model" {
		t.Fatalf("want AI raw_plan, got %+v", sug)
	}
}

func TestSuggestCustomerChainsSkipsResolvedAndRequiresApproval(t *testing.T) {
	s := New("", "", true)
	customers := []string{
		"فتح الله بيت الجمله للتجاره والتوريدات ش م م - فرع 3", // built-in → beet-elgomla
		"فرع فتح الله - كيه اتش جمله ماركت",                     // needs map suggestion → gomla
		"فرع فتح الله - زهران",                                 // needs map → zahran
		"عائله فتح الله ماركت - مخزن الافوجادو",                 // stays fathalla, no heuristic
	}
	sugs, err := s.SuggestCustomerChains(context.Background(), "tenant-adeco", "fathalla", customers)
	if err != nil {
		t.Fatal(err)
	}
	if len(sugs) < 2 {
		t.Fatalf("expected gomla+zahran suggestions, got %d: %+v", len(sugs), sugs)
	}
	chains := map[string]bool{}
	for _, sug := range sugs {
		if sug.Kind != KindCustomerChain || sug.Status != StatusPending {
			t.Fatalf("bad sug: %+v", sug)
		}
		if sug.EnvFragment == "" {
			t.Fatalf("missing env fragment: %+v", sug)
		}
		needle, chain, ok := ParseEnvFragment(sug.EnvFragment)
		if !ok || needle == "" || chain == "" {
			t.Fatalf("invalid fragment %q", sug.EnvFragment)
		}
		chains[chain] = true
		// Must NOT auto-apply: still pending.
		if sug.Status == StatusApproved {
			t.Fatal("suggestions must not auto-approve")
		}
	}
	if !chains["gomla"] || !chains["zahran"] {
		t.Fatalf("expected gomla and zahran, got %v", chains)
	}
	// Built-in beet-elgomla customer must not produce a redundant pending rule.
	for _, sug := range sugs {
		if sug.SuggestedChain == "beet-elgomla" {
			t.Fatalf("should skip already-resolved beet-elgomla: %+v", sug)
		}
	}

	// Approve one — still no prod mutation; only decision recorded.
	id := sugs[0].ID
	decided, err := s.Approve(id, "mohamed@test")
	if err != nil {
		t.Fatal(err)
	}
	if decided.Status != StatusApproved || decided.DecidedBy != "mohamed@test" {
		t.Fatalf("approve failed: %+v", decided)
	}
	frags := s.ApprovedEnvFragments("tenant-adeco")
	if len(frags) != 1 || frags[0] != decided.EnvFragment {
		t.Fatalf("fragments=%v", frags)
	}
	m := s.GetMetrics()
	if m.Approved != 1 || m.Pending < 1 || m.ApprovalRate <= 0 {
		t.Fatalf("metrics=%+v", m)
	}
}

func TestApproveRejectIdempotentGuard(t *testing.T) {
	s := New("", "", true)
	sugs, _ := s.SuggestCustomerChains(context.Background(), "tenant-adeco", "fathalla",
		[]string{"فرع فتح الله - كيه اتش جمله ماركت"})
	if len(sugs) != 1 {
		t.Fatalf("got %d", len(sugs))
	}
	if _, err := s.Approve(sugs[0].ID, "a"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Approve(sugs[0].ID, "a"); err == nil {
		t.Fatal("second approve must fail")
	}
	if _, err := s.Reject(sugs[0].ID, "a"); err == nil {
		t.Fatal("reject after approve must fail")
	}
}

func TestGeminiAPIKeyNeverInURL(t *testing.T) {
	var sawURL string
	payload := `{"candidates":[{"content":{"parts":[{"text":"{\"header_row_index\":0,\"layout\":\"long\",\"confidence\":0.9,\"reason_ar\":\"تم\",\"columns\":[{\"index\":0,\"role\":\"customer\"}]}"}]}}]}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sawURL = r.URL.String()
		if r.URL.Query().Get("key") != "" {
			t.Errorf("API key leaked into URL: %s", r.URL.String())
		}
		if r.Header.Get("x-goog-api-key") != "secret-key" {
			t.Errorf("missing api key header")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(payload))
	}))
	defer srv.Close()

	s := New("secret-key", "flash", false).WithAPIBase(srv.URL)
	raw, err := s.callGeminiJSON(context.Background(), "flash", "hello", sellInLayoutSchemaJSON, "f.xlsx")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(raw, "long") {
		t.Fatalf("raw=%s", raw)
	}
	if strings.Contains(sawURL, "secret-key") {
		t.Fatalf("key in URL path: %s", sawURL)
	}
}

func TestParseEnvFragment(t *testing.T) {
	n, c, ok := ParseEnvFragment("كيه اتش=gomla")
	if !ok || n != "كيه اتش" || c != "gomla" {
		t.Fatalf("%q %q %v", n, c, ok)
	}
	if _, _, ok := ParseEnvFragment("x=unknown-chain"); ok {
		t.Fatal("unknown chain must fail")
	}
}

func TestTenantIsolation(t *testing.T) {
	s := New("", "", true)
	_, _ = s.SuggestCustomerChains(context.Background(), "tenant-a", "fathalla",
		[]string{"فرع فتح الله - كيه اتش جمله ماركت"})
	_, _ = s.SuggestCustomerChains(context.Background(), "tenant-b", "fathalla",
		[]string{"فرع فتح الله - زهران"})
	if len(s.List("tenant-a", "")) != 1 || len(s.List("tenant-b", "")) != 1 {
		t.Fatalf("a=%d b=%d", len(s.List("tenant-a", "")), len(s.List("tenant-b", "")))
	}
	if len(s.List("tenant-a", StatusPending)) != 1 {
		t.Fatal("filter pending")
	}
}

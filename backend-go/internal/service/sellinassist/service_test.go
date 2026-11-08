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
	decided, err := s.Approve(id, "tenant-adeco", "mohamed@test")
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
	m := s.GetMetrics("tenant-adeco")
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
	if _, err := s.Approve(sugs[0].ID, "tenant-adeco", "a"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Approve(sugs[0].ID, "tenant-adeco", "a"); err == nil {
		t.Fatal("second approve must fail")
	}
	if _, err := s.Reject(sugs[0].ID, "tenant-adeco", "a"); err == nil {
		t.Fatal("reject after approve must fail")
	}
}

func TestCrossTenantDecideNoDisclosureNoMutation(t *testing.T) {
	s := New("", "", true)
	sugs, err := s.SuggestCustomerChains(context.Background(), "tenant-a", "fathalla",
		[]string{"فرع فتح الله - كيه اتش جمله ماركت"})
	if err != nil || len(sugs) != 1 {
		t.Fatalf("setup: %v %+v", err, sugs)
	}
	id := sugs[0].ID
	before := s.List("tenant-a", StatusPending)

	got, err := s.Approve(id, "tenant-b", "attacker@x")
	if err != ErrNotFound || got != nil {
		t.Fatalf("cross-tenant approve: got=%v err=%v want ErrNotFound", got, err)
	}
	got, err = s.Reject(id, "tenant-b", "attacker@x")
	if err != ErrNotFound || got != nil {
		t.Fatalf("cross-tenant reject: got=%v err=%v want ErrNotFound", got, err)
	}
	after := s.List("tenant-a", StatusPending)
	if len(after) != len(before) || after[0].Status != StatusPending {
		t.Fatalf("state changed: before=%+v after=%+v", before, after)
	}
	// Metrics must be tenant-scoped: tenant-b sees nothing.
	if m := s.GetMetrics("tenant-b"); m.Suggested != 0 || m.Pending != 0 {
		t.Fatalf("tenant-b metrics leaked: %+v", m)
	}
	if m := s.GetMetrics("tenant-a"); m.Pending != 1 || m.Approved != 0 {
		t.Fatalf("tenant-a metrics=%+v", m)
	}
}

func TestMatchRoleNetVAndBarcodePrecedence(t *testing.T) {
	if got := matchRole(normalizeHeaderLabel("Net V")); got != roleNetV {
		t.Fatalf("Net V → %s want net_v", got)
	}
	if got := matchRole(normalizeHeaderLabel("صافي القيمه")); got != roleNetV {
		t.Fatalf("صافي القيمه → %s want net_v", got)
	}
	if got := matchRole(normalizeHeaderLabel("Barcode")); got != roleBarcode {
		t.Fatalf("Barcode → %s want barcode (not item_code)", got)
	}
	if got := matchRole(normalizeHeaderLabel("الباركود")); got != roleBarcode {
		t.Fatalf("الباركود → %s want barcode", got)
	}
	if got := matchRole(normalizeHeaderLabel("Extended Price")); got != roleValue {
		t.Fatalf("Extended Price → %s want value", got)
	}
	if got := matchRole(normalizeHeaderLabel("Item Number")); got != roleItemCode {
		t.Fatalf("Item Number → %s want item_code", got)
	}
}

func TestValidateLayoutAIRejectsBadPayload(t *testing.T) {
	ok := &layoutAIResponse{
		HeaderRowIndex: 0, Layout: "long", Confidence: 0.9, ReasonAR: "تم",
		Columns: []ColumnRole{{Index: 0, Role: roleCustomer}},
	}
	if err := validateLayoutAI(ok, 3); err != nil {
		t.Fatal(err)
	}
	bad := *ok
	bad.Confidence = 0.2
	if err := validateLayoutAI(&bad, 3); err == nil {
		t.Fatal("low confidence must fail")
	}
	bad = *ok
	bad.Layout = "pivot"
	if err := validateLayoutAI(&bad, 3); err == nil {
		t.Fatal("bad layout must fail")
	}
	bad = *ok
	bad.HeaderRowIndex = 99
	if err := validateLayoutAI(&bad, 3); err == nil {
		t.Fatal("oob header must fail")
	}
	bad = *ok
	bad.Columns = []ColumnRole{{Index: 0, Role: "made_up"}}
	if err := validateLayoutAI(&bad, 3); err == nil {
		t.Fatal("bad role must fail")
	}
	bad = *ok
	bad.ReasonAR = "  "
	if err := validateLayoutAI(&bad, 3); err == nil {
		t.Fatal("empty reason must fail")
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

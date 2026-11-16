package handlers

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

type recordingApplier struct {
	tenant   string
	profiles []domain.ChainDiscountProfile
	calls    int
}

func (a *recordingApplier) SetChainDiscountProfiles(tenantID string, p []domain.ChainDiscountProfile) {
	a.tenant, a.profiles, a.calls = tenantID, p, a.calls+1
}

func cdMux(h *ChainDiscountHandler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/product-master/chain-discounts", h.HandleGet)
	mux.HandleFunc("PUT /api/v1/product-master/chain-discounts", h.HandlePut)
	return mux
}

func TestChainDiscountProfilesCRUDAuditAndTenantIsolation(t *testing.T) {
	fs := firestore.NewClient("", true)
	app := &recordingApplier{}
	mux := cdMux(NewChainDiscountHandler(fs, fs, app))
	admin := &domain.UserClaims{UserID: "u1", Email: "admin@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleAdmin}
	other := &domain.UserClaims{UserID: "u2", Email: "x@pepsi.test", TenantID: "tenant-pepsi", Role: domain.RoleAdmin}
	kam := &domain.UserClaims{UserID: "u3", Email: "kam@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleChainKAM, AssignedChain: "fathalla"}

	// Empty by default, with the 10% / 0% defaults reported.
	rec, out := tmDo(t, mux, admin, "GET", "/api/v1/product-master/chain-discounts", nil)
	if rec.Code != 200 || len(out["profiles"].([]interface{})) != 0 || out["default_invoice_discount_pct"].(float64) != 10 || out["default_additional_discount_pct"].(float64) != 0 || out["default_vat_rate_pct"].(float64) != 14 {
		t.Fatalf("unexpected empty GET: %d %v", rec.Code, out)
	}

	// Add two.
	body := map[string]interface{}{"profiles": []map[string]interface{}{
		{"chain": "Kazyon", "invoice_discount_pct": 12, "additional_discount_pct": 2},
		{"chain": "fathalla", "invoice_discount_pct": 10, "additional_discount_pct": 0},
	}}
	rec, out = tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", body)
	if rec.Code != 200 || len(out["profiles"].([]interface{})) != 2 {
		t.Fatalf("PUT failed: %d %v", rec.Code, out)
	}
	if app.calls == 0 || len(app.profiles) != 2 {
		t.Fatalf("profiles must be applied to CPFR cost")
	}

	// Edit one, delete the other.
	body = map[string]interface{}{"profiles": []map[string]interface{}{{"chain": "kazyon", "invoice_discount_pct": 15, "additional_discount_pct": 2}}}
	rec, out = tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", body)
	ps := out["profiles"].([]interface{})
	if rec.Code != 200 || len(ps) != 1 || ps[0].(map[string]interface{})["invoice_discount_pct"].(float64) != 15 {
		t.Fatalf("edit/delete failed: %d %v", rec.Code, out)
	}

	// Validation.
	for _, bad := range []interface{}{
		[]map[string]interface{}{{"chain": "", "invoice_discount_pct": 5}},
		[]map[string]interface{}{{"chain": "a", "invoice_discount_pct": 100}},
		[]map[string]interface{}{{"chain": "a", "additional_discount_pct": -1}},
		[]map[string]interface{}{{"chain": "a"}, {"chain": " A "}},
	} {
		if rec, _ := tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", map[string]interface{}{"profiles": bad}); rec.Code != 400 {
			t.Fatalf("expected 400 for %v, got %d", bad, rec.Code)
		}
	}

	// RBAC: KAM can read but not write; no claims -> 401.
	if rec, _ := tmDo(t, mux, kam, "GET", "/api/v1/product-master/chain-discounts", nil); rec.Code != 200 {
		t.Fatalf("KAM read: %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, kam, "PUT", "/api/v1/product-master/chain-discounts", body); rec.Code != 403 {
		t.Fatalf("KAM write must be 403, got %d", rec.Code)
	}
	if rec, _ := tmDo(t, mux, nil, "GET", "/api/v1/product-master/chain-discounts", nil); rec.Code != 401 {
		t.Fatalf("no claims must be 401, got %d", rec.Code)
	}

	// Tenant isolation.
	_, out = tmDo(t, mux, other, "GET", "/api/v1/product-master/chain-discounts", nil)
	if len(out["profiles"].([]interface{})) != 0 {
		t.Fatalf("other tenant must not see adeco profiles: %v", out)
	}

	// Audit log entries.
	logs, _ := fs.GetAuditLogs(context.Background(), "tenant-adeco", "chain_discounts_update", 10)
	if len(logs) < 2 {
		t.Fatalf("expected audit entries, got %d", len(logs))
	}
	joined := ""
	for _, l := range logs {
		joined += l.Details + "\n"
	}
	if !strings.Contains(joined, "added Kazyon") || !strings.Contains(joined, "deleted fathalla") || !strings.Contains(joined, "updated kazyon invoice 12.00%→15.00%") {
		t.Fatalf("audit details missing changes:\n%s", joined)
	}
}

// blockingApplier stands in for the analytics client while a long request holds its write lock.
type blockingApplier struct{ release chan struct{} }

func (a *blockingApplier) SetChainDiscountProfiles(string, []domain.ChainDiscountProfile) {
	<-a.release
}

func TestChainDiscountGetDoesNotWaitOnApplier(t *testing.T) {
	fs := firestore.NewClient("", true)
	admin := &domain.UserClaims{UserID: "u1", Email: "admin@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleAdmin}
	if err := fs.SaveChainDiscountProfiles(context.Background(), &domain.ChainDiscountProfiles{
		TenantID: "tenant-adeco",
		Profiles: []domain.ChainDiscountProfile{{Chain: "kazyon", InvoiceDiscountPct: 12}},
	}); err != nil {
		t.Fatal(err)
	}
	app := &blockingApplier{release: make(chan struct{})}
	defer close(app.release)
	mux := cdMux(NewChainDiscountHandler(fs, fs, app))

	done := make(chan map[string]interface{}, 1)
	go func() {
		rec, out := tmDo(t, mux, admin, "GET", "/api/v1/product-master/chain-discounts", nil)
		if rec.Code != 200 {
			t.Errorf("GET: %d %v", rec.Code, out)
		}
		done <- out
	}()
	select {
	case out := <-done:
		if ps, _ := out["profiles"].([]interface{}); len(ps) != 1 {
			t.Fatalf("GET profiles: %v", out)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("GET blocked on the applier (analytics write lock)")
	}
}

type slowChainRepo struct{ firestore.ChainDiscountRepository }

func (slowChainRepo) GetChainDiscountProfiles(ctx context.Context, _ string) (*domain.ChainDiscountProfiles, error) {
	<-ctx.Done()
	return nil, ctx.Err()
}

func TestChainDiscountGetTimesOutWithGatewayTimeout(t *testing.T) {
	prev := chainDiscountGetTimeout
	chainDiscountGetTimeout = 50 * time.Millisecond
	defer func() { chainDiscountGetTimeout = prev }()

	mux := cdMux(NewChainDiscountHandler(slowChainRepo{}, nil, nil))
	admin := &domain.UserClaims{UserID: "u1", Email: "admin@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleAdmin}
	start := time.Now()
	rec, _ := tmDo(t, mux, admin, "GET", "/api/v1/product-master/chain-discounts", nil)
	if rec.Code != http.StatusGatewayTimeout {
		t.Fatalf("slow store must yield 504, got %d", rec.Code)
	}
	if time.Since(start) > time.Second {
		t.Fatalf("GET took %v; must be bounded by chainDiscountGetTimeout", time.Since(start))
	}
}

func TestChainDiscountVATRateRoundTripValidationAndAudit(t *testing.T) {
	fs := firestore.NewClient("", true)
	app := &recordingApplier{}
	mux := cdMux(NewChainDiscountHandler(fs, fs, app))
	admin := &domain.UserClaims{UserID: "u1", Email: "admin@adeco.test", TenantID: "tenant-adeco", Role: domain.RoleAdmin}

	put := func(profiles []map[string]interface{}) (int, map[string]interface{}) {
		rec, out := tmDo(t, mux, admin, "PUT", "/api/v1/product-master/chain-discounts", map[string]interface{}{"profiles": profiles})
		return rec.Code, out
	}
	code, out := put([]map[string]interface{}{
		{"chain": "fathalla", "invoice_discount_pct": 10, "additional_discount_pct": 20, "vat_rate_pct": 5},
		{"chain": "kazyon", "invoice_discount_pct": 10, "additional_discount_pct": 0}, // VAT not set -> default
		{"chain": "zero", "invoice_discount_pct": 10, "additional_discount_pct": 0, "vat_rate_pct": 0},
	})
	if code != 200 {
		t.Fatalf("PUT: %d %v", code, out)
	}
	byChain := map[string]map[string]interface{}{}
	for _, p := range out["profiles"].([]interface{}) {
		m := p.(map[string]interface{})
		byChain[m["chain"].(string)] = m
	}
	if byChain["fathalla"]["vat_rate_pct"].(float64) != 5 {
		t.Fatalf("VAT not stored: %v", byChain["fathalla"])
	}
	if _, set := byChain["kazyon"]["vat_rate_pct"]; set {
		t.Fatalf("unset VAT must stay unset (default applies): %v", byChain["kazyon"])
	}
	if v, set := byChain["zero"]["vat_rate_pct"]; !set || v.(float64) != 0 {
		t.Fatalf("an explicit 0%% VAT must be kept: %v", byChain["zero"])
	}
	if len(app.profiles) != 3 || app.profiles[0].VATRatePct == nil {
		t.Fatalf("applier must receive VAT: %+v", app.profiles)
	}

	// Reload (GET) keeps it.
	_, out = tmDo(t, mux, admin, "GET", "/api/v1/product-master/chain-discounts", nil)
	if len(out["profiles"].([]interface{})) != 3 {
		t.Fatalf("GET: %v", out)
	}

	// Changing only the VAT is a change (audited, applied).
	before := app.calls
	code, _ = put([]map[string]interface{}{{"chain": "fathalla", "invoice_discount_pct": 10, "additional_discount_pct": 20, "vat_rate_pct": 14}})
	if code != 200 || app.calls != before+1 {
		t.Fatalf("VAT-only change must apply: %d", code)
	}
	logs, _ := fs.GetAuditLogs(context.Background(), "tenant-adeco", "chain_discounts_update", 10)
	joined := ""
	for _, l := range logs {
		joined += l.Details + "\n"
	}
	if !strings.Contains(joined, "vat 5.00%→14.00%") || !strings.Contains(joined, "vat=5.00%") {
		t.Fatalf("audit must record VAT:\n%s", joined)
	}

	for _, bad := range []float64{-1, 100.5} {
		if code, _ := put([]map[string]interface{}{{"chain": "a", "vat_rate_pct": bad}}); code != 400 {
			t.Fatalf("vat_rate_pct %v must be rejected, got %d", bad, code)
		}
	}
	// Any value in range is accepted ("editable to any number").
	if code, _ := put([]map[string]interface{}{{"chain": "a", "invoice_discount_pct": 10, "vat_rate_pct": 22.5}}); code != 200 {
		t.Fatalf("22.5%% VAT must be accepted, got %d", code)
	}
}

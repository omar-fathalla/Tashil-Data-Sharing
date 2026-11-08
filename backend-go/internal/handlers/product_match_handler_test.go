package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

type decideErrStore struct {
	matcher.MemoryStore
	decideErr error
}

func (s *decideErrStore) DecideItem(ctx context.Context, tenantID string, patch matcher.DecidePatch) (*matcher.ReviewItem, error) {
	if s.decideErr != nil {
		return nil, s.decideErr
	}
	return s.MemoryStore.DecideItem(ctx, tenantID, patch)
}

type fakePM struct {
	items []domain.ProductMasterItem
}

func (f fakePM) GetProductMasterItems(string) []domain.ProductMasterItem { return f.items }

func withClaims(r *http.Request, role domain.UserRole) *http.Request {
	claims := &domain.UserClaims{
		UserID: "u1", TenantID: "tenant-adeco", Email: "admin@adeco.test", Role: role,
	}
	ctx := context.WithValue(r.Context(), middleware.UserClaimsContextKey, claims)
	ctx = context.WithValue(ctx, middleware.VerifiedClaimsContextKey, claims)
	return r.WithContext(ctx)
}

func TestProductMatchAPI_MatchEnqueueReviewDecide(t *testing.T) {
	pm := fakePM{items: []domain.ProductMasterItem{{
		ItemCode: "FGCL-0550-0001", Barcode: "6223000231227",
		OfficialName: "كلوريل 500 جم مبيض", Brand: "كلوريل", ItemType: "عادي",
		IsPrimaryForBarcode: true,
	}}}
	q := matcher.NewQueue(&matcher.MemoryStore{})
	h := NewProductMatchHandler(q, pm)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/product-match", h.HandleMatch)
	mux.HandleFunc("POST /api/v1/product-match/enqueue", h.HandleEnqueue)
	mux.HandleFunc("GET /api/v1/product-match/review", h.HandleListReview)
	mux.HandleFunc("POST /api/v1/product-match/review/decide", h.HandleDecide)
	mux.HandleFunc("GET /api/v1/product-match/metrics", h.HandleMetrics)

	// Exact match
	body := `{"barcode":"6223000231227"}`
	req := withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match", bytes.NewBufferString(body)), domain.RoleVendorAdmin)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("match status=%d body=%s", rec.Code, rec.Body.String())
	}
	var exact matcher.Result
	if err := json.Unmarshal(rec.Body.Bytes(), &exact); err != nil {
		t.Fatal(err)
	}
	if exact.Decision != matcher.DecisionExact || exact.SuggestedBarcode != "6223000231227" {
		t.Fatalf("%+v", exact)
	}

	// Enqueue unknowns (foreign barcode → review)
	enq := `{"source_file":"t.xlsx","queries":[{"barcode":"9999999999999","sku_name":"أجنبي","rows":1,"value":5}]}`
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/enqueue", bytes.NewBufferString(enq)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("enqueue status=%d body=%s", rec.Code, rec.Body.String())
	}
	var enqResp struct {
		Count int `json:"count"`
		Items []matcher.ReviewItem `json:"enqueued"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &enqResp); err != nil {
		t.Fatal(err)
	}
	if enqResp.Count != 1 || len(enqResp.Items) != 1 {
		t.Fatalf("%+v", enqResp)
	}
	id := enqResp.Items[0].ID

	// List pending
	req = withClaims(httptest.NewRequest(http.MethodGet, "/api/v1/product-match/review?status=pending", nil), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list %d %s", rec.Code, rec.Body.String())
	}

	// Reject invented barcode on decide
	bad := `{"id":"` + id + `","status":"approved","chosen_barcode":"SKU-FAKE-001","reason_ar":"x"}`
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(bad)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code == http.StatusOK {
		t.Fatal("must reject invented barcode")
	}

	// Approve without inventing
	okBody := `{"id":"` + id + `","status":"approved","reason_ar":"سيُضاف للكارتة لاحقاً"}`
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(okBody)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("decide %d %s", rec.Code, rec.Body.String())
	}

	// Metrics
	req = withClaims(httptest.NewRequest(http.MethodGet, "/api/v1/product-match/metrics", nil), domain.RoleViewer)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("metrics %d", rec.Code)
	}
	var m matcher.Metrics
	if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
		t.Fatal(err)
	}
	if m.InventedBarcodes != 0 || m.Approved != 1 || m.LabelsAR["auto_resolve_rate"] == "" {
		t.Fatalf("%+v", m)
	}
}

func TestProductMatchEnqueueForbiddenForViewer(t *testing.T) {
	h := NewProductMatchHandler(matcher.NewQueue(&matcher.MemoryStore{}), fakePM{})
	req := withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/enqueue",
		bytes.NewBufferString(`{"queries":[{"sku_name":"x"}]}`)), domain.RoleViewer)
	rec := httptest.NewRecorder()
	h.HandleEnqueue(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestProductMatchDecideWrongPairAndIdempotent(t *testing.T) {
	pm := fakePM{items: []domain.ProductMasterItem{
		{ItemCode: "FGCL-0550-0001", Barcode: "6223000231227", OfficialName: "كلوريل 500 جم مبيض", IsPrimaryForBarcode: true},
		{ItemCode: "FGDW-1000-0010", Barcode: "6223000234001", OfficialName: "فيبا دش", IsPrimaryForBarcode: true},
	}}
	q := matcher.NewQueue(&matcher.MemoryStore{})
	h := NewProductMatchHandler(q, pm)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/product-match/enqueue", h.HandleEnqueue)
	mux.HandleFunc("POST /api/v1/product-match/review/decide", h.HandleDecide)

	enq := `{"queries":[{"sku_name":"صنف غامض للمراجعة"}]}`
	req := withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/enqueue", bytes.NewBufferString(enq)), domain.RoleVendorAdmin)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	var enqResp struct {
		Items []matcher.ReviewItem `json:"enqueued"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &enqResp)
	if len(enqResp.Items) != 1 {
		t.Fatalf("enqueue: %s", rec.Body.String())
	}
	id := enqResp.Items[0].ID

	// Wrong pair
	bad := `{"id":"` + id + `","status":"approved","chosen_item_code":"FGCL-0550-0001","chosen_barcode":"6223000234001"}`
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(bad)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code == http.StatusOK {
		t.Fatal("wrong pair must fail")
	}

	// Valid pair
	okBody := `{"id":"` + id + `","status":"approved","chosen_item_code":"FGCL-0550-0001","chosen_barcode":"6223000231227","reason_ar":"تم"}`
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(okBody)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("valid decide %d %s", rec.Code, rec.Body.String())
	}

	// Idempotent repeat
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(okBody)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("idempotent decide %d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Metrics matcher.Metrics `json:"metrics"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Metrics.Approved != 1 {
		t.Fatalf("idempotent must not double Approved: %+v", resp.Metrics)
	}

	// Different status rejected
	flip := `{"id":"` + id + `","status":"rejected","reason_ar":"لا"}`
	req = withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(flip)), domain.RoleVendorAdmin)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code == http.StatusOK {
		t.Fatal("repeat with different status must fail")
	}
}

func TestProductMatchDecideSanitizesFirestoreErrors(t *testing.T) {
	store := &decideErrStore{}
	q := matcher.NewQueue(store)
	item, err := q.EnqueueMatch(context.Background(), "tenant-adeco", matcher.Query{SKUName: "x"}, matcher.Result{Decision: matcher.DecisionNone})
	if err != nil || item == nil {
		t.Fatal(err)
	}
	store.decideErr = errors.New(`firestore enqueue product match: rpc error: code = Aborted desc = conflict`)

	h := NewProductMatchHandler(q, fakePM{})
	body := `{"id":"` + item.ID + `","status":"rejected","reason_ar":"رفض"}`
	req := withClaims(httptest.NewRequest(http.MethodPost, "/api/v1/product-match/review/decide", bytes.NewBufferString(body)), domain.RoleVendorAdmin)
	rec := httptest.NewRecorder()
	h.HandleDecide(rec, req)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "rpc error") || strings.Contains(rec.Body.String(), "firestore") {
		t.Fatalf("must not leak firestore text: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "تعذر حفظ قرار المراجعة") {
		t.Fatalf("want safe Arabic message, got %s", rec.Body.String())
	}
}

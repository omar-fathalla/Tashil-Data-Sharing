package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/sellinassist"
)

func sellInAssistMux(t *testing.T) (http.Handler, *middleware.AuthMiddleware, *sellinassist.Service) {
	t.Helper()
	svc := sellinassist.New("", "", true)
	h := NewSellInAssistHandler(svc)
	mw := middleware.NewAuthMiddleware("test-secret", false)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/sell-in/assist/suggestions", h.HandleList)
	mux.HandleFunc("POST /api/v1/sell-in/assist/suggest-layout", h.HandleSuggestLayout)
	mux.HandleFunc("POST /api/v1/sell-in/assist/suggest-chains", h.HandleSuggestChains)
	mux.HandleFunc("POST /api/v1/sell-in/assist/approve", h.HandleApprove)
	mux.HandleFunc("POST /api/v1/sell-in/assist/reject", h.HandleReject)
	mux.HandleFunc("GET /api/v1/sell-in/assist/metrics", h.HandleMetrics)
	return mw.Handler(mux), mw, svc
}

func TestSellInAssistSuggestApproveFlowArabic(t *testing.T) {
	h, mw, _ := sellInAssistMux(t)
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "admin@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	body := `{"upload_chain":"fathalla","customers":["فرع فتح الله - كيه اتش جمله ماركت","فرع فتح الله - زهران"]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sell-in/assist/suggest-chains", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("suggest status %d %s", rec.Code, rec.Body.String())
	}
	var sugResp struct {
		Suggestions []sellinassist.Suggestion `json:"suggestions"`
		NoteAR      string                    `json:"note_ar"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &sugResp); err != nil {
		t.Fatal(err)
	}
	if len(sugResp.Suggestions) < 1 || !strings.Contains(sugResp.NoteAR, "موافقة") {
		t.Fatalf("resp=%+v", sugResp)
	}
	id := sugResp.Suggestions[0].ID

	req = httptest.NewRequest(http.MethodPost, "/api/v1/sell-in/assist/approve", strings.NewReader(`{"id":"`+id+`"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("approve %d %s", rec.Code, rec.Body.String())
	}
	var appr map[string]interface{}
	_ = json.Unmarshal(rec.Body.Bytes(), &appr)
	if !strings.Contains(appr["note_ar"].(string), "الإنتاج") {
		t.Fatalf("missing no-prod note: %v", appr)
	}

	req = httptest.NewRequest(http.MethodGet, "/api/v1/sell-in/assist/metrics", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("metrics %d", rec.Code)
	}
	var metricsResp struct {
		Metrics sellinassist.Metrics `json:"metrics"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &metricsResp)
	if metricsResp.Metrics.Approved < 1 {
		t.Fatalf("metrics=%+v", metricsResp.Metrics)
	}
}

func TestSellInAssistLayoutSuggest(t *testing.T) {
	h, mw, _ := sellInAssistMux(t)
	tok, _ := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "admin@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	body := `{"filename":"in26.xlsx","sample":[["SOP Number","Document Date","Customer Name","Item Number","QTY","Extended Price"],["1","2026-01-01","عميل","6223","1","10"]]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sell-in/assist/suggest-layout", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("%d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Suggestion sellinassist.Suggestion `json:"suggestion"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Suggestion.Layout != "gp_sop" || resp.Suggestion.Status != sellinassist.StatusPending {
		t.Fatalf("%+v", resp.Suggestion)
	}
}

func TestSellInAssistForbiddenForViewer(t *testing.T) {
	h, mw, _ := sellInAssistMux(t)
	tok, _ := mw.GenerateToken(domain.UserClaims{
		UserID: "v", Email: "v@test", TenantID: "tenant-adeco", Role: domain.RoleViewer,
	}, time.Hour)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sell-in/assist/approve", strings.NewReader(`{"id":"x"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("want 403 got %d", rec.Code)
	}
}

func TestSellInAssistCrossTenantApproveNoDisclosure(t *testing.T) {
	h, mw, svc := sellInAssistMux(t)
	tokA, _ := mw.GenerateToken(domain.UserClaims{
		UserID: "a", Email: "a@test", TenantID: "tenant-a", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	tokB, _ := mw.GenerateToken(domain.UserClaims{
		UserID: "b", Email: "b@test", TenantID: "tenant-b", Role: domain.RoleVendorAdmin,
	}, time.Hour)

	body := `{"upload_chain":"fathalla","customers":["فرع فتح الله - كيه اتش جمله ماركت"]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sell-in/assist/suggest-chains", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokA)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("suggest %d %s", rec.Code, rec.Body.String())
	}
	var sugResp struct {
		Suggestions []sellinassist.Suggestion `json:"suggestions"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &sugResp)
	if len(sugResp.Suggestions) != 1 {
		t.Fatalf("want 1 sug, got %+v", sugResp)
	}
	id := sugResp.Suggestions[0].ID

	req = httptest.NewRequest(http.MethodPost, "/api/v1/sell-in/assist/approve", strings.NewReader(`{"id":"`+id+`"}`))
	req.Header.Set("Authorization", "Bearer "+tokB)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("cross-tenant approve want 404 got %d %s", rec.Code, rec.Body.String())
	}
	var errBody map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &errBody)
	if strings.Contains(errBody["error"], "tenant-a") || strings.Contains(rec.Body.String(), "كيه اتش") {
		t.Fatalf("response disclosed foreign tenant data: %s", rec.Body.String())
	}
	pending := svc.List("tenant-a", sellinassist.StatusPending)
	if len(pending) != 1 || pending[0].Status != sellinassist.StatusPending {
		t.Fatalf("state mutated: %+v", pending)
	}
}

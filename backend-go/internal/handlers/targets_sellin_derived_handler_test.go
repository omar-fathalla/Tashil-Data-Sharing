package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

const dsiHandlerTenant = "tenant-dsi-h"

func ownerRequest(method, target string, body []byte, contentType string) *http.Request {
	req := httptest.NewRequest(method, target, bytes.NewReader(body))
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	claims := &domain.UserClaims{UserID: "owner", TenantID: dsiHandlerTenant, Role: domain.RoleVendorAdmin}
	ctx := context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims)
	return req.WithContext(context.WithValue(ctx, middleware.VerifiedClaimsContextKey, claims))
}

func seedSellOutTargetViaAPI(t *testing.T, h *AnalyticsHandler, month int) string {
	t.Helper()
	body := `{"target_type":"sell_out","retailer_chain":"fathalla","year":2026,"month":` + string(rune('0'+month)) + `,"target_revenue_egp":10000,"target_units":500}`
	rec := httptest.NewRecorder()
	h.HandleTargets(rec, ownerRequest(http.MethodPost, "/api/v1/analytics/targets?target_type=sell_out", []byte(body), "application/json"))
	if rec.Code != http.StatusOK {
		t.Fatalf("seed Sell-Out target: HTTP %d %s", rec.Code, rec.Body.String())
	}
	var s domain.TargetsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&s); err != nil || len(s.Items) == 0 {
		t.Fatalf("seed response: %v %+v", err, s)
	}
	return s.Items[0].ID
}

func decodeErr(t *testing.T, rec *httptest.ResponseRecorder) map[string]string {
	t.Helper()
	var out map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&out); err != nil {
		t.Fatalf("error body is not JSON: %v (%s)", err, rec.Body.String())
	}
	return out
}

func TestSellInTargetsPostIsRejected(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, _ := setupTestAnalyticsHandler()

	cases := map[string]struct {
		url, body string
	}{
		"query type":   {"/api/v1/analytics/targets?target_type=sell_in", `{"retailer_chain":"fathalla","year":2026,"target_units":10}`},
		"body type":    {"/api/v1/analytics/targets", `{"target_type":"sell_in","retailer_chain":"fathalla","year":2026,"target_units":10}`},
		"legacy param": {"/api/v1/analytics/targets?type=sell_in", `{"retailer_chain":"fathalla","year":2026,"target_units":10}`},
		"batch mixed":  {"/api/v1/analytics/targets", `{"targets":[{"target_type":"sell_out","retailer_chain":"fathalla","year":2026,"target_units":5},{"target_type":"sell_in","retailer_chain":"fathalla","year":2026,"target_units":10}]}`},
		"upper case":   {"/api/v1/analytics/targets", `{"target_type":"Sell_In","retailer_chain":"fathalla","year":2026,"target_units":10}`},
	}
	for name, tc := range cases {
		for _, method := range []string{http.MethodPost, http.MethodPut} {
			rec := httptest.NewRecorder()
			h.HandleTargets(rec, ownerRequest(method, tc.url, []byte(tc.body), "application/json"))
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("%s %s: want 400, got %d %s", method, name, rec.Code, rec.Body.String())
			}
			e := decodeErr(t, rec)
			if e["code"] != "sell_in_targets_are_derived" || e["error"] == "" || e["error_ar"] == "" {
				t.Fatalf("%s %s: unclear error body %v", method, name, e)
			}
		}
	}

	// Nothing from a rejected batch was partially applied.
	rec := httptest.NewRecorder()
	h.HandleTargets(rec, ownerRequest(http.MethodGet, "/api/v1/analytics/targets?target_type=sell_out", nil, ""))
	var s domain.TargetsSummaryResponse
	_ = json.NewDecoder(rec.Body).Decode(&s)
	if len(s.Items) != 0 {
		t.Fatalf("rejected batch must not save its Sell-Out part: %+v", s.Items)
	}
}

func TestSellInTargetsUploadIsRejected(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, _ := setupTestAnalyticsHandler()

	rec := httptest.NewRecorder()
	h.HandleUploadTargetsFile(rec, ownerRequest(http.MethodPost, "/api/v1/analytics/targets/upload?target_type=sell_in", []byte("a,b\n1,2"), "text/csv"))
	if rec.Code != http.StatusBadRequest || decodeErr(t, rec)["code"] != "sell_in_targets_are_derived" {
		t.Fatalf("query upload: HTTP %d %s", rec.Code, rec.Body.String())
	}

	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	_ = mw.WriteField("target_type", "sell_in")
	fw, _ := mw.CreateFormFile("file", "targets.csv")
	_, _ = fw.Write([]byte("chain,year,month,branch,category,value,qty\nfathalla,2026,1,,,1000,100\n"))
	_ = mw.Close()
	rec = httptest.NewRecorder()
	h.HandleUploadTargetsFile(rec, ownerRequest(http.MethodPost, "/api/v1/analytics/targets/upload", buf.Bytes(), mw.FormDataContentType()))
	if rec.Code != http.StatusBadRequest || decodeErr(t, rec)["code"] != "sell_in_targets_are_derived" {
		t.Fatalf("multipart upload: HTTP %d %s", rec.Code, rec.Body.String())
	}
}

func TestSellInTargetsDeleteIsRejectedAndLegacyKept(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, bq := setupTestAnalyticsHandler()
	soID := seedSellOutTargetViaAPI(t, h, 0)

	for _, id := range []string{"derived_si_from_" + soID} {
		rec := httptest.NewRecorder()
		h.HandleTargets(rec, ownerRequest(http.MethodDelete, "/api/v1/analytics/targets?target_type=sell_in&id="+url.QueryEscape(id), nil, ""))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("delete derived %s: HTTP %d", id, rec.Code)
		}
		rec = httptest.NewRecorder()
		h.HandleTargets(rec, ownerRequest(http.MethodDelete, "/api/v1/analytics/targets?id="+url.QueryEscape(id), nil, ""))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("delete derived id without type %s: HTTP %d", id, rec.Code)
		}
	}

	if _, ok := bq.GetTarget(context.Background(), dsiHandlerTenant, soID); !ok {
		t.Fatal("the Sell-Out target must survive a rejected derived delete")
	}

	// The Sell-Out target itself is still deletable.
	rec := httptest.NewRecorder()
	h.HandleTargets(rec, ownerRequest(http.MethodDelete, "/api/v1/analytics/targets?target_type=sell_out&id="+url.QueryEscape(soID), nil, ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("Sell-Out delete: HTTP %d %s", rec.Code, rec.Body.String())
	}
}

func TestSellInTargetsGetIsDerivedFromSellOut(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, _ := setupTestAnalyticsHandler()
	soID := seedSellOutTargetViaAPI(t, h, 0)

	rec := httptest.NewRecorder()
	h.HandleTargets(rec, ownerRequest(http.MethodGet, "/api/v1/analytics/targets?target_type=sell_in&chain=fathalla&year=2026", nil, ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	var s domain.TargetsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&s); err != nil {
		t.Fatal(err)
	}
	if !s.Derived || s.TargetType != "sell_in" || len(s.Items) != 1 {
		t.Fatalf("derived summary: %+v", s)
	}
	it := s.Items[0]
	if it.ID != "derived_si_from_"+soID || it.TargetUnits != 500 || !strings.HasPrefix(it.ID, "derived_si_from_") {
		t.Fatalf("derived item: %+v", it)
	}

	// Brand filter via repeated ?brand= and ?brands=a,b is accepted (no match here: no Product Master).
	for _, q := range []string{"brand=" + url.QueryEscape("بدون براند"), "brands=" + url.QueryEscape("بدون براند,x")} {
		rec = httptest.NewRecorder()
		h.HandleTargets(rec, ownerRequest(http.MethodGet, "/api/v1/analytics/targets?target_type=sell_in&"+q, nil, ""))
		var f domain.TargetsSummaryResponse
		_ = json.NewDecoder(rec.Body).Decode(&f)
		if rec.Code != http.StatusOK || len(f.Items) != 1 || len(f.AppliedBrands) == 0 {
			t.Fatalf("brand filter %s: HTTP %d %+v", q, rec.Code, f)
		}
	}
}

func TestSellOutWritesMaterializeDerivedSellInRecords(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, repo := setupTestAnalyticsHandler()
	ctx := context.Background()
	derivedOf := func(soID string) (*domain.TargetRecord, bool) {
		return repo.GetTarget(ctx, dsiHandlerTenant, bigquery.DerivedSellInTargetID(soID))
	}

	single := seedSellOutTargetViaAPI(t, h, 3)
	if d, ok := derivedOf(single); !ok || !d.Derived || d.TargetType != "sell_in" || d.TargetUnits != 500 || d.SourceTargetID != single {
		t.Fatalf("POST stores the derived Sell-In record: %+v %v", d, ok)
	}

	body := `{"targets":[` +
		`{"target_type":"sell_out","retailer_chain":"fathalla","year":2026,"month":4,"target_units":300,"target_revenue_egp":6000},` +
		`{"target_type":"sell_out","retailer_chain":"fathalla","year":2026,"month":5,"target_units":200,"target_revenue_egp":4000}]}`
	rec := httptest.NewRecorder()
	h.HandleTargets(rec, ownerRequest(http.MethodPost, "/api/v1/analytics/targets?target_type=sell_out", []byte(body), "application/json"))
	if rec.Code != http.StatusOK {
		t.Fatalf("batch POST: HTTP %d %s", rec.Code, rec.Body.String())
	}
	var s domain.TargetsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&s); err != nil {
		t.Fatal(err)
	}
	batched := 0
	for _, it := range s.Items {
		if it.Month == 4 || it.Month == 5 {
			d, ok := derivedOf(it.ID)
			if !ok || d.TargetUnits != it.TargetUnits {
				t.Fatalf("batch POST materializes month %d: %+v %v", it.Month, d, ok)
			}
			batched++
		}
	}
	if batched != 2 {
		t.Fatalf("batch items: %+v", s.Items)
	}

	rec = httptest.NewRecorder()
	h.HandleTargets(rec, ownerRequest(http.MethodDelete, "/api/v1/analytics/targets?target_type=sell_out&id="+url.QueryEscape(single), nil, ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("Sell-Out delete: HTTP %d %s", rec.Code, rec.Body.String())
	}
	if _, ok := derivedOf(single); ok {
		t.Fatal("deleting the Sell-Out target removes its derived Sell-In record")
	}
}

func TestRequestedSellInBrands(t *testing.T) {
	got := requestedSellInBrands(map[string][]string{
		"brand":  {"أ", " ب ", "أ", ""},
		"brands": {"ج,د, ب"},
	})
	want := []string{"أ", "ب", "ج", "د"}
	if len(got) != len(want) {
		t.Fatalf("got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v want %v", got, want)
		}
	}
}

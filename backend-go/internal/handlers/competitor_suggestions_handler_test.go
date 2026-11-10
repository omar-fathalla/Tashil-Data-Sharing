package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/competitorsuggest"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

type memCatalog struct {
	res bigquery.CompetitiveMonthlyResult
}

func (m *memCatalog) CompetitiveMonthly(tenantID string, filter bigquery.RecordFilter) bigquery.CompetitiveMonthlyResult {
	return m.res
}

func suggestMux(h *CompetitorSuggestionsHandler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/competitors/suggestions", h.HandleListSuggestions)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/run", h.HandleRunSuggestions)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/sku", h.HandleSuggestForSku)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/approve", h.HandleApproveSuggestion)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/reject", h.HandleRejectSuggestion)
	mux.HandleFunc("GET /api/v1/competitors/mappings", NewCompetitorHandler(h.repo, nil).HandleListCompetitorMappings)
	return mux
}

func seedCatalog() *memCatalog {
	return &memCatalog{res: bigquery.CompetitiveMonthlyResult{
		Year: 2026,
		Items: []bigquery.CompetitiveMonthlyItem{
			{
				Barcode: "OWN-DISH", SKUName: "فيبا 3 كجم", Category: "صابون سائل اطباق", IsOwnBrand: true,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 180, Units: 10, NetRevenue: 1800}},
			},
			{
				Barcode: "COMP-PRIL", SKUName: "بريل 4 كجم", Category: "صابون سائل اطباق", IsOwnBrand: false,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 150, Units: 8, NetRevenue: 1200}},
			},
			{
				Barcode: "COMP-FAIRY", SKUName: "فييري بدون حجم", Category: "صابون سائل اطباق", IsOwnBrand: false,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 160, Units: 5, NetRevenue: 800}},
			},
			{
				Barcode: "OWN-CARE", SKUName: "عناية شخصية 1", Category: "عناية شخصية", IsOwnBrand: true,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 50, Units: 2, NetRevenue: 100}},
			},
			{
				Barcode: "OWN-GEL", SKUName: "جيل اتوماتيك", Category: "مساحيق جيل اتوماتيك", IsOwnBrand: true,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 90, Units: 3, NetRevenue: 270}},
			},
			{
				Barcode: "COMP-GEL", SKUName: "أوكسى مسحوق جيل", Category: "مسحوق جيل اتوماتيك", IsOwnBrand: false,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 85, Units: 4, NetRevenue: 340}},
			},
		},
	}}
}

func TestCompetitorSuggestionsRunApproveRejectFlow(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	ranker := &competitorsuggest.GeminiRanker{UseMock: true}
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), ranker)
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	viewer := &domain.UserClaims{UserID: "u2", TenantID: "adeco", Email: "v@adeco.com", Role: domain.RoleExecutive}

	if rec, _ := tmDo(t, mux, viewer, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 10,
	}); rec.Code != http.StatusForbidden {
		t.Fatalf("non-owner run: want 403, got %d", rec.Code)
	}

	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 10, "own_skus": []string{"OWN-DISH", "OWN-CARE", "OWN-GEL"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("run: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	created := int(out["created_count"].(float64))
	if created < 1 {
		t.Fatalf("expected suggestions created, got %v", out)
	}
	skipped := out["skipped"].([]interface{})
	careSkip := false
	for _, s := range skipped {
		m := s.(map[string]interface{})
		if m["barcode"] == "OWN-CARE" && m["reason_ar"] == "لا يوجد منافسين في البيانات" {
			careSkip = true
		}
	}
	if !careSkip {
		t.Fatalf("عناية شخصية must skip with Arabic empty message, skipped=%v", skipped)
	}

	_, out = tmDo(t, mux, admin, "GET", "/api/v1/competitors/suggestions?status=pending&chain=fathalla", nil)
	pending := out["suggestions"].([]interface{})
	if len(pending) == 0 {
		t.Fatal("expected pending suggestions")
	}
	for _, raw := range pending {
		row := raw.(map[string]interface{})
		brand := strings.TrimSpace(fmt.Sprint(row["competitor_brand"]))
		if brand == "" || brand == "منافس" {
			t.Fatalf("suggestion %v missing real competitor_brand (got %q)", row["id"], brand)
		}
	}
	// Pending must NOT appear as mappings yet.
	_, mout := tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings?chain=fathalla", nil)
	if mout["count"].(float64) != 0 {
		t.Fatalf("pending must not create mappings, got %v", mout)
	}

	first := pending[0].(map[string]interface{})
	id := first["id"].(string)
	ownBC := first["own_barcode"].(string)
	compBC := first["competitor_barcode"].(string)

	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/approve", map[string]interface{}{"id": id})
	if rec.Code != http.StatusOK {
		t.Fatalf("approve: %d %s", rec.Code, rec.Body.String())
	}
	if out["mapping"].(map[string]interface{})["competitor_barcode"] != compBC {
		t.Fatalf("approve should write mapping: %v", out)
	}
	_, mout = tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings?chain=fathalla", nil)
	if mout["count"].(float64) != 1 {
		t.Fatalf("after approve want 1 mapping, got %v", mout)
	}

	// Reject another pending if available; else create via second own.
	_, out = tmDo(t, mux, admin, "GET", "/api/v1/competitors/suggestions?status=pending&chain=fathalla", nil)
	pending = out["suggestions"].([]interface{})
	var rejectID string
	for _, raw := range pending {
		m := raw.(map[string]interface{})
		if m["own_barcode"] != ownBC {
			rejectID = m["id"].(string)
			break
		}
	}
	if rejectID == "" && len(pending) > 0 {
		rejectID = pending[0].(map[string]interface{})["id"].(string)
	}
	if rejectID != "" {
		rec, _ = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/reject", map[string]interface{}{"id": rejectID})
		if rec.Code != http.StatusOK {
			t.Fatalf("reject: %d", rec.Code)
		}
	}

	// Rate-limit: immediate re-run should 429
	if rec, _ = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5,
	}); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("rate limit: want 429, got %d", rec.Code)
	}
	// Bypass rate limit for reject-not-resuggested check
	h.rateMu.Lock()
	h.lastRun = map[string]time.Time{}
	h.rateMu.Unlock()

	// Own with approved mapping and/or remaining pending rows is skipped on re-run
	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 10, "own_skus": []string{ownBC},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("rerun: %d %s", rec.Code, rec.Body.String())
	}
	for _, s := range out["skipped"].([]interface{}) {
		m := s.(map[string]interface{})
		if m["barcode"] != ownBC {
			continue
		}
		reason := fmt.Sprint(m["reason_ar"])
		// Remaining pending rows → covered skip; otherwise approved-mapping skip.
		if reason == skipReasonOwnAlreadyCovered || reason == "يوجد تعيين معتمد مسبقاً" {
			return
		}
	}
	t.Fatalf("approved/covered own should be skipped on rerun: %v", out["skipped"])
}

func TestCompetitorSuggestionsRejectNotResuggested(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	ranker := &competitorsuggest.GeminiRanker{UseMock: true}
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), ranker)
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	_, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5, "own_skus": []string{"OWN-DISH"},
	})
	pending := out["suggestions"].([]interface{})
	if len(pending) == 0 {
		t.Fatal("need pending")
	}
	ids := make([]string, 0, len(pending))
	for _, raw := range pending {
		ids = append(ids, raw.(map[string]interface{})["id"].(string))
	}
	for _, id := range ids {
		if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/reject", map[string]interface{}{"id": id}); rec.Code != http.StatusOK {
			t.Fatalf("reject %s: %d", id, rec.Code)
		}
	}
	h.rateMu.Lock()
	h.lastRun = map[string]time.Time{}
	h.rateMu.Unlock()

	_, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5, "own_skus": []string{"OWN-DISH"},
	})
	if int(out["created_count"].(float64)) != 0 {
		t.Fatalf("rejected pairs must not be re-suggested, got %v", out)
	}
}

func TestCompetitorSuggestionsAIRejectsHallucination(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	ranker := &competitorsuggest.GeminiRanker{
		CallJSON: func(ctx context.Context, model, prompt string) (string, competitorsuggest.TokenUsage, error) {
			return `{"suggestions":[
				{"competitor_barcode":"COMP-PRIL","reason_ar":"مناسب","confidence":0.9,"rank":1},
				{"competitor_barcode":"FAKE-SKU","reason_ar":"مخترع","confidence":0.99,"rank":2}
			]}`, competitorsuggest.TokenUsage{PromptTokens: 10, CompletionTokens: 5}, nil
		},
	}
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), ranker)
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	_, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 3, "own_skus": []string{"OWN-DISH"},
	})
	sugs := out["suggestions"].([]interface{})
	for _, raw := range sugs {
		m := raw.(map[string]interface{})
		if m["competitor_barcode"] == "FAKE-SKU" {
			t.Fatal("hallucinated barcode must be rejected server-side")
		}
	}
	if len(sugs) != 1 {
		t.Fatalf("want only COMP-PRIL, got %v", mustJSON(sugs))
	}
}

func TestCompetitorSuggestionsAllRanksFailedReturnsError(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	ranker := &competitorsuggest.GeminiRanker{
		CallJSON: func(ctx context.Context, model, prompt string) (string, competitorsuggest.TokenUsage, error) {
			return "", competitorsuggest.TokenUsage{}, context.Canceled
		},
	}
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), ranker)
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5, "own_skus": []string{"OWN-DISH"},
	})
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("all ranks failed: want 502, got %d %s", rec.Code, rec.Body.String())
	}
	if int(out["created_count"].(float64)) != 0 {
		t.Fatalf("created_count: %v", out["created_count"])
	}
	if int(out["rank_failures"].(float64)) < 1 {
		t.Fatalf("rank_failures: %v", out)
	}
	errMsg, _ := out["error"].(string)
	if !strings.Contains(errMsg, "فشل ترتيب") {
		t.Fatalf("error summary missing Arabic failure text: %v", out)
	}
	counts, _ := out["skipped_reason_counts"].(map[string]interface{})
	if counts == nil || counts["تعذر ترتيب المرشحين"] == nil {
		t.Fatalf("skipped_reason_counts missing rank failure: %v", out)
	}
}

func TestCompetitorSuggestionsBatchCapIsTen(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	_, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 99,
	})
	if int(out["limit"].(float64)) != 10 {
		t.Fatalf("hard cap must be 10, got %v", out["limit"])
	}
}

func TestPendingSuggestionsNeverInMappingsCount(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5, "own_skus": []string{"OWN-DISH"},
	})
	_, out := tmDo(t, mux, admin, "GET", "/api/v1/competitors/suggestions?status=pending", nil)
	if out["count"].(float64) < 1 {
		t.Fatal("expected pending")
	}
	_, mout := tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings", nil)
	if mout["count"].(float64) != 0 {
		t.Fatal("pending must not count as mappings / Compare pins")
	}
}

func TestCompetitorSuggestionsForSkuCacheAndGenerate(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	viewer := &domain.UserClaims{UserID: "u2", TenantID: "adeco", Email: "v@adeco.com", Role: domain.RoleExecutive}

	if rec, _ := tmDo(t, mux, viewer, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-DISH", "chain": "fathalla",
	}); rec.Code != http.StatusForbidden {
		t.Fatalf("non-owner sku: want 403, got %d", rec.Code)
	}

	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-DISH", "chain": "fathalla", "year": 2026,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("sku generate: %d %s", rec.Code, rec.Body.String())
	}
	if out["cached"] != false {
		t.Fatalf("first call should generate, got cached=%v", out["cached"])
	}
	if out["include_in_kpi_averages"] != false {
		t.Fatal("KPI averages flag must default OFF (HOLD)")
	}
	sugs := out["suggestions"].([]interface{})
	if len(sugs) == 0 || len(sugs) > 3 {
		t.Fatalf("want 1..3 suggestions, got %d", len(sugs))
	}

	// Cache hit — no regenerate even within rate window
	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-DISH", "chain": "fathalla",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("sku cache: %d", rec.Code)
	}
	if out["cached"] != true {
		t.Fatalf("second call should be cached, got %v", out)
	}
	if int(out["count"].(float64)) != len(sugs) {
		t.Fatalf("cached count mismatch: %v vs %d", out["count"], len(sugs))
	}

	// Pending must still not write mappings (view without approve)
	_, mout := tmDo(t, mux, admin, "GET", "/api/v1/competitors/mappings", nil)
	if mout["count"].(float64) != 0 {
		t.Fatal("sku suggestions must not auto-write competitor_mappings")
	}
}

func TestCompetitorSuggestionsBrandNotGenericCompetitor(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	cat := &memCatalog{res: bigquery.CompetitiveMonthlyResult{
		Year: 2026, Months: []int{5},
		Items: []bigquery.CompetitiveMonthlyItem{
			{
				Barcode: "OWN-GEL2", SKUName: "فيبا بلس اوكسي 3كجم", Category: "مساحيق جيل اتوماتيك",
				IsOwnBrand: true,
				Months:     []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 180, Units: 10, NetRevenue: 1800}},
			},
			{
				Barcode: "COMP-OXI", SKUName: "أوكسى جيل اوتوماتيك نسيم العطور 3كجم",
				Category: "مسحوق جيل اتوماتيك", Supplier: "هنكل", IsOwnBrand: false,
				Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 150, Units: 8, NetRevenue: 1200}},
			},
		},
	}}
	h := NewCompetitorSuggestionsHandler(fs, fs, cat, &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-GEL2", "chain": "fathalla", "year": 2026,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("sku: %d %s", rec.Code, rec.Body.String())
	}
	sugs := out["suggestions"].([]interface{})
	if len(sugs) == 0 {
		t.Fatal("expected at least one suggestion")
	}
	for _, raw := range sugs {
		row := raw.(map[string]interface{})
		brand := strings.TrimSpace(fmt.Sprint(row["competitor_brand"]))
		if brand == "" || brand == "منافس" {
			t.Fatalf("want real brand, got %q for %v", brand, row["competitor_sku_name"])
		}
		if !strings.Contains(brand, "أوكسي") && !strings.Contains(brand, "أوكسى") {
			// Mock ranker may pick the only candidate; brand must still be Oxi-derived.
			t.Fatalf("brand=%q should resolve to أوكسي from SKU name", brand)
		}
	}
}

func TestCompetitorSuggestionsForSkuEmptyCategoryArabic(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	cat := seedCatalog()
	cat.res.Items = append(cat.res.Items, bigquery.CompetitiveMonthlyItem{
		Barcode: "OWN-NOCAT", SKUName: "بدون فئة", Category: "", IsOwnBrand: true,
		Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 10, Units: 1, NetRevenue: 10}},
	})
	h := NewCompetitorSuggestionsHandler(fs, fs, cat, &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-NOCAT", "chain": "fathalla",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 with skip reason, got %d", rec.Code)
	}
	if out["skipped_reason_ar"] != "فئة مفقودة في البيانات" {
		t.Fatalf("skip reason: %v", out["skipped_reason_ar"])
	}
}

func TestCompetitorSuggestionsForSkuEmptyCacheAndPerSkuScope(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	// OWN-CARE has no same-category comps → empty generate (cached negatively).
	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-CARE", "chain": "fathalla",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("first empty: %d %s", rec.Code, rec.Body.String())
	}
	if out["skipped_reason_ar"] != "لا يوجد منافسين في البيانات" {
		t.Fatalf("skip: %v", out["skipped_reason_ar"])
	}

	// Re-select same SKU → empty cache hit (200), never 429.
	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-CARE", "chain": "fathalla",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("empty cache: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	if out["cached"] != true {
		t.Fatalf("want cached empty, got %v", out)
	}

	// Different SKU must not share the CARE cooldown / cache — browsing one-per-SKU stays OK.
	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-DISH", "chain": "fathalla",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("other SKU blocked by rate limit?: %d %s", rec.Code, rec.Body.String())
	}
	if out["cached"] == true && out["count"].(float64) == 0 {
		t.Fatalf("OWN-DISH should generate suggestions, got %v", out)
	}
	if int(out["count"].(float64)) < 1 {
		t.Fatalf("OWN-DISH want suggestions, got %v", out)
	}
}

func TestCompetitorSuggestionsForSkuTimeoutArabic(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	ranker := &competitorsuggest.GeminiRanker{
		CallJSON: func(ctx context.Context, model, prompt string) (string, competitorsuggest.TokenUsage, error) {
			<-ctx.Done()
			return "", competitorsuggest.TokenUsage{}, ctx.Err()
		},
	}
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), ranker)
	// Shrink timeout for the test so we do not wait 28s.
	prev := competitorSuggestRankTimeout
	competitorSuggestRankTimeout = 50 * time.Millisecond
	defer func() { competitorSuggestRankTimeout = prev }()

	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-DISH", "chain": "fathalla",
	})
	if rec.Code != http.StatusGatewayTimeout {
		t.Fatalf("want 504 on rank timeout, got %d %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "انتهت مهلة") {
		t.Fatalf("want Arabic timeout message, got %s", rec.Body.String())
	}

	// Failure must not stamp cooldown — immediate retry is allowed (still times out).
	rec2, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-DISH", "chain": "fathalla",
	})
	if rec2.Code == http.StatusTooManyRequests {
		t.Fatal("timeout must not stamp per-SKU cooldown")
	}
	if rec2.Code != http.StatusGatewayTimeout {
		t.Fatalf("retry after timeout: want 504, got %d %s", rec2.Code, rec2.Body.String())
	}
}

func TestCompetitorSuggestionsForSkuCooldownAfterClearedEmptyCache(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-CARE", "chain": "fathalla",
	}); rec.Code != http.StatusOK {
		t.Fatalf("first: %d", rec.Code)
	}
	// Simulate empty-cache expiry while cooldown stamp remains → 429 on force re-generate.
	rateKey := strings.ToLower("tenant-adeco|fathalla|own-care")
	h.clearEmptySkuCache(rateKey)
	rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/sku", map[string]interface{}{
		"barcode": "OWN-CARE", "chain": "fathalla",
	})
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("want 429 when empty cache cleared inside cooldown, got %d %s", rec.Code, rec.Body.String())
	}
}

func TestCompetitorSuggestionsRunSkipsPendingAndAdvances(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	// Expand catalogue so two own SKUs with competitors exist beyond the first.
	cat := seedCatalog()
	cat.res.Items = append(cat.res.Items,
		bigquery.CompetitiveMonthlyItem{
			Barcode: "OWN-DISH-2", SKUName: "فيبا 2 كجم", Category: "صابون سائل اطباق", IsOwnBrand: true,
			Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 170, Units: 6, NetRevenue: 1020}},
		},
		bigquery.CompetitiveMonthlyItem{
			Barcode: "OWN-DISH-3", SKUName: "فيبا 1 كجم", Category: "صابون سائل اطباق", IsOwnBrand: true,
			Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 100, Units: 4, NetRevenue: 400}},
		},
	)
	h := NewCompetitorSuggestionsHandler(fs, fs, cat, &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	// Batch 1: only first own — creates pending coverage.
	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 1, "own_skus": []string{"OWN-DISH", "OWN-DISH-2", "OWN-DISH-3"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("batch1: %d %s", rec.Code, rec.Body.String())
	}
	if int(out["processed_own"].(float64)) != 1 {
		t.Fatalf("batch1 processed_own: %v", out["processed_own"])
	}
	if int(out["created_count"].(float64)) < 1 {
		t.Fatalf("batch1 created: %v", out)
	}
	remaining1 := int(out["remaining_uncovered"].(float64))
	if remaining1 != 2 {
		t.Fatalf("batch1 remaining_uncovered want 2, got %d (out=%v)", remaining1, out)
	}

	h.rateMu.Lock()
	h.lastRun = map[string]time.Time{}
	h.rateMu.Unlock()

	// Batch 2: must skip OWN-DISH (pending) and advance to OWN-DISH-2.
	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 1, "own_skus": []string{"OWN-DISH", "OWN-DISH-2", "OWN-DISH-3"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("batch2: %d %s", rec.Code, rec.Body.String())
	}
	coveredSkip := false
	for _, s := range out["skipped"].([]interface{}) {
		m := s.(map[string]interface{})
		if m["barcode"] == "OWN-DISH" && m["reason_ar"] == skipReasonOwnAlreadyCovered {
			coveredSkip = true
		}
	}
	if !coveredSkip {
		t.Fatalf("batch2 must skip pending OWN-DISH: %v", out["skipped"])
	}
	if int(out["processed_own"].(float64)) != 1 {
		t.Fatalf("batch2 should process next uncovered, got processed=%v created=%v", out["processed_own"], out["created_count"])
	}
	sugs := out["suggestions"].([]interface{})
	if len(sugs) == 0 {
		t.Fatal("batch2 should create suggestions for the next own SKU")
	}
	own2 := sugs[0].(map[string]interface{})["own_barcode"]
	if own2 != "OWN-DISH-2" {
		t.Fatalf("batch2 should advance to OWN-DISH-2, got %v", own2)
	}
	remaining2 := int(out["remaining_uncovered"].(float64))
	if remaining2 != 1 {
		t.Fatalf("batch2 remaining_uncovered want 1, got %d", remaining2)
	}
}

func TestCompetitorSuggestionsRunSkipsRejectedOwnAndReportsRemaining(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	h := NewCompetitorSuggestionsHandler(fs, fs, seedCatalog(), &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	_, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5, "own_skus": []string{"OWN-DISH"},
	})
	pending := out["suggestions"].([]interface{})
	if len(pending) == 0 {
		t.Fatal("need pending to reject")
	}
	for _, raw := range pending {
		id := raw.(map[string]interface{})["id"].(string)
		if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/reject", map[string]interface{}{"id": id}); rec.Code != http.StatusOK {
			t.Fatalf("reject: %d", rec.Code)
		}
	}

	h.rateMu.Lock()
	h.lastRun = map[string]time.Time{}
	h.rateMu.Unlock()

	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 5, "own_skus": []string{"OWN-DISH", "OWN-GEL"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("rerun: %d %s", rec.Code, rec.Body.String())
	}
	rejectedSkip := false
	for _, s := range out["skipped"].([]interface{}) {
		m := s.(map[string]interface{})
		if m["barcode"] == "OWN-DISH" && m["reason_ar"] == skipReasonOwnAlreadyCovered {
			rejectedSkip = true
		}
	}
	if !rejectedSkip {
		t.Fatalf("rejected own must be skipped as covered: %v", out["skipped"])
	}
	// OWN-GEL should still be processed; OWN-DISH must not be re-ranked.
	for _, raw := range out["suggestions"].([]interface{}) {
		if raw.(map[string]interface{})["own_barcode"] == "OWN-DISH" {
			t.Fatal("OWN-DISH must not be re-suggested after reject coverage")
		}
	}
	if _, ok := out["remaining_uncovered"]; !ok {
		t.Fatal("response must include remaining_uncovered")
	}
	if int(out["remaining_uncovered"].(float64)) != 0 {
		// OWN-DISH covered (rejected), OWN-GEL processed this run → 0 left in filter.
		t.Fatalf("remaining_uncovered want 0, got %v", out["remaining_uncovered"])
	}
}

func TestCompetitorSuggestionsRunAdvancesPastNoCandidateHead(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	// More than limit no-candidate owns at the head, then one with competitors.
	items := make([]bigquery.CompetitiveMonthlyItem, 0, 14)
	ownFilter := make([]string, 0, 13)
	for i := 0; i < 12; i++ {
		bc := fmt.Sprintf("OWN-EMPTY-%02d", i)
		ownFilter = append(ownFilter, bc)
		items = append(items, bigquery.CompetitiveMonthlyItem{
			Barcode: bc, SKUName: fmt.Sprintf("عناية %d", i), Category: "عناية شخصية", IsOwnBrand: true,
			Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 10, Units: 1, NetRevenue: 10}},
		})
	}
	ownFilter = append(ownFilter, "OWN-DISH")
	items = append(items,
		bigquery.CompetitiveMonthlyItem{
			Barcode: "OWN-DISH", SKUName: "فيبا 3 كجم", Category: "صابون سائل اطباق", IsOwnBrand: true,
			Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 180, Units: 10, NetRevenue: 1800}},
		},
		bigquery.CompetitiveMonthlyItem{
			Barcode: "COMP-PRIL", SKUName: "بريل 4 كجم", Category: "صابون سائل اطباق", IsOwnBrand: false,
			Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 150, Units: 8, NetRevenue: 1200}},
		},
	)
	h := NewCompetitorSuggestionsHandler(fs, fs, &memCatalog{res: bigquery.CompetitiveMonthlyResult{Year: 2026, Items: items}}, &competitorsuggest.GeminiRanker{UseMock: true})
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 10, "own_skus": ownFilter,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("run: %d %s", rec.Code, rec.Body.String())
	}
	// No-candidate owns must not consume the batch slot — OWN-DISH still processed.
	if int(out["processed_own"].(float64)) != 1 {
		t.Fatalf("processed_own want 1 (only OWN-DISH), got %v skipped=%v", out["processed_own"], out["skipped"])
	}
	if int(out["created_count"].(float64)) < 1 {
		t.Fatalf("expected OWN-DISH suggestions, got %v", out)
	}
	noCandSkips := 0
	for _, s := range out["skipped"].([]interface{}) {
		m := s.(map[string]interface{})
		if m["reason_ar"] == skipReasonNoCompetitors {
			noCandSkips++
		}
	}
	if noCandSkips != 12 {
		t.Fatalf("want 12 no-candidate skips without slot burn, got %d", noCandSkips)
	}
	if int(out["remaining_uncovered"].(float64)) != 0 {
		t.Fatalf("remaining_uncovered want 0 (no-candidate excluded), got %v", out["remaining_uncovered"])
	}
}

func TestCompetitorSuggestionsRunRankFailureMarksAttemptAndAdvances(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	cat := seedCatalog()
	cat.res.Items = append(cat.res.Items,
		bigquery.CompetitiveMonthlyItem{
			Barcode: "OWN-DISH-2", SKUName: "فيبا 2 كجم", Category: "صابون سائل اطباق", IsOwnBrand: true,
			Months: []bigquery.CompetitiveMonthPoint{{MonthKey: "2026-05", Month: 5, UnitPrice: 170, Units: 6, NetRevenue: 1020}},
		},
	)
	failOnce := true
	ranker := &competitorsuggest.GeminiRanker{
		CallJSON: func(ctx context.Context, model, prompt string) (string, competitorsuggest.TokenUsage, error) {
			if failOnce {
				failOnce = false
				return "", competitorsuggest.TokenUsage{}, context.Canceled
			}
			return `{"suggestions":[{"competitor_barcode":"COMP-PRIL","reason_ar":"مناسب","confidence":0.9,"rank":1}]}`,
				competitorsuggest.TokenUsage{PromptTokens: 1, CompletionTokens: 1}, nil
		},
	}
	h := NewCompetitorSuggestionsHandler(fs, fs, cat, ranker)
	mux := suggestMux(h)
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	rec, out := tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 1, "own_skus": []string{"OWN-DISH", "OWN-DISH-2"},
	})
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("batch1 all-rank-fail: want 502, got %d %s", rec.Code, rec.Body.String())
	}
	attempted, _ := out["attempted_without_suggestions"].([]interface{})
	if len(attempted) != 1 {
		t.Fatalf("batch1 attempted_without_suggestions: %v", out["attempted_without_suggestions"])
	}
	if int(out["remaining_uncovered"].(float64)) != 1 {
		t.Fatalf("batch1 remaining want 1 (OWN-DISH-2), got %v", out["remaining_uncovered"])
	}

	h.rateMu.Lock()
	h.lastRun = map[string]time.Time{}
	h.rateMu.Unlock()

	rec, out = tmDo(t, mux, admin, "POST", "/api/v1/competitors/suggestions/run", map[string]interface{}{
		"chain": "fathalla", "limit": 1, "own_skus": []string{"OWN-DISH", "OWN-DISH-2"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("batch2: %d %s", rec.Code, rec.Body.String())
	}
	skippedAttempt := false
	for _, s := range out["skipped"].([]interface{}) {
		m := s.(map[string]interface{})
		if m["barcode"] == "OWN-DISH" && m["reason_ar"] == skipReasonAttemptedEmpty {
			skippedAttempt = true
		}
	}
	if !skippedAttempt {
		t.Fatalf("batch2 must skip previously failed OWN-DISH: %v", out["skipped"])
	}
	sugs := out["suggestions"].([]interface{})
	if len(sugs) == 0 || sugs[0].(map[string]interface{})["own_barcode"] != "OWN-DISH-2" {
		t.Fatalf("batch2 should advance to OWN-DISH-2, got %v", out["suggestions"])
	}
	if int(out["remaining_uncovered"].(float64)) != 0 {
		t.Fatalf("batch2 remaining want 0, got %v", out["remaining_uncovered"])
	}
}

func mustJSON(v interface{}) string {
	b, _ := json.Marshal(v)
	return string(b)
}

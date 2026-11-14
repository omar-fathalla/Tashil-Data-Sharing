package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func TestYearListIsDataDriven(t *testing.T) {
	ys, def := YearList([]int{2025, 2026, 2027, 0, 1999}, 2026)
	if len(ys) != 3 || ys[0] != 2027 || ys[2] != 2025 || def != 2027 {
		t.Fatalf("got %v default %d", ys, def)
	}
	ys, def = YearList(nil, 2028)
	if len(ys) != 1 || ys[0] != 2028 || def != 2028 {
		t.Fatalf("no data → current year only, got %v %d", ys, def)
	}
}

func TestMonthListKeepsValidAscending(t *testing.T) {
	got := MonthList([]int{10, 1, 0, 13, 4, 10, -1})
	want := []int{1, 4, 10}
	if len(got) != len(want) {
		t.Fatalf("got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v want %v", got, want)
		}
	}
	if len(MonthList(nil)) != 0 {
		t.Fatal("empty stays empty")
	}
}

type stubRegistryProc struct {
	months []int
}

func (s stubRegistryProc) CustomerRegistry() *customers.Registry { return nil }
func (s stubRegistryProc) ReapplySellInFiles(context.Context, string, []string, []string) ([]ingestion.ReapplyResult, []string) {
	return nil, nil
}
func (s stubRegistryProc) SellInYears(string) []int { return nil }
func (s stubRegistryProc) SellOutMonths(_ string, year int) []int {
	if year != 2026 {
		return nil
	}
	return append([]int(nil), s.months...)
}

func TestHandleMonthsReturnsJanThroughOct(t *testing.T) {
	h := NewCustomerRegistryHandler(stubRegistryProc{months: []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}}, nil)
	h.now = func() time.Time { return time.Date(2026, 11, 8, 0, 0, 0, 0, time.UTC) }

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sell-out/months?year=2026", nil)
	req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, &domain.UserClaims{
		TenantID: "tenant-adeco",
		Role:     domain.RoleVendorAdmin,
	}))
	rec := httptest.NewRecorder()
	h.HandleMonths(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d body %s", rec.Code, rec.Body.String())
	}
	var out struct {
		Year   int   `json:"year"`
		Months []int `json:"months"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	if out.Year != 2026 || len(out.Months) != 10 {
		t.Fatalf("got %+v", out)
	}
	for i, want := range []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10} {
		if out.Months[i] != want {
			t.Fatalf("months=%v", out.Months)
		}
	}
}

type mergeProc struct {
	reg        *customers.Registry
	lastFiles  []string
	lastChains []string
	nilFiles   bool
	stats      map[string]ingestion.CustomerLiveStat
}

func (m *mergeProc) CustomerRegistry() *customers.Registry { return m.reg }
func (m *mergeProc) ReapplySellInFiles(_ context.Context, _ string, files, chains []string) ([]ingestion.ReapplyResult, []string) {
	m.lastFiles, m.lastChains = files, chains
	m.nilFiles = files == nil
	return []ingestion.ReapplyResult{{File: "in26.xlsx", Rows: 2}}, nil
}
func (m *mergeProc) SellInYears(string) []int        { return nil }
func (m *mergeProc) SellOutMonths(string, int) []int { return nil }
func (m *mergeProc) SellInCustomerLiveStats(string) map[string]ingestion.CustomerLiveStat {
	return m.stats
}

func mergeClaims(role domain.UserRole) *domain.UserClaims {
	return &domain.UserClaims{TenantID: "tenant-adeco", Email: "admin@adeco-retail.com", Role: role, UserID: "u1"}
}

func postRegistry(t *testing.T, h *CustomerRegistryHandler, path, body string, role domain.UserRole) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader([]byte(body)))
	req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, mergeClaims(role)))
	rec := httptest.NewRecorder()
	switch {
	case strings.HasSuffix(path, "/approve"):
		h.HandleApprove(rec, req)
	case strings.HasSuffix(path, "/unmerge"):
		h.HandleUnmerge(rec, req)
	default:
		t.Fatalf("unknown path %s", path)
	}
	return rec
}

func TestHandleApproveMergeReappliesChainAndUnmergeKeepsApproved(t *testing.T) {
	ctx := context.Background()
	reg := customers.New(&customers.MemoryStore{})
	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	alias := "عائله فتح الله ماركت مواد عناية - كفر الدوار2"
	if _, err := reg.Decide(ctx, "tenant-adeco", canonical, customers.StatusApproved, "fathalla", "", "seed"); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Decide(ctx, "tenant-adeco", alias, customers.StatusApproved, "fathalla", "", "seed"); err != nil {
		t.Fatal(err)
	}
	proc := &mergeProc{reg: reg, stats: map[string]ingestion.CustomerLiveStat{
		customers.NormalizeName(alias):     {Name: alias, Chain: "fathalla", Rows: 10, Value: 100, Files: []string{"in26.xlsx"}},
		customers.NormalizeName(canonical): {Name: canonical, Chain: "fathalla", Rows: 20, Value: 200, Files: []string{"in26.xlsx"}},
	}}
	h := NewCustomerRegistryHandler(proc, nil)

	rec := postRegistry(t, h, "/api/v1/customers/registry/approve",
		`{"name":"`+alias+`","chain":"fathalla","alias_of":"`+canonical+`"}`, domain.RoleVendorAdmin)
	if rec.Code != http.StatusOK {
		t.Fatalf("merge HTTP %d body %s", rec.Code, rec.Body.String())
	}
	if !proc.nilFiles && len(proc.lastFiles) == 0 {
		t.Fatalf("expected a re-apply of the chain or archived files, got files=%v chains=%v", proc.lastFiles, proc.lastChains)
	}
	if len(proc.lastChains) != 1 || proc.lastChains[0] != "fathalla" {
		t.Fatalf("re-apply must stay on fathalla, got %v", proc.lastChains)
	}
	got, err := json.Marshal(reg.List(ctx, "tenant-adeco", customers.StatusApproved, false))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"alias_of":"`+canonical+`"`) && !strings.Contains(string(got), canonical) {
		t.Fatalf("alias_of not stored: %s", got)
	}

	rec = postRegistry(t, h, "/api/v1/customers/registry/unmerge",
		`{"name":"`+alias+`"}`, domain.RoleVendorAdmin)
	if rec.Code != http.StatusOK {
		t.Fatalf("unmerge HTTP %d body %s", rec.Code, rec.Body.String())
	}
	found := false
	for _, e := range reg.List(ctx, "tenant-adeco", "", false) {
		if e.Key == customers.NormalizeName(alias) {
			found = true
			if e.Status != customers.StatusApproved {
				t.Fatalf("unmerge of a merge must keep the name approved, got %s", e.Status)
			}
			if strings.TrimSpace(e.AliasOf) != "" {
				t.Fatalf("alias_of must be cleared, got %q", e.AliasOf)
			}
		}
	}
	if !found {
		t.Fatal("alias entry missing after unmerge")
	}
}

func TestHandleApproveMergeRejectedForViewerAndCrossChain(t *testing.T) {
	ctx := context.Background()
	reg := customers.New(&customers.MemoryStore{})
	if _, err := reg.Decide(ctx, "tenant-adeco", "A", customers.StatusApproved, "fathalla", "", "s"); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Decide(ctx, "tenant-adeco", "B", customers.StatusApproved, "carrefour", "", "s"); err != nil {
		t.Fatal(err)
	}
	h := NewCustomerRegistryHandler(&mergeProc{reg: reg}, nil)

	rec := postRegistry(t, h, "/api/v1/customers/registry/approve",
		`{"name":"A","chain":"fathalla","alias_of":"B"}`, domain.RoleViewer)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("viewer must be 403, got %d %s", rec.Code, rec.Body.String())
	}
	rec = postRegistry(t, h, "/api/v1/customers/registry/approve",
		`{"name":"A","chain":"fathalla","alias_of":"B"}`, domain.RoleVendorAdmin)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("cross-chain must be 400, got %d %s", rec.Code, rec.Body.String())
	}
}

func TestHandleListIncludesLiveStats(t *testing.T) {
	ctx := context.Background()
	reg := customers.New(&customers.MemoryStore{})
	name := "عائله فتح الله ماركت - كفر الدوار 2"
	if _, err := reg.Decide(ctx, "tenant-adeco", name, customers.StatusApproved, "fathalla", "", "s"); err != nil {
		t.Fatal(err)
	}
	proc := &mergeProc{reg: reg, stats: map[string]ingestion.CustomerLiveStat{
		customers.NormalizeName(name): {Name: name, Chain: "fathalla", Rows: 42, Value: 99.5, Files: []string{"in26.xlsx"}},
	}}
	h := NewCustomerRegistryHandler(proc, nil)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/customers/registry?status=approved", nil)
	req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, mergeClaims(domain.RoleVendorAdmin)))
	rec := httptest.NewRecorder()
	h.HandleList(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"live_rows":42`) || !strings.Contains(body, `"live_chain":"fathalla"`) {
		t.Fatalf("missing live stats: %s", body)
	}
}

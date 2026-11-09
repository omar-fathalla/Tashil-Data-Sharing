package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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

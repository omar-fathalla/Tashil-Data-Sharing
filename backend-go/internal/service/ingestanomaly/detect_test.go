package ingestanomaly

import (
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func rec(barcode, store, date string, qty int, rev float64) domain.NormalizedRecord {
	return domain.NormalizedRecord{
		Barcode:         barcode,
		ResolvedStoreID: store,
		TransactionDate: date,
		QuantitySold:    qty,
		NetRevenue:      rev,
	}
}

func byType(anoms []domain.IngestionAnomaly, typ string) []domain.IngestionAnomaly {
	var out []domain.IngestionAnomaly
	for _, a := range anoms {
		if a.IssueType == typ {
			out = append(out, a)
		}
	}
	return out
}

func TestDetect_Negatives(t *testing.T) {
	records := []domain.NormalizedRecord{
		rec("6221001", "crf_maadi", "2026-01-15", 10, 100),
		rec("6221002", "crf_maadi", "2026-01-15", -3, 50),
		rec("6221003", "crf_maadi", "2026-01-15", 5, -20),
	}
	got := Detect(records, nil)
	negs := byType(got, TypeNegativeSales)
	if len(negs) != 2 {
		t.Fatalf("expected 2 negative_sales, got %d (%+v)", len(negs), got)
	}
	if negs[0].RowNumber != 2 || negs[1].RowNumber != 3 {
		t.Fatalf("unexpected rows: %+v", negs)
	}
}

func TestDetect_Duplicates(t *testing.T) {
	dup := rec("6221001", "crf_maadi", "2026-01-15", 10, 100)
	records := []domain.NormalizedRecord{
		dup,
		rec("6221002", "crf_maadi", "2026-01-15", 4, 40),
		dup, // exact duplicate of row 1
	}
	got := Detect(records, nil)
	dups := byType(got, TypeDuplicateRow)
	if len(dups) != 1 || dups[0].RowNumber != 3 {
		t.Fatalf("expected duplicate on row 3, got %+v", dups)
	}
	if !strings.Contains(dups[0].Description, "row 1") {
		t.Fatalf("description should reference first row: %q", dups[0].Description)
	}
}

func TestDetect_UnitPriceOutlier(t *testing.T) {
	records := make([]domain.NormalizedRecord, 0, 10)
	// Nine normal ~10 EGP unit prices for one product, then one extreme on the same barcode.
	for i := 0; i < 9; i++ {
		records = append(records, rec("6221001", "crf_maadi", "2026-01-15", 10, 100))
	}
	records = append(records, rec("6221001", "crf_maadi", "2026-01-16", 1, 10000)) // same product outlier

	got := Detect(records, nil)
	outs := byType(got, TypeUnitPriceOutlier)
	if len(outs) != 1 || outs[0].RowNumber != 10 {
		t.Fatalf("expected outlier on row 10, got %+v", outs)
	}
}

func TestDetect_UnitPriceOutlier_SkipsSmallSamples(t *testing.T) {
	records := []domain.NormalizedRecord{
		rec("a", "s", "2026-01-01", 1, 10),
		rec("a", "s", "2026-01-02", 1, 10),
		rec("a", "s", "2026-01-03", 1, 9999), // same product but < minOutlierSamples
	}
	got := Detect(records, nil)
	if outs := byType(got, TypeUnitPriceOutlier); len(outs) != 0 {
		t.Fatalf("expected no outlier with < %d samples, got %+v", minOutlierSamples, outs)
	}
}

func TestDetect_UnitPriceOutlier_GroupsByProduct(t *testing.T) {
	// Product A ~10 EGP, product B ~500 EGP — different normals must not cross-flag.
	records := make([]domain.NormalizedRecord, 0, 20)
	for i := 0; i < 8; i++ {
		records = append(records, rec("6221001", "crf_maadi", "2026-01-15", 10, 100)) // ~10
	}
	for i := 0; i < 8; i++ {
		records = append(records, rec("6222002", "crf_maadi", "2026-01-15", 2, 1000)) // ~500
	}
	got := Detect(records, nil)
	if outs := byType(got, TypeUnitPriceOutlier); len(outs) != 0 {
		t.Fatalf("mixed normal prices across products should not flag outliers, got %+v", outs)
	}

	// Extreme price on product A only — still flagged within that product's distribution.
	records = append(records, rec("6221001", "crf_maadi", "2026-01-16", 1, 10000))
	got = Detect(records, nil)
	outs := byType(got, TypeUnitPriceOutlier)
	if len(outs) != 1 || outs[0].RowNumber != len(records) {
		t.Fatalf("expected one product-A outlier on last row, got %+v", outs)
	}
}

func TestDetect_MomSpike(t *testing.T) {
	records := []domain.NormalizedRecord{
		rec("6221001", "crf_maadi", "2026-01-10", 10, 100),
		rec("6221001", "crf_maadi", "2026-02-10", 10, 500), // +400% MoM
		rec("6221002", "crf_maadi", "2026-01-10", 5, 50),
		rec("6221002", "crf_maadi", "2026-02-10", 5, 55), // mild — no spike
	}
	got := Detect(records, nil)
	spikes := byType(got, TypeMomSpike)
	if len(spikes) != 1 {
		t.Fatalf("expected 1 mom_spike, got %+v", spikes)
	}
	if spikes[0].RowNumber != 2 {
		t.Fatalf("expected spike flagged on Feb row 2, got %+v", spikes[0])
	}
	if !strings.Contains(spikes[0].Description, "up") {
		t.Fatalf("expected up direction: %q", spikes[0].Description)
	}
}

func TestDetect_MomSpike_Down(t *testing.T) {
	records := []domain.NormalizedRecord{
		rec("6221001", "crf_maadi", "2026-01-10", 10, 1000),
		rec("6221001", "crf_maadi", "2026-02-10", 10, 100), // -90% drop vs prior consecutive month
	}
	got := Detect(records, nil)
	spikes := byType(got, TypeMomSpike)
	if len(spikes) != 1 || !strings.Contains(spikes[0].Description, "down") {
		t.Fatalf("expected down mom_spike, got %+v", spikes)
	}
}

func TestDetect_MomSpike_RequiresConsecutiveMonths(t *testing.T) {
	// Jan → Mar with Feb missing: large jump must NOT flag (non-consecutive).
	records := []domain.NormalizedRecord{
		rec("6221001", "crf_maadi", "2026-01-10", 10, 100),
		rec("6221001", "crf_maadi", "2026-03-10", 10, 500), // +400% but gap
	}
	got := Detect(records, nil)
	if spikes := byType(got, TypeMomSpike); len(spikes) != 0 {
		t.Fatalf("expected no mom_spike across missing month, got %+v", spikes)
	}

	// Year boundary Dec → Jan is consecutive and should still flag.
	records = []domain.NormalizedRecord{
		rec("6221001", "crf_maadi", "2025-12-10", 10, 100),
		rec("6221001", "crf_maadi", "2026-01-10", 10, 500),
	}
	got = Detect(records, nil)
	spikes := byType(got, TypeMomSpike)
	if len(spikes) != 1 {
		t.Fatalf("expected mom_spike across Dec→Jan, got %+v", spikes)
	}
}

func TestMonthsConsecutive(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"2026-01", "2026-02", true},
		{"2025-12", "2026-01", true},
		{"2026-01", "2026-03", false},
		{"2026-02", "2026-01", false},
		{"bad", "2026-02", false},
	}
	for _, tc := range cases {
		if got := monthsConsecutive(tc.a, tc.b); got != tc.want {
			t.Errorf("monthsConsecutive(%q,%q)=%v want %v", tc.a, tc.b, got, tc.want)
		}
	}
}

func TestDetect_DedupesExisting(t *testing.T) {
	records := []domain.NormalizedRecord{
		rec("6221001", "crf_maadi", "2026-01-15", -1, 10),
	}
	existing := []domain.IngestionAnomaly{{
		RowNumber: 1, IssueType: TypeNegativeSales, Description: "already flagged",
	}}
	got := Detect(records, existing)
	negs := byType(got, TypeNegativeSales)
	if len(negs) != 1 || negs[0].Description != "already flagged" {
		t.Fatalf("should keep existing negative, got %+v", negs)
	}
}

func TestDetect_Empty(t *testing.T) {
	if got := Detect(nil, nil); len(got) != 0 {
		t.Fatalf("expected empty, got %+v", got)
	}
}

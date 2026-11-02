package handlers

import "testing"

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

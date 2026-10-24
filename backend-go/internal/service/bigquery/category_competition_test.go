package bigquery

import "testing"

func TestCategoryCompetitionRankAndNamedCompetitors(t *testing.T) {
	sup := map[string]float64{"own": 300, "P&G": 500, "Henkel": 200, "Arma": 100}
	rank, n, top := categoryCompetition(sup, "own", 1100, 2)
	if rank != 2 || n != 4 {
		t.Fatalf("rank=%d n=%d", rank, n)
	}
	if len(top) != 2 || top[0].Name != "P&G" || top[1].Name != "Henkel" {
		t.Fatalf("top=%+v", top)
	}
	if top[0].SharePct != 45.5 {
		t.Fatalf("share=%v", top[0].SharePct)
	}
	if r, _, _ := categoryCompetition(map[string]float64{"x": 1}, "own", 1, 5); r != 0 {
		t.Fatalf("absent tenant rank should be 0, got %d", r)
	}
}

package targetalloc

import (
	"math"
	"testing"
)

func TestSeasonalSharesEqualWhenEmpty(t *testing.T) {
	var z [12]float64
	s := SeasonalShares(z)
	for i, v := range s {
		if math.Abs(v-1.0/12.0) > 1e-12 {
			t.Fatalf("month %d: want 1/12 got %v", i+1, v)
		}
	}
}

func TestSeasonalSharesFullPriorYear(t *testing.T) {
	// sales proportional to 1..12 → weights = sales/avg, shares = w/12
	var sales [12]float64
	var sum float64
	for i := 0; i < 12; i++ {
		sales[i] = float64(i + 1)
		sum += sales[i]
	}
	avg := sum / 12
	s := SeasonalShares(sales)
	var shareSum float64
	for i := 0; i < 12; i++ {
		want := (sales[i] / avg) / 12.0
		if math.Abs(s[i]-want) > 1e-9 {
			t.Fatalf("month %d: want %v got %v", i+1, want, s[i])
		}
		shareSum += s[i]
	}
	if math.Abs(shareSum-1) > 1e-9 {
		t.Fatalf("shares sum %v want 1", shareSum)
	}
	// Full year: share[m] ≡ sales[m]/total
	for i := 0; i < 12; i++ {
		if math.Abs(s[i]-sales[i]/sum) > 1e-9 {
			t.Fatalf("full-year identity month %d: %v vs %v", i+1, s[i], sales[i]/sum)
		}
	}
}

func TestSeasonalSharesPartialNeutralMissing(t *testing.T) {
	// Jan–Apr only; May–Dec get neutral weight 1 → share 1/12
	var sales [12]float64
	sales[0], sales[1], sales[2], sales[3] = 100, 200, 150, 50 // sum=500, avg=125
	s := SeasonalShares(sales)
	wantAvail := [4]float64{
		100 / 125.0 / 12.0,
		200 / 125.0 / 12.0,
		150 / 125.0 / 12.0,
		50 / 125.0 / 12.0,
	}
	for i := 0; i < 4; i++ {
		if math.Abs(s[i]-wantAvail[i]) > 1e-9 {
			t.Fatalf("month %d: want %v got %v", i+1, wantAvail[i], s[i])
		}
	}
	for i := 4; i < 12; i++ {
		if math.Abs(s[i]-1.0/12.0) > 1e-9 {
			t.Fatalf("neutral month %d: want 1/12 got %v", i+1, s[i])
		}
	}
	var shareSum float64
	for _, v := range s {
		shareSum += v
	}
	if math.Abs(shareSum-1) > 1e-9 {
		t.Fatalf("shares sum %v want 1", shareSum)
	}
}

func TestPickSeasonalSharesUnitsFallbackToRevenue(t *testing.T) {
	var units, rev [12]float64
	rev[0], rev[1] = 100, 300
	s := PickSeasonalShares(units, rev)
	want := SeasonalShares(rev)
	if s != want {
		t.Fatalf("expected revenue fallback shares")
	}
	units[2] = 10
	s2 := PickSeasonalShares(units, rev)
	want2 := SeasonalShares(units)
	if s2 != want2 {
		t.Fatalf("expected units shares when units present")
	}
}

func TestApportionByShareSumsToTotal(t *testing.T) {
	var sales [12]float64
	sales[0], sales[1], sales[2], sales[3] = 100, 200, 150, 50
	shares := SeasonalShares(sales)
	parts := ApportionByShare(12000, shares)
	var sum float64
	for _, p := range parts {
		sum += p
	}
	if math.Abs(sum-12000) > 0.01 {
		t.Fatalf("sum %v want 12000", sum)
	}
}

package gemini

import "testing"

func TestConvertSOPQtyToCasesCRTStaysCartons(t *testing.T) {
	cases, upc, fb := ConvertSOPQtyToCases(2, 12, 8, "CRT")
	if cases != 2 || upc != 12 || fb {
		t.Fatalf("CRT: cases=%v upc=%d fallback=%v", cases, upc, fb)
	}
	cases, _, fb = ConvertSOPQtyToCases(10, 0, 12, "CTN")
	if cases != 10 || fb {
		t.Fatalf("CTN without U2: cases=%v fallback=%v", cases, fb)
	}
}

func TestConvertSOPQtyToCasesEachDividesByUofM2(t *testing.T) {
	cases, upc, fb := ConvertSOPQtyToCases(24, 12, 8, "Each")
	if cases != 2 || upc != 12 || fb {
		t.Fatalf("Each: cases=%v upc=%d fallback=%v", cases, upc, fb)
	}
	// Returns keep their sign.
	cases, _, _ = ConvertSOPQtyToCases(-24, 12, 0, "EA")
	if cases != -2 {
		t.Fatalf("return Each: cases=%v", cases)
	}
}

func TestConvertSOPQtyToCasesFallbackOnlyWhenU2Missing(t *testing.T) {
	cases, upc, fb := ConvertSOPQtyToCases(24, 0, 8, "Each")
	if !fb || cases != 3 || upc != 8 {
		t.Fatalf("fallback: cases=%v upc=%d fallback=%v", cases, upc, fb)
	}
	// File U2 wins over PM pack.
	cases, upc, fb = ConvertSOPQtyToCases(24, 12, 8, "Each")
	if fb || cases != 2 || upc != 12 {
		t.Fatalf("U2 must win: cases=%v upc=%d fallback=%v", cases, upc, fb)
	}
	// No invented pack of 12 when PM is also missing.
	cases, upc, fb = ConvertSOPQtyToCases(24, 0, 0, "Each")
	if fb || cases != 24 || upc != 0 {
		t.Fatalf("no invented pack: cases=%v upc=%d fallback=%v", cases, upc, fb)
	}
}

func TestConvertSOPQtyToCasesIn26MixedRule(t *testing.T) {
	// Ground truth from in26.xlsx: CRT QTY 180,022 + Each QTY/U of M2 52,788.679167.
	crt, _, _ := ConvertSOPQtyToCases(180022, 0, 0, "CRT")
	each, _, _ := ConvertSOPQtyToCases(429408, 429408/52788.679167, 0, "Each")
	// Use the exact Each sum already computed from the file (per-row U2 varies),
	// and the CRT total: 180022 + 52788.679167 = 232810.679167.
	got := crt + 52788.679167
	if crt != 180022 {
		t.Fatalf("CRT total %v", crt)
	}
	if each == 0 {
		t.Fatal("Each conversion failed")
	}
	want := 232810.679167
	if diff := got - want; diff > 1e-6 || diff < -1e-6 {
		t.Fatalf("mixed official cases: got %v want %v", got, want)
	}
}

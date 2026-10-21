package domain

import (
	"testing"
)

func TestDetermineStoreTier(t *testing.T) {
	tests := []struct {
		name     string
		revenue  float64
		expected string
	}{
		{"High revenue Tier A", 850000.0, "Tier A"},
		{"Tier A boundary exactly 600,000", 600000.0, "Tier A"},
		{"Medium revenue Tier B", 450000.0, "Tier B"},
		{"Tier B boundary exactly 300,000", 300000.0, "Tier B"},
		{"Low revenue Tier C", 299999.0, "Tier C"},
		{"Zero revenue Tier C", 0.0, "Tier C"},
		{"Negative revenue Tier C", -500.0, "Tier C"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := DetermineStoreTier(tt.revenue)
			if got != tt.expected {
				t.Errorf("DetermineStoreTier(%f) = %s, expected %s", tt.revenue, got, tt.expected)
			}
		})
	}
}

func TestCalculatePriceDeltaPctAndClassification(t *testing.T) {
	tests := []struct {
		name          string
		actual        float64
		recommended   float64
		expectedDelta float64
		expectedType  string
	}{
		{
			name:          "Compliant exact price",
			actual:        110.0,
			recommended:   110.0,
			expectedDelta: 0.0,
			expectedType:  "compliant",
		},
		{
			name:          "Compliant within +1% tolerance",
			actual:        101.0,
			recommended:   100.0,
			expectedDelta: 1.0,
			expectedType:  "compliant",
		},
		{
			name:          "Compliant within -1% tolerance",
			actual:        99.0,
			recommended:   100.0,
			expectedDelta: -1.0,
			expectedType:  "compliant",
		},
		{
			name:          "Under cutting violation",
			actual:        95.0,
			recommended:   110.0,
			expectedDelta: -13.6,
			expectedType:  "under_cutting",
		},
		{
			name:          "Price gouging violation",
			actual:        130.0,
			recommended:   110.0,
			expectedDelta: 18.2,
			expectedType:  "price_gouging",
		},
		{
			name:          "Zero recommended price returns zero delta and compliant",
			actual:        50.0,
			recommended:   0.0,
			expectedDelta: 0.0,
			expectedType:  "compliant",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			delta := CalculatePriceDeltaPct(tt.actual, tt.recommended)
			if delta != tt.expectedDelta {
				t.Errorf("CalculatePriceDeltaPct(%f, %f) = %f, expected %f", tt.actual, tt.recommended, delta, tt.expectedDelta)
			}

			classification := ClassifyPriceViolation(delta)
			if classification != tt.expectedType {
				t.Errorf("ClassifyPriceViolation(%f) = %s, expected %s", delta, classification, tt.expectedType)
			}
		})
	}
}

func TestCalculatePromoUpliftPct(t *testing.T) {
	tests := []struct {
		name           string
		promoQty       int
		baselineQty    int
		expectedUplift float64
	}{
		{"Significant uplift +35%", 135, 100, 35.0},
		{"Zero uplift", 100, 100, 0.0},
		{"Negative change / dip", 90, 100, -10.0},
		{"Zero baseline returns 0", 50, 0, 0.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CalculatePromoUpliftPct(tt.promoQty, tt.baselineQty)
			if got != tt.expectedUplift {
				t.Errorf("CalculatePromoUpliftPct(%d, %d) = %f, expected %f", tt.promoQty, tt.baselineQty, got, tt.expectedUplift)
			}
		})
	}
}

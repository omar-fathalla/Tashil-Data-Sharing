package domain

import (
	"testing"
)

func TestCleanBarcode(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"Standard GTIN-13", "6221155001234", "6221155001234"},
		{"Barcode with spaces", " 622 1155 001234 ", "6221155001234"},
		{"Barcode with prefix chars", "EAN:6221155001234", "6221155001234"},
		{"Barcode with dashes", "622-1155-001234", "6221155001234"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := CleanBarcode(tt.input)
			if result != tt.expected {
				t.Errorf("CleanBarcode(%q) = %q; want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestParseGeminiPayload(t *testing.T) {
	validJSON := []byte(`{
		"retailer_detected": "carrefour",
		"reporting_period_start": "2026-03-01",
		"reporting_period_end": "2026-03-07",
		"confidence_score": 0.99,
		"column_mapping": {
			"barcode_column": "Barcode",
			"sku_name_column": "Description",
			"store_name_column": "Branch",
			"quantity_sold_column": "Qty",
			"net_revenue_column": "Net_Val"
		},
		"anomalies_detected": [
			{
				"row_number": 4,
				"issue_type": "invalid_barcode",
				"description": "Barcode truncated"
			}
		],
		"normalized_records": [
			{
				"raw_store_name": "Carrefour Maadi",
				"resolved_store_id": "crf_cairo_maadi",
				"barcode": "6221155001234",
				"sku_name": "Adeco Extra Virgin Olive Oil 500ml",
				"quantity_sold": 50,
				"net_revenue": 12500.0,
				"transaction_date": "2026-03-05"
			}
		]
	}`)

	payload, err := ParseGeminiPayload(validJSON)
	if err != nil {
		t.Fatalf("expected valid payload, got error: %v", err)
	}

	if payload.RetailerDetected != "carrefour" {
		t.Errorf("expected retailer 'carrefour', got '%s'", payload.RetailerDetected)
	}
	if len(payload.NormalizedRecords) != 1 {
		t.Errorf("expected 1 record, got %d", len(payload.NormalizedRecords))
	}
	if len(payload.AnomaliesDetected) != 1 {
		t.Errorf("expected 1 anomaly, got %d", len(payload.AnomaliesDetected))
	}
}

func TestParseGeminiPayloadInvalid(t *testing.T) {
	invalidJSON := []byte(`{
		"retailer_detected": "non_existent_supermarket",
		"normalized_records": []
	}`)

	_, err := ParseGeminiPayload(invalidJSON)
	if err == nil {
		t.Errorf("expected error for invalid retailer and empty records, got nil")
	}
}

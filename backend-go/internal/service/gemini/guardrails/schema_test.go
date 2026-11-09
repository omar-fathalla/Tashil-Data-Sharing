package guardrails

import (
	"strings"
	"testing"
)

const validPlan = `{"header_row_index":2,"skip_rows":[0,1],"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"category"},{"index":2,"role":"barcode"},{"index":3,"role":"product_name"},
{"index":4,"role":"store_value","branch":"سموحة"},{"index":5,"role":"store_quantity","branch":"سموحة"},
{"index":6,"role":"total_value"},{"index":7,"role":"month"},{"index":11,"role":"year"}]}`

func TestValidateColumnMapPlanJSON_OK(t *testing.T) {
	plan, err := ValidateColumnMapPlanJSON([]byte(validPlan))
	if err != nil {
		t.Fatal(err)
	}
	if plan.Layout != "wide" || plan.Confidence != 0.95 {
		t.Fatalf("unexpected plan: %+v", plan)
	}
}

func TestValidateColumnMapPlanJSON_Rejects(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{"empty", "", "empty"},
		{"bad_json", "{", "invalid json"},
		{"bad_layout", `{"header_row_index":0,"layout":"pivot","confidence":1,"columns":[{"index":0,"role":"barcode"}]}`, "layout"},
		{"no_columns", `{"header_row_index":0,"layout":"long","confidence":1,"columns":[]}`, "columns"},
		{"bad_role", `{"header_row_index":0,"layout":"long","confidence":1,"columns":[{"index":0,"role":"magic"}]}`, "role"},
		{"confidence", `{"header_row_index":0,"layout":"long","confidence":1.5,"columns":[{"index":0,"role":"barcode"}]}`, "confidence"},
		{"branch_required", `{"header_row_index":0,"layout":"wide","confidence":0.9,"columns":[{"index":0,"role":"store_value"}]}`, "branch"},
		{"dup_index", `{"header_row_index":0,"layout":"long","confidence":0.9,"columns":[{"index":0,"role":"barcode"},{"index":0,"role":"quantity"}]}`, "duplicate"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ValidateColumnMapPlanJSON([]byte(tc.raw))
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
}

func TestValidateIngestionPayloadJSON_OK(t *testing.T) {
	raw := `{
		"retailer_detected":"carrefour",
		"confidence_score":0.91,
		"mapping_source":"ai",
		"mapping_confidence":0.91,
		"column_mapping":{
			"barcode_column":"Barcode",
			"store_name_column":"Branch",
			"quantity_sold_column":"Qty",
			"net_revenue_column":"Net"
		},
		"anomalies_detected":[{"row_number":2,"issue_type":"invalid_barcode","description":"short"}],
		"normalized_records":[{
			"resolved_store_id":"crf_maadi",
			"barcode":"6221155001234",
			"quantity_sold":10,
			"net_revenue":100.5,
			"transaction_date":"2026-01-15"
		}]
	}`
	if err := ValidateIngestionPayloadJSON([]byte(raw)); err != nil {
		t.Fatal(err)
	}
}

func TestValidateIngestionPayloadJSON_AllowsPhaseBTypes(t *testing.T) {
	raw := `{
		"retailer_detected":"carrefour",
		"confidence_score":0.91,
		"mapping_source":"ai",
		"mapping_confidence":0.91,
		"column_mapping":{
			"barcode_column":"Barcode",
			"store_name_column":"Branch",
			"quantity_sold_column":"Qty",
			"net_revenue_column":"Net"
		},
		"anomalies_detected":[
			{"row_number":2,"issue_type":"duplicate_row","description":"dup"},
			{"row_number":3,"issue_type":"unit_price_outlier","description":"price"},
			{"row_number":4,"issue_type":"mom_spike","description":"spike"}
		],
		"normalized_records":[{
			"resolved_store_id":"crf_maadi",
			"barcode":"6221155001234",
			"quantity_sold":10,
			"net_revenue":100.5,
			"transaction_date":"2026-01-15"
		}]
	}`
	if err := ValidateIngestionPayloadJSON([]byte(raw)); err != nil {
		t.Fatal(err)
	}
}

func TestValidateIngestionPayloadJSON_Rejects(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want string
	}{
		{"no_retailer", `{"column_mapping":{"barcode_column":"a","store_name_column":"b","quantity_sold_column":"c","net_revenue_column":"d"},"normalized_records":[{"resolved_store_id":"s","barcode":"1","quantity_sold":1,"net_revenue":1,"transaction_date":"2026-01-01"}]}`, "retailer"},
		{"bad_retailer", `{"retailer_detected":"nope","column_mapping":{"barcode_column":"a","store_name_column":"b","quantity_sold_column":"c","net_revenue_column":"d"},"normalized_records":[{"resolved_store_id":"s","barcode":"1","quantity_sold":1,"net_revenue":1,"transaction_date":"2026-01-01"}]}`, "unrecognized"},
		{"empty_records", `{"retailer_detected":"fathalla","column_mapping":{"barcode_column":"a","store_name_column":"b","quantity_sold_column":"c","net_revenue_column":"d"},"normalized_records":[]}`, "non-empty"},
		{"bad_source", `{"retailer_detected":"fathalla","mapping_source":"invented","column_mapping":{"barcode_column":"a","store_name_column":"b","quantity_sold_column":"c","net_revenue_column":"d"},"normalized_records":[{"resolved_store_id":"s","barcode":"1","quantity_sold":1,"net_revenue":1,"transaction_date":"2026-01-01"}]}`, "mapping_source"},
		{"bad_anomaly", `{"retailer_detected":"fathalla","column_mapping":{"barcode_column":"a","store_name_column":"b","quantity_sold_column":"c","net_revenue_column":"d"},"anomalies_detected":[{"row_number":1,"issue_type":"made_up","description":"x"}],"normalized_records":[{"resolved_store_id":"s","barcode":"1","quantity_sold":1,"net_revenue":1,"transaction_date":"2026-01-01"}]}`, "issue_type"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateIngestionPayloadJSON([]byte(tc.raw))
			if err == nil || !strings.Contains(strings.ToLower(err.Error()), strings.ToLower(tc.want)) {
				t.Fatalf("want %q in error, got %v", tc.want, err)
			}
		})
	}
}

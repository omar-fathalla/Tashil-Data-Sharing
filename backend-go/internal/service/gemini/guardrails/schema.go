// Package guardrails validates Gemini structured output and enforces ingest safety rules
// (schema, human approval, no mock in production, minimal PII, per-call logs).
package guardrails

import (
	"encoding/json"
	"fmt"
	"math"
	"strings"
)

// Allowed column-map roles (must stay aligned with ai_column_mapping.go).
var allowedColumnRoles = map[string]bool{
	"barcode": true, "product_name": true, "category": true, "supplier": true,
	"store": true, "store_value": true, "store_quantity": true,
	"quantity": true, "value": true, "return": true,
	"month": true, "year": true, "date": true,
	"total_value": true, "total_quantity": true, "ignore": true,
}

var allowedRetailers = map[string]bool{
	"carrefour": true, "fathalla": true, "gomla": true, "beet-elgomla": true,
	"beet_elgomla": true, "spinneys": true, "metro": true, "seoudi": true,
	"kazyon": true, "unknown": true,
}

var allowedAnomalyTypes = map[string]bool{
	"invalid_barcode": true, "negative_sales": true, "unmapped_store": true, "missing_price": true,
}

var allowedMappingSources = map[string]bool{
	"": true, "ai": true, "deterministic": true, "cache": true, "mock": true,
}

// ColumnMapPlan is the Gemini column-mapping JSON shape (duplicated here so this
// package does not import the gemini service and create a cycle).
type ColumnMapPlan struct {
	HeaderRowIndex int          `json:"header_row_index"`
	SkipRows       []int        `json:"skip_rows,omitempty"`
	Layout         string       `json:"layout"`
	Columns        []ColumnRole `json:"columns"`
	Confidence     float64      `json:"confidence"`
}

// ColumnRole is one mapped column.
type ColumnRole struct {
	Index  int    `json:"index"`
	Role   string `json:"role"`
	Branch string `json:"branch,omitempty"`
}

// ValidateColumnMapPlanJSON unmarshals and validates a Gemini column-map response.
func ValidateColumnMapPlanJSON(raw []byte) (*ColumnMapPlan, error) {
	if len(strings.TrimSpace(string(raw))) == 0 {
		return nil, fmt.Errorf("column map plan: empty json")
	}
	var plan ColumnMapPlan
	if err := json.Unmarshal(raw, &plan); err != nil {
		return nil, fmt.Errorf("column map plan: invalid json: %w", err)
	}
	if err := ValidateColumnMapPlan(&plan); err != nil {
		return nil, err
	}
	return &plan, nil
}

// ValidateColumnMapPlan checks required fields, enums, and numeric bounds.
func ValidateColumnMapPlan(plan *ColumnMapPlan) error {
	if plan == nil {
		return fmt.Errorf("column map plan: nil")
	}
	if plan.HeaderRowIndex < 0 {
		return fmt.Errorf("column map plan: header_row_index must be >= 0")
	}
	switch plan.Layout {
	case "wide", "long":
	default:
		return fmt.Errorf("column map plan: layout must be wide|long, got %q", plan.Layout)
	}
	if len(plan.Columns) == 0 {
		return fmt.Errorf("column map plan: columns required")
	}
	if plan.Confidence < 0 || plan.Confidence > 1 || math.IsNaN(plan.Confidence) {
		return fmt.Errorf("column map plan: confidence must be in [0,1], got %v", plan.Confidence)
	}
	seen := map[int]bool{}
	for i, c := range plan.Columns {
		if c.Index < 0 {
			return fmt.Errorf("column map plan: columns[%d].index must be >= 0", i)
		}
		if seen[c.Index] {
			return fmt.Errorf("column map plan: duplicate column index %d", c.Index)
		}
		seen[c.Index] = true
		if !allowedColumnRoles[c.Role] {
			return fmt.Errorf("column map plan: columns[%d].role %q not allowed", i, c.Role)
		}
		if (c.Role == "store_value" || c.Role == "store_quantity") && strings.TrimSpace(c.Branch) == "" {
			return fmt.Errorf("column map plan: columns[%d] role %s requires branch", i, c.Role)
		}
	}
	return nil
}

// payloadProbe is a minimal structural view of NormalizedRetailIngestionPayload for schema checks.
type payloadProbe struct {
	RetailerDetected  string `json:"retailer_detected"`
	ConfidenceScore   float64 `json:"confidence_score"`
	MappingSource     string `json:"mapping_source"`
	MappingConfidence float64 `json:"mapping_confidence"`
	ColumnMapping     *struct {
		BarcodeColumn      string `json:"barcode_column"`
		StoreNameColumn    string `json:"store_name_column"`
		QuantitySoldColumn string `json:"quantity_sold_column"`
		NetRevenueColumn   string `json:"net_revenue_column"`
	} `json:"column_mapping"`
	AnomaliesDetected []struct {
		RowNumber   int    `json:"row_number"`
		IssueType   string `json:"issue_type"`
		Description string `json:"description"`
	} `json:"anomalies_detected"`
	NormalizedRecords []struct {
		ResolvedStoreID string  `json:"resolved_store_id"`
		Barcode         string  `json:"barcode"`
		QuantitySold    int     `json:"quantity_sold"`
		NetRevenue      float64 `json:"net_revenue"`
		TransactionDate string  `json:"transaction_date"`
	} `json:"normalized_records"`
}

// ValidateIngestionPayloadJSON validates Gemini full-normalize JSON against the contract schema.
func ValidateIngestionPayloadJSON(raw []byte) error {
	if len(strings.TrimSpace(string(raw))) == 0 {
		return fmt.Errorf("ingestion payload: empty json")
	}
	var p payloadProbe
	if err := json.Unmarshal(raw, &p); err != nil {
		return fmt.Errorf("ingestion payload: invalid json: %w", err)
	}
	return validatePayloadProbe(&p)
}

func validatePayloadProbe(p *payloadProbe) error {
	retailer := strings.ToLower(strings.TrimSpace(p.RetailerDetected))
	if retailer == "" {
		return fmt.Errorf("ingestion payload: retailer_detected required")
	}
	if !allowedRetailers[retailer] {
		return fmt.Errorf("ingestion payload: unrecognized retailer %q", p.RetailerDetected)
	}
	if p.ColumnMapping == nil {
		return fmt.Errorf("ingestion payload: column_mapping required")
	}
	cm := p.ColumnMapping
	if strings.TrimSpace(cm.BarcodeColumn) == "" ||
		strings.TrimSpace(cm.StoreNameColumn) == "" ||
		strings.TrimSpace(cm.QuantitySoldColumn) == "" ||
		strings.TrimSpace(cm.NetRevenueColumn) == "" {
		return fmt.Errorf("ingestion payload: column_mapping missing required columns")
	}
	if len(p.NormalizedRecords) == 0 {
		return fmt.Errorf("ingestion payload: normalized_records must be non-empty")
	}
	if p.ConfidenceScore < 0 || p.ConfidenceScore > 1 {
		return fmt.Errorf("ingestion payload: confidence_score must be in [0,1]")
	}
	if !allowedMappingSources[strings.ToLower(strings.TrimSpace(p.MappingSource))] {
		return fmt.Errorf("ingestion payload: mapping_source %q not allowed", p.MappingSource)
	}
	if p.MappingConfidence < 0 || p.MappingConfidence > 1 {
		return fmt.Errorf("ingestion payload: mapping_confidence must be in [0,1]")
	}
	for i, a := range p.AnomaliesDetected {
		if a.RowNumber < 0 {
			return fmt.Errorf("ingestion payload: anomalies[%d].row_number invalid", i)
		}
		if !allowedAnomalyTypes[a.IssueType] {
			return fmt.Errorf("ingestion payload: anomalies[%d].issue_type %q not allowed", i, a.IssueType)
		}
		if strings.TrimSpace(a.Description) == "" {
			return fmt.Errorf("ingestion payload: anomalies[%d].description required", i)
		}
	}
	for i, r := range p.NormalizedRecords {
		if strings.TrimSpace(r.ResolvedStoreID) == "" || strings.TrimSpace(r.Barcode) == "" {
			return fmt.Errorf("ingestion payload: records[%d] missing store/barcode", i)
		}
		if strings.TrimSpace(r.TransactionDate) == "" {
			return fmt.Errorf("ingestion payload: records[%d] missing transaction_date", i)
		}
	}
	return nil
}

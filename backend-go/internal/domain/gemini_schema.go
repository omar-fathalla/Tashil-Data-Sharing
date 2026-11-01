package domain

import (
	"encoding/json"
	"fmt"
	"strings"
)

// GeminiSchemaJSON represents the JSON Schema passed to the Gemini 3.8 Flash structured output API.
const GeminiSchemaJSON = `{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "NormalizedRetailIngestionPayload",
  "type": "object",
  "properties": {
    "retailer_detected": {
      "type": "string",
      "enum": ["carrefour", "fathalla", "gomla", "spinneys", "unknown"]
    },
    "reporting_period_start": {
      "type": "string",
      "format": "date"
    },
    "reporting_period_end": {
      "type": "string",
      "format": "date"
    },
    "confidence_score": {
      "type": "number",
      "minimum": 0,
      "maximum": 1
    },
    "column_mapping": {
      "type": "object",
      "properties": {
        "barcode_column": { "type": "string" },
        "sku_name_column": { "type": "string" },
        "store_name_column": { "type": "string" },
        "quantity_sold_column": { "type": "string" },
        "net_revenue_column": { "type": "string" }
      },
      "required": ["barcode_column", "store_name_column", "quantity_sold_column", "net_revenue_column"]
    },
    "anomalies_detected": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "row_number": { "type": "integer" },
          "issue_type": {
            "type": "string",
            "enum": ["invalid_barcode", "negative_sales", "unmapped_store", "missing_price"]
          },
          "description": { "type": "string" }
        },
        "required": ["row_number", "issue_type", "description"]
      }
    },
    "normalized_records": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "raw_store_name": { "type": "string" },
          "resolved_store_id": { "type": "string" },
          "barcode": { "type": "string" },
          "sku_name": { "type": "string" },
          "quantity_sold": { "type": "integer" },
          "net_revenue": { "type": "number" },
          "transaction_date": { "type": "string", "format": "date" }
        },
        "required": ["resolved_store_id", "barcode", "quantity_sold", "net_revenue", "transaction_date"]
      }
    }
  },
  "required": ["retailer_detected", "column_mapping", "normalized_records"]
}`

// GeminiCleanSchemaJSON is the schema without draft-07 top-level metadata ($schema, title)
// for direct compatibility with Gemini API responseSchema parameter.
const GeminiCleanSchemaJSON = `{
  "type": "object",
  "properties": {
    "retailer_detected": {
      "type": "string",
      "enum": ["carrefour", "fathalla", "gomla", "spinneys", "unknown"]
    },
    "reporting_period_start": {
      "type": "string"
    },
    "reporting_period_end": {
      "type": "string"
    },
    "confidence_score": {
      "type": "number"
    },
    "column_mapping": {
      "type": "object",
      "properties": {
        "barcode_column": { "type": "string" },
        "sku_name_column": { "type": "string" },
        "store_name_column": { "type": "string" },
        "quantity_sold_column": { "type": "string" },
        "net_revenue_column": { "type": "string" }
      },
      "required": ["barcode_column", "store_name_column", "quantity_sold_column", "net_revenue_column"]
    },
    "anomalies_detected": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "row_number": { "type": "integer" },
          "issue_type": {
            "type": "string",
            "enum": ["invalid_barcode", "negative_sales", "unmapped_store", "missing_price"]
          },
          "description": { "type": "string" }
        },
        "required": ["row_number", "issue_type", "description"]
      }
    },
    "normalized_records": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "raw_store_name": { "type": "string" },
          "resolved_store_id": { "type": "string" },
          "barcode": { "type": "string" },
          "sku_name": { "type": "string" },
          "category": { "type": "string" },
          "quantity_sold": { "type": "integer" },
          "net_revenue": { "type": "number" },
          "transaction_date": { "type": "string" }
        },
        "required": ["resolved_store_id", "barcode", "quantity_sold", "net_revenue", "transaction_date"]
      }
    }
  },
  "required": ["retailer_detected", "column_mapping", "normalized_records"]
}`

// ColumnMapping holds discovered mappings from raw headers to standard canonical keys.
type ColumnMapping struct {
	BarcodeColumn      string `json:"barcode_column"`
	SKUNameColumn      string `json:"sku_name_column"`
	StoreNameColumn    string `json:"store_name_column"`
	QuantitySoldColumn string `json:"quantity_sold_column"`
	NetRevenueColumn   string `json:"net_revenue_column"`
	CategoryColumn     string `json:"category_column,omitempty"`
	SupplierColumn     string `json:"supplier_column,omitempty"`
}

// IngestionAnomaly indicates a single data quality defect detected by Gemini Agent.
type IngestionAnomaly struct {
	RowNumber   int    `json:"row_number"`
	IssueType   string `json:"issue_type"` // invalid_barcode, negative_sales, unmapped_store, missing_price
	Description string `json:"description"`
}

// NormalizedRecord is one unified sell-out line extracted from non-standard retail files.
type NormalizedRecord struct {
	RawStoreName     string  `json:"raw_store_name"`
	ResolvedStoreID  string  `json:"resolved_store_id"`
	ItemCode         string  `json:"item_code,omitempty"`
	Barcode          string  `json:"barcode"`
	SKUName          string  `json:"sku_name"`
	Category         string  `json:"category,omitempty"`
	Supplier         string  `json:"supplier,omitempty"`
	IsOwnBrand       bool    `json:"is_own_brand,omitempty"`
	QuantitySold     int     `json:"quantity_sold"`
	NetRevenue       float64 `json:"net_revenue"`
	UnitPrice        float64 `json:"unit_price,omitempty"`
	RecommendedPrice float64 `json:"recommended_price,omitempty"`
	TransactionDate  string  `json:"transaction_date"` // YYYY-MM-DD
}

// DiscoveredSheetInfo describes a single worksheet/tab detected inside an Excel workbook.
type DiscoveredSheetInfo struct {
	Name         string  `json:"name"`
	State        string  `json:"state"` // "visible" or "hidden"
	RowCount     int     `json:"row_count"`
	RecordsCount int     `json:"records_count"`
	TotalRevenue float64 `json:"total_revenue"`
	TotalUnits   int     `json:"total_units"`
	PeriodDate   string  `json:"period_date,omitempty"`
}

// NormalizedRetailIngestionPayload represents the complete structured response from Gemini 3.8 Flash.
type NormalizedRetailIngestionPayload struct {
	RetailerDetected     string                  `json:"retailer_detected"`
	ReportingPeriodStart string                  `json:"reporting_period_start"`
	ReportingPeriodEnd   string                  `json:"reporting_period_end"`
	ConfidenceScore      float64                 `json:"confidence_score"`
	ColumnMapping        ColumnMapping           `json:"column_mapping"`
	AnomaliesDetected    []IngestionAnomaly      `json:"anomalies_detected"`
	NormalizedRecords    []NormalizedRecord      `json:"normalized_records"`
	DiscoveredBranches   []string                `json:"discovered_branches,omitempty"`
	DiscoveredCategories []string                `json:"discovered_categories,omitempty"`
	SheetsProcessed      []string                `json:"sheets_processed,omitempty"`
	DetectedSheets       []DiscoveredSheetInfo   `json:"detected_sheets,omitempty"`
	SheetsDetectedCount  int                     `json:"sheets_detected_count,omitempty"`
	SupplierShares       []SupplierShareSummary  `json:"supplier_shares,omitempty"`
	CategoryMarketTotals map[string]float64      `json:"category_market_totals,omitempty"`
	MonthlyTrends        []DailyTrendPoint       `json:"monthly_trends,omitempty"`
	ComputedOOSAlerts    []OOSAlert              `json:"computed_oos_alerts,omitempty"`
	ComputedPricingItems []PricingComplianceItem `json:"computed_pricing_items,omitempty"`
	RevenueMoMPct        float64                 `json:"revenue_mom_pct,omitempty"`
	RevenueYoYPct        float64                 `json:"revenue_yoy_pct,omitempty"`
	UnitsMoMPct          float64                 `json:"units_mom_pct,omitempty"`
	UnitsYoYPct          float64                 `json:"units_yoy_pct,omitempty"`
	IsWideMatrixWorkbook bool                    `json:"is_wide_matrix_workbook,omitempty"`
	RawValidRowsCount    int                     `json:"raw_valid_rows_count,omitempty"`
	AiModelUsed          string                  `json:"ai_model_used,omitempty"`
	AiTierUsed           string                  `json:"ai_tier_used,omitempty"`
	Tier2Escalated       bool                    `json:"tier2_escalated,omitempty"`
	MappingSource        string                  `json:"mapping_source,omitempty"` // "ai" or "deterministic"
	MappingConfidence    float64                 `json:"mapping_confidence,omitempty"`
	Validation           *IngestionValidation    `json:"validation,omitempty"`
}

// IngestionValidation records the pre-save totals check for an upload.
type IngestionValidation struct {
	Status          string   `json:"status"` // "ok", "flagged" or "rejected"
	RecordCount     int      `json:"record_count"`
	ExtractedUnits  int      `json:"extracted_units"`
	ExtractedValue  float64  `json:"extracted_value"`
	SourceUnits     float64  `json:"source_units,omitempty"`
	SourceValue     float64  `json:"source_value,omitempty"`
	SheetTotalUnits float64  `json:"sheet_total_units,omitempty"`
	SheetTotalValue float64  `json:"sheet_total_value,omitempty"`
	MonthsDetected  []string `json:"months_detected,omitempty"`
	Issues          []string `json:"issues,omitempty"`
}


// Validate performs sanity and business rule checks on the structured payload.
func (p *NormalizedRetailIngestionPayload) Validate() error {
	p.RetailerDetected = strings.ToLower(strings.TrimSpace(p.RetailerDetected))
	validRetailers := map[string]bool{
		"carrefour":    true,
		"fathalla":     true,
		"gomla":        true,
		"beet-elgomla": true,
		"beet_elgomla": true,
		"spinneys":     true,
		"metro":        true,
		"seoudi":       true,
		"kazyon":       true,
		"unknown":      true,
	}
	if !validRetailers[p.RetailerDetected] {
		return fmt.Errorf("unrecognized retailer: %s", p.RetailerDetected)
	}

	if len(p.NormalizedRecords) == 0 {
		return fmt.Errorf("payload contains zero normalized records")
	}

	return nil
}

// CleanBarcode normalizes GTIN-13/14 barcodes, stripping leading spaces or non-digit chars.
func CleanBarcode(raw string) string {
	var sb strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			sb.WriteRune(r)
		}
	}
	cleaned := sb.String()
	// Pad or normalize standard 13-digit EAN if needed
	return cleaned
}

// ParseGeminiPayload parses raw JSON string into NormalizedRetailIngestionPayload.
func ParseGeminiPayload(rawJSON []byte) (*NormalizedRetailIngestionPayload, error) {
	var payload NormalizedRetailIngestionPayload
	if err := json.Unmarshal(rawJSON, &payload); err != nil {
		return nil, fmt.Errorf("failed to unmarshal gemini structured output: %w", err)
	}
	if err := payload.Validate(); err != nil {
		return nil, fmt.Errorf("invalid gemini payload: %w", err)
	}
	return &payload, nil
}

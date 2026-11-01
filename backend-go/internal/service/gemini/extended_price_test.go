package gemini

import (
	"strings"
	"testing"
)

// ERP sales-GP exports (header structure mirrors the real in25 sell-in file, rows are
// made up) carry the value in "Extended Price" under a From/To date block.
func TestExtendedPriceIsReadAsValue(t *testing.T) {
	rows := [][]string{
		{"", "From Date", "To Date"},
		{"", "2025-01-01", "2025-12-31"},
		{""},
		{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", "Extended Price", "Trade Discount Amount", "Item Tax Schedule ID"},
		{"Invoice", "INV-1", "2025-01-01", "SKU-1", "منتج 1", "CRT", "2", "L1", "C1", "فرع 1", "MT", "200.5", "0", "VAT"},
		{"Invoice", "INV-2", "2025-02-03", "SKU-2", "منتج 2", "CRT", "1", "L1", "C1", "فرع 1", "MT", "99.5", "0", "VAT"},
	}
	xlsxBytes, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatalf("build xlsx: %v", err)
	}
	payload, ok := parseFullTabularPayload("in25.xlsx", xlsxBytes)
	if !ok || payload == nil {
		t.Fatalf("expected workbook to parse")
	}
	var revenue float64
	for _, r := range payload.NormalizedRecords {
		revenue += r.NetRevenue
	}
	if revenue != 300 {
		t.Fatalf("expected value 300 from Extended Price, got %v", revenue)
	}
}

func TestNewAgentTrimsKeyWhitespace(t *testing.T) {
	c := NewAgent("abc\n", "", false)
	if strings.ContainsAny(c.apiKey, "\n ") {
		t.Fatalf("api key not trimmed")
	}
}

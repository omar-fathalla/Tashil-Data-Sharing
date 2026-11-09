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

// in26-style Dynamics exports sometimes rename the value header (no space / dotted /
// parenthetical EGP) or ship only TO (turnover) with no Extended Price column.
func TestExtendedPriceAliasHeadersMapForGPSOP(t *testing.T) {
	aliases := []string{
		"ExtendedPrice",
		"Ext. Price",
		"Ext. Price (EGP)",
		"XTNDPRCE",
		"Extended\u00a0Price", // NBSP between words
		"TO",                 // real in26.xlsx value column
	}
	for _, alias := range aliases {
		t.Run(alias, func(t *testing.T) {
			rows := [][]string{
				{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", alias, "Branch"},
				{"Invoice", "INV-1", "2026-01-05", "FG-1", "صنف", "CTN", "2", "L1", "C1", "عائله فتح الله ماركت - طنطا", "KA", "150", "TNT"},
				{"Return", "INV-2", "2026-01-06", "FG-1", "صنف", "CTN", "-1", "L1", "C1", "عائله فتح الله ماركت - طنطا", "KA", "-25", "TNT"},
			}
			x, err := BuildSampleXLSX(rows)
			if err != nil {
				t.Fatal(err)
			}
			recs, _, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.xlsx", x, "fathalla")
			if err != nil {
				t.Fatalf("alias %q should map as Extended Price/TO: %v", alias, err)
			}
			if len(recs) != 2 {
				t.Fatalf("alias %q: expected 2 rows, got %d", alias, len(recs))
			}
			var sum float64
			for _, r := range recs {
				sum += r.NetValueEGP
			}
			if sum != 125 {
				t.Fatalf("alias %q: expected signed TO sum 125, got %v (%+v)", alias, sum, recs)
			}
			if recs[1].NetValueEGP >= 0 {
				t.Fatalf("alias %q: return row must keep negative TO", alias)
			}
		})
	}
}

// Extended Price wins over TO when both columns exist (older in25-style exports).
func TestExtendedPricePreferredOverTO(t *testing.T) {
	rows := [][]string{
		{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Customer Name", "Extended Price", "TO"},
		{"Invoice", "INV-1", "2026-01-05", "FG-1", "صنف", "CTN", "1", "عائله فتح الله ماركت - طنطا", "100", "999"},
	}
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	recs, _, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in25.xlsx", x, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 1 || recs[0].NetValueEGP != 100 {
		t.Fatalf("Extended Price must win over TO: %+v", recs)
	}
}

func TestNewAgentTrimsKeyWhitespace(t *testing.T) {
	c := NewAgent("abc\n", "", false)
	if strings.ContainsAny(c.apiKey, "\n ") {
		t.Fatalf("api key not trimmed")
	}
}

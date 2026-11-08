package gemini

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func TestParseChainBranchCellFirstDash(t *testing.T) {
	cases := []struct {
		in, chain, branch string
	}{
		{"عائله فتح الله ماركت - دمنهور", "عائله فتح الله ماركت", "دمنهور"},
		{"عائله فتح الله ماركت - دمنهور - الاستاد", "عائله فتح الله ماركت", "دمنهور - الاستاد"},
		{"عائله فتح الله ماركت – طنطا", "عائله فتح الله ماركت", "طنطا"},
		{"عائله فتح الله ماركت — كفر الشيخ", "عائله فتح الله ماركت", "كفر الشيخ"},
		{"عائله فتح الله ماركت-دمنهور", "عائله فتح الله ماركت", "دمنهور"},
		{"عائله فتح الله ماركت -  فلمنج", "عائله فتح الله ماركت", "فلمنج"},
		{"عائله فتح الله ماركت -  أمواج", "عائله فتح الله ماركت", "أمواج"},
		{"عائله فتح الله ماركت مواد عناية - دمنهور - الاستاد", "عائله فتح الله ماركت مواد عناية", "دمنهور - الاستاد"},
		{"دمنهور", "", "دمنهور"},
		{"", "", ""},
	}
	for _, c := range cases {
		chain, branch := ParseChainBranchCell(c.in)
		if chain != c.chain || branch != c.branch {
			t.Fatalf("%q → chain=%q branch=%q want %q / %q", c.in, chain, branch, c.chain, c.branch)
		}
	}
	// دمنهور - الاستاد must stay distinct from دمنهور
	_, a := ParseChainBranchCell("عائله فتح الله ماركت - دمنهور")
	_, b := ParseChainBranchCell("عائله فتح الله ماركت - دمنهور - الاستاد")
	if a == b {
		t.Fatalf("stadium branch must differ from plain damanhour: %q vs %q", a, b)
	}
}

func TestNormalizeArabicLabelGroupsVariants(t *testing.T) {
	a := normalizeArabicLabel("عائلة فتح الله ماركت")
	b := normalizeArabicLabel("عائله  فتح الله ماركـت")
	if a != b {
		t.Fatalf("expected Arabic variants to group: %q vs %q", a, b)
	}
}

func TestCollectDistinctBranchesFullColumn(t *testing.T) {
	rows := make([][]string, 0, 30)
	for i := 0; i < 20; i++ {
		rows = append(rows, []string{"عائله فتح الله ماركت - دمنهور", fmt.Sprintf("6223000%04d", i), "1", "10"})
	}
	rows = append(rows,
		[]string{"عائله فتح الله ماركت - طنطا", "62230009901", "1", "10"},
		[]string{"عائله فتح الله ماركت - كفر الشيخ", "62230009902", "1", "10"},
		[]string{"عائله فتح الله ماركت - دمنهور - الاستاد", "62230009903", "1", "10"},
		[]string{"عائلة فتح الله ماركت - دمنهور", "62230009904", "1", "10"}, // ه/ة variant of first
	)
	got := collectDistinctBranches(rows, 0)
	if len(got) != 4 {
		t.Fatalf("expected 4 distinct customer cells, got %d: %v", len(got), got)
	}
}

func TestSectionHeaderStoreFill(t *testing.T) {
	rows := [][]string{
		{"عائله فتح الله ماركت - دمنهور", "", "", ""},
		{"", "62230000001", "2", "50"},
		{"", "62230000002", "1", "20"},
		{"عائله فتح الله ماركت - طنطا", "", "", ""},
		{"", "62230000003", "3", "90"},
	}
	applySectionHeaderStoreFill(rows, 0, 1, 2, 3)
	if rows[1][0] != "عائله فتح الله ماركت - دمنهور" || rows[2][0] != "عائله فتح الله ماركت - دمنهور" {
		t.Fatalf("damanhour section not filled: %+v", rows)
	}
	if rows[4][0] != "عائله فتح الله ماركت - طنطا" {
		t.Fatalf("tanta section not filled: %+v", rows)
	}
}

// First 20 data rows are branch A (دمنهور); later rows are طنطا and كفر الشيخ.
// AI only sees the leading sample (all A) but extraction must land all 3 branches with fathalla chain.
func TestAIMappingFullColumnBranchesAfterSample(t *testing.T) {
	header := []string{"Store_Name", "Barcode", "Item_Description", "Qty_Sold", "Net_Amount", "Date"}
	rows := [][]string{header}
	for i := 0; i < 20; i++ {
		rows = append(rows, []string{
			"عائله فتح الله ماركت - دمنهور",
			fmt.Sprintf("62230002337%02d", i),
			"صنف", "1", "10", "2026-01-15",
		})
	}
	rows = append(rows,
		[]string{"عائله فتح الله ماركت - طنطا", "6223000233801", "صنف", "2", "20", "2026-01-16"},
		[]string{"عائله فتح الله ماركت - كفر الشيخ", "6223000233802", "صنف", "3", "30", "2026-01-17"},
	)
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	plan := `{"header_row_index":0,"layout":"long","confidence":0.95,"columns":[
{"index":0,"role":"store"},{"index":1,"role":"barcode"},{"index":2,"role":"product_name"},
{"index":3,"role":"quantity"},{"index":4,"role":"value"},{"index":5,"role":"date"}]}`
	var calls []string
	c := stubClient(map[string]string{"tier1-model": plan}, &calls)
	p, err := c.AnalyzeAndNormalize(context.Background(), "branches_full_column.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceAI {
		t.Fatalf("expected AI mapping, got %s", p.MappingSource)
	}
	if len(p.DiscoveredBranches) != 3 {
		t.Fatalf("expected 3 discovered branches after full-column scan, got %d: %v", len(p.DiscoveredBranches), p.DiscoveredBranches)
	}
	storeIDs := map[string]bool{}
	for _, r := range p.NormalizedRecords {
		storeIDs[r.ResolvedStoreID] = true
		if !strings.HasPrefix(r.ResolvedStoreID, "fat_") {
			t.Fatalf("expected fathalla store id, got %s for %q", r.ResolvedStoreID, r.RawStoreName)
		}
	}
	if len(storeIDs) != 3 {
		t.Fatalf("expected 3 distinct store IDs in records, got %d: %v", len(storeIDs), storeIDs)
	}
}

func TestGPSOPFullColumnChainBranchParse(t *testing.T) {
	hdr := []string{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", "TO", "Branch"}
	rows := [][]string{hdr}
	for i := 0; i < 20; i++ {
		rows = append(rows, []string{"Invoice", fmt.Sprintf("INV-%d", i), "2026-03-02", fmt.Sprintf("FG-%d", i), "صنف", "CTN", "1", "L1", "C1", "عائله فتح الله ماركت - دمنهور", "KA", "10", "BHR"})
	}
	rows = append(rows,
		[]string{"Invoice", "INV-T", "2026-03-03", "FG-T", "صنف", "CTN", "1", "L1", "C1", "عائله فتح الله ماركت - طنطا", "KA", "20", "TNT"},
		[]string{"Invoice", "INV-K", "2026-03-04", "FG-K", "صنف", "CTN", "1", "L1", "C1", "عائله فتح الله ماركت - كفر الشيخ", "KA", "30", "BRG"},
		[]string{"Invoice", "INV-S", "2026-03-05", "FG-S", "صنف", "CTN", "1", "L1", "C1", "عائله فتح الله ماركت - دمنهور - الاستاد", "KA", "40", "BHR"},
	)
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	recs, _, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26_branches.xlsx", x, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 23 {
		t.Fatalf("expected 23 source rows preserved, got %d", len(recs))
	}
	branches := map[string]string{}
	for _, r := range recs {
		branches[r.CustomerName] = r.RetailerChain
		if r.RetailerChain != "fathalla" {
			t.Fatalf("expected fathalla chain, got %q for %q", r.RetailerChain, r.CustomerName)
		}
	}
	if len(branches) != 4 {
		t.Fatalf("expected 4 customer branches (stadium separate), got %d: %v", len(branches), branches)
	}
	var to float64
	for _, r := range recs {
		to += r.NetValueEGP
	}
	if to != 20*10+20+30+40 {
		t.Fatalf("TO total: got %v", to)
	}
}

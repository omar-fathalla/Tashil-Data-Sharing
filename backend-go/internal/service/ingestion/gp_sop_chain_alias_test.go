package ingestion

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"os"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// gpSOPCSV builds a GP SOP invoice export (the in25/in26 layout) through the real parser input format.
func gpSOPCSV(t *testing.T, names []string) []byte {
	t.Helper()
	var b bytes.Buffer
	w := csv.NewWriter(&b)
	_ = w.Write([]string{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class", "Extended Price", "TO", "Net Q", "Branch"})
	for _, n := range names {
		_ = w.Write([]string{"Invoice", "INV1", "2026-03-02", "FG-1", "صنف تجريبي", "CTN", "2", "L1", "C1", n, "KA", "100", "100", "2", "ALX"})
	}
	w.Flush()
	return b.Bytes()
}

func aliasNewNames(t *testing.T) []string {
	t.Helper()
	raw, err := os.ReadFile("../customers/seed_aliases.json")
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]string
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(m))
	for n := range m {
		out = append(out, n)
	}
	return out
}

// H1: a GP SOP export has no chain column, so an empty / all / الكل chain is rejected by the parser.
func TestGPSOPParserRejectsMissingChain(t *testing.T) {
	file := gpSOPCSV(t, []string{"زهران - البيطاش"})
	for _, chain := range []string{"", "  ", "all", "ALL", "الكل", "جميع السلاسل"} {
		recs, rep, err := gemini.ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.csv", file, chain)
		var ce *gemini.SellInChainRequiredError
		if !errors.As(err, &ce) || len(recs) != 0 {
			t.Errorf("chain %q: want SellInChainRequiredError and no rows, got err=%v rows=%d", chain, err, len(recs))
			continue
		}
		if rep.Layout != "gp_sop_export" || ce.Error() == "" {
			t.Errorf("chain %q: layout=%q msg=%q", chain, rep.Layout, ce.Error())
		}
	}
	// No variadic chain at all is also rejected.
	if _, _, err := gemini.ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.csv", file); err == nil {
		t.Error("no chain argument: want rejection")
	}
}

// H1: through the real parser, a zahran (or gomla) GP SOP upload keeps its own chain, nothing is
// aliased and «زهران - البيطاش» goes to quarantine; a fathalla upload aliases all 84 approved.
func TestGPSOPParserChainDrivesAliases(t *testing.T) {
	ctx := context.Background()
	for _, chain := range []string{"zahran", "gomla"} {
		recs, rep, err := gemini.ParseSellInPlanWorkbookWithReport("tenant-adeco", "z.csv", gpSOPCSV(t, []string{"زهران - البيطاش"}), chain)
		if err != nil || len(recs) != 1 {
			t.Fatalf("%s: err=%v rows=%d", chain, err, len(recs))
		}
		if recs[0].RetailerChain != chain {
			t.Fatalf("%s: row chain=%q", chain, recs[0].RetailerChain)
		}
		kept, q := customers.New(&customers.MemoryStore{}).PartitionLayout(ctx, "tenant-adeco", "z.csv", chain, rep.Layout, recs, false)
		if len(kept) != 0 || len(q) != 1 || q[0].Name != "زهران - البيطاش" {
			t.Errorf("%s: want quarantine under own name, kept=%+v q=%+v", chain, kept, q)
		}
	}

	names := aliasNewNames(t)
	if len(names) != 84 {
		t.Fatalf("want 84 aliases, got %d", len(names))
	}
	recs, rep, err := gemini.ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.csv", gpSOPCSV(t, names), "fathalla")
	if err != nil || len(recs) != 84 {
		t.Fatalf("fathalla: err=%v rows=%d", err, len(recs))
	}
	kept, q := customers.New(&customers.MemoryStore{}).PartitionLayout(ctx, "tenant-adeco", "in26.csv", "fathalla", rep.Layout, recs, false)
	if len(q) != 0 || len(kept) != 84 {
		t.Fatalf("fathalla: kept=%d quarantined=%d", len(kept), len(q))
	}
	for _, k := range kept {
		if len(k.CustomerName) < len("فرع فتح الله - ") || k.CustomerName[:len("فرع فتح الله - ")] != "فرع فتح الله - " {
			t.Errorf("fathalla row not aliased to the seed name: %q", k.CustomerName)
		}
	}
}

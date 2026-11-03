package ingestion

import (
	"context"
	"crypto/sha256"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Parity on the real client workbooks (never committed; opt-in: set TDS_CLIENT_ARCHIVE, e.g.
// /tmp/rq/arch; takes ~6 min). Each file is replayed (non-interactive, as the archive sync does) into its own
// in-memory processor with the production customer registry; stored rows, value, per-chain value
// and the customer-name / branch-id digests must equal the main@677b1c9 baseline. Then the file is
// re-applied for chain fathalla (the customer-confirmation path) and must not change anything.
func TestClientFilesParity(t *testing.T) {
	dir := os.Getenv("TDS_CLIENT_ARCHIVE")
	if dir == "" {
		t.Skip("TDS_CLIENT_ARCHIVE not set (opt-in parity on real client workbooks)")
	}
	type want struct {
		file            string
		rows            int
		value           float64
		perChain        map[string]float64 // millions, 2 decimals
		names, branches string
	}
	cases := []want{
		// Rows/per-chain here are the in-memory harness values produced by main@677b1c9 with an empty
		// customer registry (raw parsed rows; the 133,861/62,681 BigQuery counts and the
		// gomla/wakala/zahran split come from the prod registry and are checked read-only in BQ).
		{file: "in25.xlsx", rows: 65412, value: 178651114.63, perChain: map[string]float64{"fathalla": 137.86, "beet-elgomla": 40.79}, names: "82:d557869ea3a75f7fc", branches: "82:e46ecc43e395b4500"},
		{file: "in26.xlsx", rows: 137985, value: 308139541.92, perChain: map[string]float64{"fathalla": 267.71, "beet-elgomla": 40.43}, names: "169:a72b9bdd9a7dfddd", branches: "169:95273a163811808b"},
		{file: "arch_sellin_adeco_fathalla_1792619328568966000_Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", rows: 7826, value: 122733380.01, perChain: map[string]float64{"fathalla": 122.73}, names: "2:779b62a37ea55c8db9", branches: "18:6abccfc80bf5783ad"},
	}
	for _, w := range cases {
		path := filepath.Join(dir, w.file)
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Logf("skip %s: %v", w.file, err)
			continue
		}
		t.Run(w.file, func(t *testing.T) {
			ctx := context.Background()
			bq := bigquery.NewClient("test-proj", "test-dataset", true)
			p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
			p.SetCustomerRegistry(customers.New(&customers.MemoryStore{}))
			if _, err := p.ProcessSellInPlan(ctx, "tenant-adeco", w.file, raw, false, "fathalla"); err != nil {
				t.Fatal(err)
			}
			check := func(stage string) {
				rows, total := 0, 0.0
				per := map[string]float64{}
				names, branches := map[string]bool{}, map[string]bool{}
				for _, r := range bq.SellInRecordsSnapshot("tenant-adeco") {
					if r.SourceFilename != "" && r.SourceFilename != w.file {
						continue
					}
					rows++
					total += r.NetValueEGP
					per[bigquery.ResolveSellInChain(r.CustomerName, r.RetailerChain)] += r.NetValueEGP
					names[r.CustomerName] = true
					branches[r.CustomerName+"|"+r.CustomerBranchCode] = true
				}
				dig := func(m map[string]bool) string {
					var k []string
					for x := range m {
						k = append(k, x)
					}
					sort.Strings(k)
					return fmt.Sprintf("%d:%x", len(k), sha256.Sum256([]byte(strings.Join(k, "\n"))))[:20]
				}
				t.Logf("PARITY %s %s rows=%d value=%.2f per=%v names=%s branches=%s", stage, w.file, rows, total, per, dig(names), dig(branches))
				if rows != w.rows || math.Abs(total-w.value) > 0.005 {
					t.Errorf("%s: rows %d value %.2f, want %d / %.2f", stage, rows, total, w.rows, w.value)
				}
				for c, m := range w.perChain {
					if got := math.Round(per[c]/1e4) / 100; got != m {
						t.Errorf("%s: chain %s = %.2fM, want %.2fM", stage, c, got, m)
					}
				}
				if dig(names) != w.names || dig(branches) != w.branches {
					t.Errorf("%s: digests %s/%s want %s/%s", stage, dig(names), dig(branches), w.names, w.branches)
				}
			}
			check("upload")
			if _, errs := p.ReapplySellInFiles(ctx, "tenant-adeco", []string{w.file}, []string{"fathalla"}); len(errs) != 0 {
				t.Fatalf("reapply: %v", errs)
			}
			check("reapply-fathalla")
		})
	}
}

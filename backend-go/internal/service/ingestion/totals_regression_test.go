package ingestion

import (
	"context"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Production archive copies are not in the repo (client data). When present locally
// (TDS_ARCHIVE_DIR, default /tmp/rq/arch), the served Sell-In totals must stay exactly as in
// BigQuery and every customer name must be known to the seeded registry (zero quarantine).
func TestArchivedSellInTotalsUnchanged(t *testing.T) {
	dir := os.Getenv("TDS_ARCHIVE_DIR")
	if dir == "" {
		dir = "/tmp/rq/arch"
	}
	raw, err := os.ReadFile(filepath.Join(dir, "in25.xlsx"))
	if err != nil {
		t.Skip("archive copies not present")
	}
	want := []float64{9435369.3, 16218728.9, 15279372.22, 8932178.47, 15174393.46, 13804372.66, 15544184.03, 16997892.17, 11519079.81, 23672194.97, 18417710.93, 13655637.71}
	wantQty := []float64{44050, 68321, 63824, 43841, 62197, 56097, 80594, 72280, 84066, 113290, 96360, 74393}
	recs, _, err := gemini.ParseSellInPlanWorkbookWithReport("tenant-adeco", "in25.xlsx", raw, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	val := make([]float64, 13)
	qty := make([]float64, 13)
	for _, r := range recs {
		if r.Year != 2025 {
			t.Fatalf("in25 row with year %d", r.Year)
		}
		val[r.MonthNum] += r.NetValueEGP
		qty[r.MonthNum] += r.NetQtyCases
	}
	for m := 1; m <= 12; m++ {
		if math.Abs(val[m]-want[m-1]) > 0.05 {
			t.Errorf("2025-%02d value %.2f want %.2f", m, val[m], want[m-1])
		}
		// Prod served +1 invented unit in 2025-05 (value/420 rule, now removed).
		d := qty[m] - wantQty[m-1]
		if !(d == 0 || (m == 5 && d == -1)) {
			t.Errorf("2025-%02d qty %.0f want %.0f", m, qty[m], wantQty[m-1])
		}
	}
	reg := customers.New(&customers.MemoryStore{})
	files, _ := filepath.Glob(filepath.Join(dir, "in2*.xlsx"))
	clean, _ := filepath.Glob(filepath.Join(dir, "arch_sellin_*.xlsx"))
	files = append(files, clean...)
	for _, path := range files {
		f := filepath.Base(path)
		b, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		rs, _, err := gemini.ParseSellInPlanWorkbookWithReport("tenant-adeco", f, b, "fathalla")
		if err != nil {
			t.Fatal(err)
		}
		if _, q := reg.Partition(context.Background(), "tenant-adeco", f, "fathalla", rs, false); len(q) != 0 {
			t.Errorf("%s: %d names would be quarantined, first %q", f, len(q), q[0].Name)
		}
	}
}

package bigquery

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const perfTenant = "tenant-si-perf"

var (
	perfWordsA = []string{"احمر", "ازرق", "اخضر", "اصفر", "برتقالي", "بنفسجي", "وردي", "رمادي", "بني", "ذهبي",
		"فضي", "كحلي", "زيتي", "سماوي", "لبني", "خمري", "عنابي", "فيروزي", "نيلي", "كريمي"}
	perfWordsB = []string{"تفاح", "موز", "عنب", "مانجو", "خوخ", "كمثرى", "رمان", "ليمون", "برتقال", "فراوله",
		"توت", "كرز", "مشمش", "تين", "بلح", "جوافه", "كيوي", "اناناس", "بطيخ", "شمام"}
)

// newLargeDerivedFixture seeds ~1k Product Master items, Sell-Out history over 20 branches x 200 SKUs,
// 12 monthly + 1 annual Sell-Out targets, and 50k Sell-In rows of which 40% match no Product Master item (no item code).
func newLargeDerivedFixture(tb testing.TB) (*Client, time.Duration) {
	tb.Helper()
	tb.Setenv("TASHIL_TARGETS_DIR", tb.TempDir())
	c := NewClient("tashil-test", "retail", true)
	ctx := context.Background()

	brands := []string{"ديفا (Diva)", "فلفيتا", "كلوريل", "اوكسي", "بريل", "جيف", "داوني", ""}
	items := make([]domain.ProductMasterItem, 1000)
	for i := range items {
		items[i] = domain.ProductMasterItem{
			SerialNo: i + 1, ItemCode: fmt.Sprintf("FGPF-%04d", i), ItemCodePrefix: "FGPF",
			Barcode:      fmt.Sprintf("62230%08d", i),
			OfficialName: fmt.Sprintf("منتج %s رقم %d عبوه %d جم", brands[i%len(brands)], i, 100+(i%9)*50),
			Brand:        brands[i%len(brands)], UnitsPerCarton: 6 + i%3*6, NetUnitInvoiceCost: float64(5 + i%40),
		}
	}
	if _, err := c.SetProductMaster(ctx, perfTenant, &domain.ProductMasterSummaryResponse{TenantID: perfTenant, Items: items}); err != nil {
		tb.Fatal(err)
	}

	var facts []domain.SellOutFact
	for b := 0; b < 20; b++ {
		for s := 0; s < 200; s++ {
			facts = append(facts, domain.SellOutFact{
				RecordID: fmt.Sprintf("so-%d-%d", b, s), TenantID: perfTenant, RetailerChain: "fathalla",
				StoreID: fmt.Sprintf("st%02d", b), StoreName: fmt.Sprintf("فتح الله - فرع %d", b),
				ItemCode: items[s].ItemCode, SKUName: items[s].OfficialName, UnitsPerCarton: 12,
				QuantitySold: 5 + (b*s)%30, NetRevenue: float64(50 + (b*s)%300), TransactionDate: fmt.Sprintf("2025-%02d-10", 1+s%12),
			})
		}
	}
	if err := c.InsertSellOutFacts(ctx, facts); err != nil {
		tb.Fatal(err)
	}
	for m := 0; m <= 12; m++ {
		if _, err := c.UpsertTarget(ctx, perfTenant, domain.TargetRecord{
			TargetType: "sell_out", RetailerChain: "fathalla", Year: 2026, Month: m, TargetUnits: float64(20000 + m*100), TargetRevenueEGP: 500000,
		}); err != nil {
			tb.Fatal(err)
		}
	}

	rows := make([]domain.SellInRecord, 50000)
	for i := range rows {
		cases := float64(1 + i%5)
		r := domain.SellInRecord{
			RecordID: fmt.Sprintf("si-%d", i), TenantID: perfTenant, RetailerChain: "fathalla",
			Year: 2025 + i%2, MonthNum: 1 + i%12,
			CustomerName: fmt.Sprintf("فتح الله - فرع %d", i%20), CustomerBranchCode: fmt.Sprintf("st%02d", i%20),
			NetQtyCases: cases, NetValueEGP: cases * 120,
		}
		if i%10 < 6 {
			it := items[i%1000]
			r.ItemCode, r.ItemName = it.ItemCode, it.OfficialName
		} else {
			// Unmatched rows carry no item code (and no number the fuzzy matcher could align on), like the
			// production SOP rows that used to be re-matched on every read.
			k := i % 400
			r.ItemName = "صنف منافس " + perfWordsA[k%20] + " " + perfWordsB[k/20]
		}
		if i%97 == 0 {
			r.NetQtyCases, r.NetValueEGP = 0, 0
		}
		rows[i] = r
	}
	start := time.Now()
	c.ReplaceSellInRecords(perfTenant, rows)
	return c, time.Since(start)
}

func TestDerivedSellInReadIsFastOnLargeData(t *testing.T) {
	c, load := newLargeDerivedFixture(t)
	t.Logf("load-time enrichment of 50k Sell-In rows: %v", load)
	opts := DerivedSellInOptions{Chain: "fathalla", Year: 2026}

	start := time.Now()
	cold, err := c.GetDerivedSellInTargetsSummary(context.Background(), perfTenant, opts)
	coldDur := time.Since(start)
	if err != nil {
		t.Fatal(err)
	}
	start = time.Now()
	warm, err := c.GetDerivedSellInTargetsSummary(context.Background(), perfTenant, opts)
	warmDur := time.Since(start)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("cold read %v, warm read %v", coldDur, warmDur)

	if len(cold.Items) != 13 || cold.TotalActualUnits <= 0 || cold.ExcludedFromTotalsCount != 1 {
		t.Fatalf("unexpected summary: items=%d actual=%v excluded=%d", len(cold.Items), cold.TotalActualUnits, cold.ExcludedFromTotalsCount)
	}
	if warm.TotalActualUnits != cold.TotalActualUnits || warm.TotalTargetRevenueEGP != cold.TotalTargetRevenueEGP {
		t.Fatal("warm read must equal the cold read")
	}
	if coldDur > 2*time.Second {
		t.Fatalf("cold read of stored Sell-In targets took %v (want < 2s)", coldDur)
	}
	if warmDur > time.Second {
		t.Fatalf("warm read took %v (want < 1s)", warmDur)
	}
}

func BenchmarkDerivedSellInColdRead(b *testing.B) {
	c, _ := newLargeDerivedFixture(b)
	opts := DerivedSellInOptions{Chain: "fathalla", Year: 2026}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		c.derivedSI.mu.Lock()
		c.derivedSI.cache = nil
		c.derivedSI.mu.Unlock()
		if _, err := c.GetDerivedSellInTargetsSummary(context.Background(), perfTenant, opts); err != nil {
			b.Fatal(err)
		}
	}
}

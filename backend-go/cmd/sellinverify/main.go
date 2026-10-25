// Command sellinverify checks that the durable Sell-In and Sell-Out rows in BigQuery match what the server builds
// in memory from the upload archive, and that loading them back (the multi-instance path) yields the
// same totals. Read-only against BigQuery.
//
//	USE_MOCK_SERVICES=true TASHIL_ARCHIVE_DIR=data/archive PROJECT_ID=tashil-data-sharing \
//	  BIGQUERY_DATASET=tashil_analytics go run ./cmd/sellinverify
package main

import (
	"context"
	"fmt"
	"log"
	"math"
	"os"
	"sort"

	"github.com/tashil/data-sharing/backend/internal/config"
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

type tot struct {
	n                    int
	value, qty, official float64
}

func totals(recs []domain.SellInRecord) map[string]*tot {
	m := map[string]*tot{}
	for _, r := range recs {
		k := fmt.Sprintf("%s|%04d-%02d", r.RetailerChain, r.Year, r.MonthNum)
		if m[k] == nil {
			m[k] = &tot{}
		}
		m[k].n++
		m[k].value += r.NetValueEGP
		m[k].qty += r.NetQtyCases
		m[k].official += r.OfficialListValueExclEGP
	}
	return m
}

func sellOutTotals(facts []domain.SellOutFact) map[string]*tot {
	m := map[string]*tot{}
	for _, f := range facts {
		month := f.TransactionDate
		if len(month) >= 7 {
			month = month[:7]
		}
		k := f.RetailerChain + "|" + month
		if m[k] == nil {
			m[k] = &tot{}
		}
		m[k].n++
		m[k].value += f.NetRevenue
		m[k].qty += float64(f.QuantitySold)
		m[k].official += f.TotalFactoryCost
	}
	return m
}

func compare(label string, a, b map[string]*tot) bool {
	keys := map[string]bool{}
	for k := range a {
		keys[k] = true
	}
	for k := range b {
		keys[k] = true
	}
	ks := make([]string, 0, len(keys))
	for k := range keys {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	ok := true
	var ta, tb tot
	fmt.Printf("\n== %s ==\n%-18s %8s %8s %16s %16s %12s %12s\n", label, "chain|month", "rows A", "rows B", "value A", "value B", "qty A", "qty B")
	for _, k := range ks {
		x, y := a[k], b[k]
		if x == nil {
			x = &tot{}
		}
		if y == nil {
			y = &tot{}
		}
		mark := ""
		if x.n != y.n || math.Abs(x.value-y.value) > 0.01 || math.Abs(x.qty-y.qty) > 0.001 || math.Abs(x.official-y.official) > 0.01 {
			mark, ok = "  MISMATCH", false
		}
		fmt.Printf("%-18s %8d %8d %16.2f %16.2f %12.2f %12.2f%s\n", k, x.n, y.n, x.value, y.value, x.qty, y.qty, mark)
		ta.n += x.n
		ta.value += x.value
		ta.qty += x.qty
		ta.official += x.official
		tb.n += y.n
		tb.value += y.value
		tb.qty += y.qty
		tb.official += y.official
	}
	fmt.Printf("%-18s %8d %8d %16.2f %16.2f %12.2f %12.2f\n", "TOTAL", ta.n, tb.n, ta.value, tb.value, ta.qty, tb.qty)
	fmt.Printf("official list value: A=%.2f B=%.2f\n", ta.official, tb.official)
	return ok
}

func main() {
	cfg := config.Load()
	archDir := os.Getenv("TASHIL_ARCHIVE_DIR")
	if archDir == "" {
		log.Fatal("TASHIL_ARCHIVE_DIR is required")
	}
	ctx := context.Background()
	bqRepo := bigquery.NewClient(cfg.ProjectID, cfg.BigQueryDataset, true)
	fsRepo := firestore.NewClient(cfg.FirestoreDatabase, true)
	agent := gemini.NewAgent(cfg.GeminiAPIKey, cfg.GeminiModel, true)
	p := ingestion.NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(archDir)
	_ = p.ClearTenantData(ctx, "all")
	if err := p.ReplayArchivedFilesToDatabase(ctx); err != nil {
		log.Printf("replay warning: %v", err)
	}
	mem := bqRepo.SellInRecordsSnapshot("tenant-adeco")

	sinkCfg := bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset)
	sinkCfg.Enabled = true
	bqs, ok := bqsink.New(ctx, sinkCfg).(*bqsink.BigQuerySink)
	if !ok {
		log.Fatal("BigQuery sink unavailable")
	}
	durable, err := bqs.ReadSellIn(ctx, "tenant-adeco")
	if err != nil {
		log.Fatal(err)
	}
	ok1 := compare("A = in-memory archive replay, B = BigQuery sell_in_records (raw)", totals(mem), totals(durable))

	p.WithSellInStore(bqs, nil)
	if _, err := p.SyncSellInFromStore(ctx, "tenant-adeco", true); err != nil {
		log.Fatal(err)
	}
	reloaded := bqRepo.SellInRecordsSnapshot("tenant-adeco")
	ok2 := compare("A = in-memory archive replay, B = memory after reload from BigQuery (re-enriched)", totals(mem), totals(reloaded))
	// Sell-Out: archive replay vs BigQuery sell_out_facts vs memory after reload.
	memOut := bqRepo.SellOutFactsSnapshot("tenant-adeco")
	durableOut, err := bqs.ReadSellOut(ctx, "tenant-adeco")
	if err != nil {
		log.Fatal(err)
	}
	ok3 := compare("SELL-OUT A = in-memory archive replay, B = BigQuery sell_out_facts (raw); qty = units, official = factory cost", sellOutTotals(memOut), sellOutTotals(durableOut))
	p.WithSellOutStore(bqs, nil)
	if _, err := p.SyncSellOutFromStore(ctx, "tenant-adeco", true); err != nil {
		log.Fatal(err)
	}
	ok4 := compare("SELL-OUT A = in-memory archive replay, B = memory after reload from BigQuery", sellOutTotals(memOut), sellOutTotals(bqRepo.SellOutFactsSnapshot("tenant-adeco")))
	ok2 = ok2 && ok3 && ok4
	if ok1 && ok2 {
		fmt.Println("\nRESULT: MATCH")
		return
	}
	fmt.Println("\nRESULT: MISMATCH")
	os.Exit(1)
}

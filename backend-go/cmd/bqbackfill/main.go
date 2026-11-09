// Command bqbackfill loads archive files into the BigQuery sink tables.
//
// Default mode (lists / reconciles every archived file of every tenant):
//
//	TASHIL_ARCHIVE_DIR=/path/to/archive go run ./cmd/bqbackfill
//	TASHIL_ARCHIVE_DIR=... PROJECT_ID=... BIGQUERY_DATASET=... go run ./cmd/bqbackfill -execute
//
// Sell-In month-cycle force replay (one archive only — no orphan cleanup):
//
//	TASHIL_ARCHIVE_DIR=... PROJECT_ID=... BIGQUERY_DATASET=... \
//	  USE_MOCK_SERVICES=true go run ./cmd/bqbackfill \
//	  -archive-id=arch_sellin_adeco_fathalla_1794178032976473890 \
//	  -tenant=tenant-adeco -kind=sell_in
//
// Dry-run prints per-month BEFORE/AFTER rows and net TO. Pass -execute to replace only that
// archive's sell_in_records rows and refresh agg_sell_through. Archive id is required for this mode.
//
// Note: like server startup, parsing may write stores/OOS alerts to Firestore when USE_MOCK_SERVICES=false.
// Run with USE_MOCK_SERVICES=true to keep Firestore and Gemini in local mock mode (recommended).
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/config"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func main() {
	execute := flag.Bool("execute", false, "actually write to BigQuery (default: dry-run / list only)")
	archiveID := flag.String("archive-id", "", "force re-parse + replace only this archive id (sell-in month-cycle replay; required for scoped mode)")
	tenant := flag.String("tenant", "tenant-adeco", "tenant id for -archive-id scoped replay")
	kind := flag.String("kind", "sell_in", "sheet kind for -archive-id scoped replay (sell_in only)")
	flag.Parse()

	cfg := config.Load()
	archDir := os.Getenv("TASHIL_ARCHIVE_DIR")
	if archDir == "" {
		log.Fatal("TASHIL_ARCHIVE_DIR is required")
	}

	bqRepo := bigquery.NewClient(cfg.ProjectID, cfg.BigQueryDataset, true)
	fsRepo := firestore.NewClient(cfg.FirestoreDatabase, cfg.UseMockServices)
	agent := gemini.NewAgent(cfg.GeminiAPIKey, cfg.GeminiModel, cfg.UseMockServices).WithTier2Model(cfg.GeminiTier2Model)
	p := ingestion.NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(archDir)

	sinkCfg := bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset)
	sinkCfg.Enabled = true
	sink := bqsink.New(context.Background(), sinkCfg)
	p.WithSink(sink)
	if bqs, ok := sink.(*bqsink.BigQuerySink); ok {
		bqRepo.WithAggregatesWriter(bqs, *tenant)
		p.WithSellInStore(bqs, fsRepo)
		p.WithSellOutStore(bqs, fsRepo)
	}

	if id := strings.TrimSpace(*archiveID); id != "" {
		runScopedSellInReplay(p, *tenant, id, *kind, *execute)
		return
	}

	// Legacy full-archive reconcile (unchanged). Month-cycle redistribute must pass -archive-id.
	list := p.ListArchivedFiles(context.Background(), "all", "", "", "", "all")
	fmt.Printf("archive %s: %d file(s)\n", archDir, len(list.Files))
	for _, f := range list.Files {
		fmt.Printf("  %-15s %-14s %-12s %s\n", f.FileType, f.TenantID, f.RetailChain, f.FileName)
	}

	tenants := map[string]bool{}
	for _, f := range list.Files {
		tenants[f.TenantID] = true
	}
	for t := range tenants {
		rep, err := p.ReconcileArchivesToSink(context.Background(), t, *execute)
		if err != nil {
			log.Printf("tenant %s: %v", t, err)
		}
		if rep == nil {
			continue
		}
		for _, f := range rep.Files {
			fmt.Printf("  %-14s %-45s archive=%-7d bq_before=%-7d legacy=%-7d bq_after=%-7d %s\n", f.Kind, f.FileName, f.ArchiveRows, f.StoredBefore, f.LegacyBefore, f.StoredAfter, f.Action)
		}
		for k, n := range rep.OrphanRows {
			fmt.Printf("  orphan rows %s: %d (deleted=%v)\n", k, n, rep.OrphanDeleted[k])
		}
	}
	if !*execute {
		fmt.Println("dry run: pass -execute to write missing files and drop orphan rows")
		fmt.Println("month-cycle redistribute: pass -archive-id=<id> -tenant=tenant-adeco -kind=sell_in")
	}
}

func runScopedSellInReplay(p *ingestion.Processor, tenantID, archiveID, kind string, execute bool) {
	if strings.TrimSpace(archiveID) == "" {
		log.Fatal("archive id is required for sell-in month-cycle replay (refusing blind rewrite)")
	}
	rep, err := p.ReplaySellInArchive(context.Background(), tenantID, archiveID, kind, execute)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Print(ingestion.FormatSellInArchiveReplayDryRun(rep))
	if execute {
		fmt.Printf("executed: rows_written=%d sink=%s aggregates=%s\n",
			rep.RowsWritten, rep.SinkStatus, rep.AggRefresh)
	}
}

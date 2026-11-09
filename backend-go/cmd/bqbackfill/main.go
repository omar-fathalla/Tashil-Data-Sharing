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
// archive's sell_in_records rows and refresh agg_sell_through. Archive id is required for this mode:
// missing/empty -archive-id with scoped flags exits non-zero before any legacy reconcile.
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
	tenant := flag.String("tenant", "tenant-adeco", "tenant id for scoped sell-in replay (setting this selects scoped mode)")
	kind := flag.String("kind", "sell_in", "sheet kind for scoped sell-in replay (setting this selects scoped mode; sell_in only)")
	flag.Parse()

	archiveIDFlagSet, tenantFlagSet, kindFlagSet := false, false, false
	flag.Visit(func(f *flag.Flag) {
		switch f.Name {
		case "archive-id":
			archiveIDFlagSet = true
		case "tenant":
			tenantFlagSet = true
		case "kind":
			kindFlagSet = true
		}
	})

	mode, err := resolveBackfillMode(archiveIDFlagSet, tenantFlagSet, kindFlagSet, *archiveID)
	if err != nil {
		log.Fatal(err) // non-zero; never reach legacy ReconcileArchivesToSink
	}

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

	if mode == modeScoped {
		runScopedSellInReplay(p, *tenant, strings.TrimSpace(*archiveID), *kind, *execute)
		return
	}

	runLegacyReconcile(p, archDir, *execute)
}

func runLegacyReconcile(p *ingestion.Processor, archDir string, execute bool) {
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
		rep, err := p.ReconcileArchivesToSink(context.Background(), t, execute)
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
	if !execute {
		fmt.Println("dry run: pass -execute to write missing files and drop orphan rows")
		fmt.Println("month-cycle redistribute: pass -archive-id=<id> -tenant=tenant-adeco -kind=sell_in")
	}
}

func runScopedSellInReplay(p *ingestion.Processor, tenantID, archiveID, kind string, execute bool) {
	rep, err := p.ReplaySellInArchive(context.Background(), tenantID, archiveID, kind, execute)
	if err != nil {
		if rep != nil {
			fmt.Print(ingestion.FormatSellInArchiveReplayDryRun(rep))
			if execute {
				fmt.Printf("executed_partial: rows_written=%d sink=%s aggregates=%s\n",
					rep.RowsWritten, rep.SinkStatus, rep.AggRefresh)
			}
		}
		log.Fatal(err)
	}
	fmt.Print(ingestion.FormatSellInArchiveReplayDryRun(rep))
	if execute {
		fmt.Printf("executed: rows_written=%d sink=%s aggregates=%s\n",
			rep.RowsWritten, rep.SinkStatus, rep.AggRefresh)
	}
}

// runBackfillEntry is the CLI gate used by tests: scoped without archive id must not call legacy.
func runBackfillEntry(
	archiveIDFlagSet, tenantFlagSet, kindFlagSet bool,
	archiveID string,
	scoped func(archiveID string),
	legacy func(),
) error {
	mode, err := resolveBackfillMode(archiveIDFlagSet, tenantFlagSet, kindFlagSet, archiveID)
	if err != nil {
		return err
	}
	if mode == modeScoped {
		scoped(strings.TrimSpace(archiveID))
		return nil
	}
	legacy()
	return nil
}

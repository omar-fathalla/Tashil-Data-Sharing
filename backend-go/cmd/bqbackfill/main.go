// Command bqbackfill loads archive files into the BigQuery sink tables.
//
// Sell-In month-cycle force replay (one archive only — no orphan cleanup) — preferred:
//
//	TASHIL_ARCHIVE_DIR=... PROJECT_ID=... BIGQUERY_DATASET=... \
//	  USE_MOCK_SERVICES=true go run ./cmd/bqbackfill \
//	  -archive-id=arch_sellin_adeco_fathalla_1794178032976473890 \
//	  -tenant=tenant-adeco -kind=sell_in
//
// Dry-run prints per-month BEFORE/AFTER rows and net TO. Pass -execute to replace only that
// archive's sell_in_records rows and refresh agg_sell_through.
//
// Unscoped -execute is refused by default (never all-tenant orphan cleanup). The old
// full-archive reconcile requires explicit opt-in:
//
//	go run ./cmd/bqbackfill -legacy-reconcile-all
//	go run ./cmd/bqbackfill -legacy-reconcile-all -execute
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

	"github.com/tashil/data-sharing/backend/internal/config"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func main() {
	f := parseBackfillFlags()
	if err := runBackfillEntry(f, mainScopedReplay, mainLegacyReconcile); err != nil {
		log.Fatal(err)
	}
}

func parseBackfillFlags() backfillCLIFlags {
	execute := flag.Bool("execute", false, "actually write to BigQuery (default: dry-run / list only)")
	legacyAll := flag.Bool("legacy-reconcile-all", false, "opt-in to full-archive reconcile + orphan cleanup across all tenants (dangerous; off by default)")
	archiveID := flag.String("archive-id", "", "force re-parse + replace only this archive id (sell-in month-cycle replay; required for scoped mode)")
	tenant := flag.String("tenant", "tenant-adeco", "tenant id for scoped sell-in replay (setting this selects scoped mode)")
	kind := flag.String("kind", "sell_in", "sheet kind for scoped sell-in replay (setting this selects scoped mode; sell_in only)")
	flag.Parse()

	f := backfillCLIFlags{
		Execute:            *execute,
		LegacyReconcileAll: *legacyAll,
		ArchiveID:          *archiveID,
		Tenant:             *tenant,
		Kind:               *kind,
	}
	flag.Visit(func(fl *flag.Flag) {
		switch fl.Name {
		case "archive-id":
			f.ArchiveIDFlagSet = true
		case "tenant":
			f.TenantFlagSet = true
		case "kind":
			f.KindFlagSet = true
		}
	})
	return f
}

func mustProcessor(tenantHint string) (*ingestion.Processor, string) {
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
		bqRepo.WithAggregatesWriter(bqs, tenantHint)
		p.WithSellInStore(bqs, fsRepo)
		p.WithSellOutStore(bqs, fsRepo)
	}
	return p, archDir
}

func mainScopedReplay(archiveID, tenant, kind string, execute bool) {
	p, _ := mustProcessor(tenant)
	runScopedSellInReplay(p, tenant, archiveID, kind, execute)
}

func mainLegacyReconcile(execute bool) {
	p, archDir := mustProcessor("tenant-adeco")
	runLegacyReconcile(p, archDir, execute)
}

func runLegacyReconcile(p *ingestion.Processor, archDir string, execute bool) {
	list := p.ListArchivedFiles(context.Background(), "all", "", "", "", "all")
	fmt.Printf("archive %s: %d file(s) [legacy-reconcile-all]\n", archDir, len(list.Files))
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
		fmt.Println("dry run: pass -execute with -legacy-reconcile-all to write missing files and drop orphan rows")
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

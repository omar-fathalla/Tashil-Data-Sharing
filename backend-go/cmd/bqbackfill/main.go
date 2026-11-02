// Command bqbackfill loads every file in the upload archive into the BigQuery sink tables.
//
// It parses the archive exactly like server startup does, then writes each sheet with the same
// idempotent DELETE+INSERT plans used by live uploads, so re-running it never duplicates rows.
//
// Usage (lists only, writes nothing):
//
//	TASHIL_ARCHIVE_DIR=/path/to/archive go run ./cmd/bqbackfill
//
// To write missing files and drop rows of deleted files (requires tashil-backend-sa roles):
//
//	TASHIL_ARCHIVE_DIR=... PROJECT_ID=... BIGQUERY_DATASET=... go run ./cmd/bqbackfill -execute
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
	execute := flag.Bool("execute", false, "actually write to BigQuery (default: list archive only)")
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

	list := p.ListArchivedFiles(context.Background(), "all", "", "", "", "all")
	fmt.Printf("archive %s: %d file(s)\n", archDir, len(list.Files))
	for _, f := range list.Files {
		fmt.Printf("  %-15s %-14s %-12s %s\n", f.FileType, f.TenantID, f.RetailChain, f.FileName)
	}

	// Compare every archived file with its rows in BigQuery (read-only), then with -execute write the
	// missing files (keyed by archive id, idempotent) and drop rows of deleted files. The server runs the
	// same reconcile on startup (BQ_ARCHIVE_SYNC), so this command is only needed for out-of-band runs.
	sinkCfg := bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset)
	sinkCfg.Enabled = true
	p.WithSink(bqsink.New(context.Background(), sinkCfg))
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
	}
}

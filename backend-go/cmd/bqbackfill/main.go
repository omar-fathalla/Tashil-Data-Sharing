// Command bqbackfill loads every file in the upload archive into the BigQuery sink tables.
//
// It parses the archive exactly like server startup does, then writes each sheet with the same
// idempotent DELETE+INSERT plans used by live uploads, so re-running it never duplicates rows.
//
// Usage (lists only, writes nothing):
//
//	TASHIL_ARCHIVE_DIR=/path/to/archive go run ./cmd/bqbackfill
//
// To actually write (requires credentials with the tashil-backend-sa roles):
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
	if !*execute {
		fmt.Println("dry run: pass -execute to load these into BigQuery")
		return
	}

	sinkCfg := bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset)
	sinkCfg.Enabled = true
	p.WithSink(bqsink.New(context.Background(), sinkCfg))
	_ = p.ClearTenantData(context.Background(), "all")
	if err := p.BackfillArchiveToSink(context.Background()); err != nil {
		log.Fatalf("backfill failed: %v", err)
	}
	fmt.Println("backfill finished; check the ingestion_log table for per-file status")
}

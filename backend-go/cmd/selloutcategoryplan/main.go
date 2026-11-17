// Command selloutcategoryplan is a READ-ONLY dry run for refreshing the Sell-Out category column.
//
// It re-parses the archived Sell-Out sheets BigQuery stores rows for (in memory, mock Firestore and
// Gemini, no sink attached), reads sell_out_facts through the same view the server loads, and prints
// before/after category totals plus the invariants (rows, quantity, net revenue unchanged). It has no
// write mode: BigQuery is only queried with SELECTs.
//
//	TASHIL_ARCHIVE_DIR=/path/to/archive PROJECT_ID=... BIGQUERY_DATASET=tashil_analytics \
//	  go run ./cmd/selloutcategoryplan -tenant=tenant-adeco \
//	  [-expected=/secure/excel_2026_totals.csv] [-mapping-out=/secure/category_mapping.csv]
//
// -expected and -mapping-out must point outside any git work tree (client data is never committed).
// See docs/SELLOUT_CATEGORY_REFRESH_PLAN.md.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/config"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func main() {
	tenant := flag.String("tenant", "tenant-adeco", "tenant id")
	expected := flag.String("expected", "", "optional CSV chain,category,scope(own|all),net_revenue from the client Excel (outside the repo)")
	mappingOut := flag.String("mapping-out", "", "optional path for the record_id/batch/old/new category CSV (outside the repo)")
	focus := flag.String("focus", "كلور,اطباق,صحون", "comma-separated category words for the detail tables (empty = all)")
	flag.Parse()

	for _, p := range []string{*expected, *mappingOut} {
		if err := refuseInsideGitTree(p); err != nil {
			log.Fatal(err)
		}
	}
	archDir := os.Getenv("TASHIL_ARCHIVE_DIR")
	if archDir == "" {
		log.Fatal("TASHIL_ARCHIVE_DIR is required")
	}
	var exp []ingestion.ExpectedCategoryTotal
	if *expected != "" {
		f, err := os.Open(*expected)
		if err != nil {
			log.Fatal(err)
		}
		exp, err = ingestion.ParseExpectedCategoryCSV(f)
		_ = f.Close()
		if err != nil {
			log.Fatalf("expected CSV: %v", err)
		}
	}

	ctx := context.Background()
	cfg := config.Load()
	sinkCfg := bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset)
	sinkCfg.Enabled = true
	bqs, ok := bqsink.New(ctx, sinkCfg).(*bqsink.BigQuerySink)
	if !ok {
		log.Fatal("BigQuery client unavailable")
	}
	stored, err := bqs.ReadSellOut(ctx, *tenant)
	if err != nil {
		log.Fatal(err)
	}
	counts, err := bqs.ArchiveRowCounts(ctx, *tenant)
	if err != nil {
		log.Fatal(err)
	}

	// In-memory only: mock Firestore/Gemini and no sink, so the replay cannot write anywhere durable.
	bqRepo := bigquery.NewClient(cfg.ProjectID, cfg.BigQueryDataset, true)
	fsRepo := firestore.NewClient(cfg.FirestoreDatabase, true)
	agent := gemini.NewAgent("", cfg.GeminiModel, true)
	p := ingestion.NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(archDir)
	// "all" only resets the in-memory mocks; a tenant-scoped clear would also delete that tenant's archive files.
	_ = p.ClearTenantData(ctx, "all")
	files := p.ReplaySellOutArchivesForCategoryPlan(ctx, *tenant, counts)
	fmt.Printf("re-parsed %d archive file(s):\n", len(files))
	for _, f := range files {
		fmt.Printf("  %-15s %-40s %s\n", f.FileType, f.ID, f.FileName)
	}
	replayed := bqRepo.SellOutFactsSnapshot(*tenant)

	plan := ingestion.PlanSellOutCategoryRefresh(*tenant, stored, replayed)
	var words []string
	for _, w := range strings.Split(*focus, ",") {
		if w = strings.TrimSpace(w); w != "" {
			words = append(words, w)
		}
	}
	fmt.Print(ingestion.FormatSellOutCategoryRefreshPlan(plan, words, ingestion.ReconcileExpected(plan, exp)))

	if *mappingOut != "" {
		f, err := os.Create(*mappingOut)
		if err != nil {
			log.Fatal(err)
		}
		if err := ingestion.WriteSellOutCategoryMappingCSV(f, plan); err != nil {
			log.Fatal(err)
		}
		if err := f.Close(); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("mapping CSV (%d row(s)) written to %s\n", len(plan.Changes), *mappingOut)
	}
	table := fmt.Sprintf("`%s.%s.%s`", cfg.ProjectID, cfg.BigQueryDataset, bqsink.TableSellOut)
	mapping := fmt.Sprintf("`%s.%s.sell_out_category_fix_YYYYMMDD`", cfg.ProjectID, cfg.BigQueryDataset)
	fmt.Printf("\nproposed UPDATE (NOT executed; owner approval required):\n%s\n", ingestion.SellOutCategoryUpdateSQL(table, mapping))
	fmt.Printf("rollback (NOT executed):\n%s\n", ingestion.SellOutCategoryRollbackSQL(table, mapping))
	if len(plan.Violations()) > 0 {
		os.Exit(1)
	}
}

// refuseInsideGitTree rejects paths inside a git work tree so client figures and mappings never land in a commit.
func refuseInsideGitTree(path string) error {
	if path == "" {
		return nil
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	for dir := filepath.Dir(abs); ; dir = filepath.Dir(dir) {
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return errors.New("refusing " + path + ": inside git work tree " + dir + " (client data must stay outside the repo)")
		}
		if parent := filepath.Dir(dir); parent == dir {
			return nil
		}
	}
}

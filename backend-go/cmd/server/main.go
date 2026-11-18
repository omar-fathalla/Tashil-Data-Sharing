package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/tashil/data-sharing/backend/internal/config"
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/handlers"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/arabicqa"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/competitorsuggest"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/dataquality"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
	"github.com/tashil/data-sharing/backend/internal/service/matcher"
	"github.com/tashil/data-sharing/backend/internal/service/monthlysummary"
	"github.com/tashil/data-sharing/backend/internal/service/sellinassist"
)

func main() {
	// Keep the Go heap well under the 2Gi Cloud Run limit so a full archive replay triggers
	// garbage collection instead of an out-of-memory kill. GOMEMLIMIT, when set, wins.
	if os.Getenv("GOMEMLIMIT") == "" {
		debug.SetMemoryLimit(1536 << 20)
	}
	cfg := config.Load()
	// Cloud Run sets K_SERVICE; ENVIRONMENT must be explicit so production never invents mock samples.
	if os.Getenv("K_SERVICE") != "" && strings.TrimSpace(os.Getenv("ENVIRONMENT")) == "" {
		log.Printf("[Tashil Cloud Run] WARNING: ENVIRONMENT is unset on Cloud Run — defaulting to %q; set ENVIRONMENT=production in the service config", cfg.Environment)
	}
	log.Printf("[Tashil Cloud Run] Initializing service on port %s (env: %s, mock: %v)", cfg.Port, cfg.Environment, cfg.UseMockServices)

	// 1. Initialize repositories
	bqRepo := bigquery.NewClient(cfg.ProjectID, cfg.BigQueryDataset, cfg.UseMockServices)
	fsRepo := firestore.NewClient(cfg.FirestoreDatabase, cfg.UseMockServices)

	// 2. Initialize Two-Tier Hybrid Gemini AI Ingestion Agent (Tier 1: Gemini 3.8 Flash, Tier 2: Gemini 4 Argon Medium / gemini-1.5-pro)
	geminiAgent := gemini.NewAgent(cfg.GeminiAPIKey, cfg.GeminiModel, cfg.UseMockServices).WithTier2Model(cfg.GeminiTier2Model)

	// 3. Initialize Ingestion Processor with persistent disk archive directory
	archDir := os.Getenv("TASHIL_ARCHIVE_DIR")
	if archDir == "" {
		archDir = "data/archive"
	}
	// Accepted AI column-mapping plans are stored next to the archive ("_" prefix = metadata, not a workbook),
	// so re-reading an archived file on any instance reuses them instead of calling Gemini again.
	geminiAgent.WithMappingPlanDir(filepath.Join(archDir, "_mapping_plans"))
	ingestProcessor := ingestion.NewProcessor(geminiAgent, bqRepo, fsRepo).WithArchiveDir(archDir)
	// Only one instance at a time runs the startup archive sync (Firestore lease with TTL).
	ingestProcessor.WithSyncLease(fsRepo)
	// Data-quality ("الأخطاء") checks: re-run on every Product Master upload and any source change.
	dqService := dataquality.NewService(fsRepo, bqRepo).WithMaster(bqRepo)
	ingestProcessor.WithProductMasterHook(func(tenantID, filename string, raw []byte) {
		dqService.SetProductMasterFile(tenantID, filename, raw)
		dqService.OnSourceChanged()
	})
	bqRepo.OnSourceChange(dqService.OnSourceChanged)
	// Sell-In customer registry: only exact or admin-approved names count; unknown names are quarantined.
	customerRegistry := customers.New(fsRepo)
	ingestProcessor.SetCustomerRegistry(customerRegistry)
	// Product/barcode matching review queue (Phase A4) — durable in Firestore; never invents barcodes.
	productMatchQueue := matcher.NewQueue(fsRepo)
	ingestProcessor.OnUploadIssues(func(ctx context.Context, tenantID, filename string, unknown []ingestion.UnknownBarcode) {
		items := make([]dataquality.UnknownItem, 0, len(unknown))
		queries := make([]matcher.Query, 0, len(unknown))
		for _, u := range unknown {
			items = append(items, dataquality.UnknownItem{ItemCode: u.ItemCode, Barcode: u.Barcode, ItemName: u.ItemName, Rows: u.Rows, Value: u.Value})
			queries = append(queries, matcher.Query{
				ItemCode: u.ItemCode, Barcode: u.Barcode, SKUName: u.ItemName,
				SourceFile: filename, Rows: u.Rows, Value: u.Value,
			})
		}
		if err := dqService.RecordSellInUnknownItems(ctx, tenantID, filename, items); err != nil {
			log.Printf("[data-quality] unknown items for %s: %v", filename, err)
		}
		cat := matcher.NewCatalog(bqRepo.GetProductMasterItems(tenantID))
		enqueued, err := productMatchQueue.EnqueueUnknowns(ctx, tenantID, filename, queries, cat)
		if err != nil {
			log.Printf("[product-match] tenant=%s file=%s enqueue failed: %v", tenantID, filename, err)
		} else if len(enqueued) > 0 {
			log.Printf("[product-match] tenant=%s file=%s enqueued %d review item(s)", tenantID, filename, len(enqueued))
		}
	})

	// Durable BigQuery persistence of uploaded sheets (off unless BIGQUERY_SINK_ENABLED=true)
	sink := bqsink.New(context.Background(), bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset))
	ingestProcessor.WithSink(sink)
	// Precomputed analytics layer: mirrored to agg_* tables when the BigQuery sink is enabled.
	if bqs, ok := sink.(*bqsink.BigQuerySink); ok {
		bqRepo.WithAggregatesWriter(bqs, "tenant-adeco")
		// BigQuery is the source of truth for Sell-In and Sell-Out: instances reload when data_versions changes.
		ingestProcessor.WithSellInStore(bqs, fsRepo)
		ingestProcessor.WithSellOutStore(bqs, fsRepo)
	}
	// Per-chain discount profiles (Firestore) feed CPFR cost.
	// Re-read them on analytics reads (TTL) so all Cloud Run instances converge within ~30s.
	bqRepo.WithChainDiscountSource(fsRepo, bigquery.DefaultChainDiscountSyncTTL)
	go func() {
		tenants, err := fsRepo.ListTenants(context.Background())
		if err != nil {
			log.Printf("[chain-discounts] list tenants failed: %v", err)
			return
		}
		for _, t := range tenants {
			if d, err := fsRepo.GetChainDiscountProfiles(context.Background(), t.ID); err == nil && len(d.Profiles) > 0 {
				bqRepo.SetChainDiscountProfiles(t.ID, d.Profiles)
				log.Printf("[chain-discounts] tenant=%s loaded %d profile(s)", t.ID, len(d.Profiles))
			}
		}
	}()

	// Inputs whose contents feed the replayed in-memory state; any change invalidates the startup snapshot.
	pmDir := os.Getenv("TASHIL_PRODUCT_MASTER_DIR")
	if pmDir == "" {
		pmDir = "data/product_master"
	}
	targetsDir := os.Getenv("TASHIL_TARGETS_DIR")
	if targetsDir == "" {
		targetsDir = "data/targets"
	}
	ingestProcessor.WithSnapshotInputs([]string{pmDir, targetsDir}, []string{
		"data/product_master/adeco_product_master_2026_08_01.xlsx",
		"/app/data/product_master/adeco_product_master_2026_08_01.xlsx",
		"data/cpfr_seed/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
		"/app/data/cpfr_seed/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
	})

	// When the snapshot is outdated (new parser version, or files deleted), serve it right away and
	// replay the archive into separate in-memory stores in the background, then swap the result in.
	ingestProcessor.WithBackgroundRebuild(func(ctx context.Context) ([]byte, []byte, error) {
		tbq := bigquery.NewClient(cfg.ProjectID, cfg.BigQueryDataset, true)
		tfs := firestore.NewClient(cfg.FirestoreDatabase, true)
		tp := ingestion.NewProcessor(geminiAgent, tbq, tfs).WithArchiveDir(archDir)
		tp.SetCustomerRegistry(customerRegistry)
		_ = tp.ClearTenantData(ctx, "all")
		if err := tp.ReplayArchivedFilesToDatabase(ctx); err != nil {
			return nil, nil, err
		}
		b, err := tbq.ExportSnapshot()
		if err != nil {
			return nil, nil, err
		}
		f, err := tfs.ExportSnapshot()
		return b, f, err
	}).OnRebuilt(func() {
		// Background rebuild swaps archive-replayed state (pre-merge spellings). Converge on
		// BigQuery, then re-apply recorded alias_of decisions before warming caches — otherwise
		// a successful startup remap is wiped and Returns shows both كفر الدوار 2 spellings again.
		ingestProcessor.SyncDurableFromStore(context.Background(), "tenant-adeco", true)
		ar := ingestProcessor.ApplyCustomerAliasAttributions(context.Background(), "tenant-adeco")
		if ar.Decisions > 0 || ar.Remapped > 0 || len(ar.Errors) > 0 {
			log.Printf("[customer-alias] on-rebuilt tenant=tenant-adeco decisions=%d remapped=%d sources=%v errs=%v", ar.Decisions, ar.Remapped, ar.Sources, ar.Errors)
		}
		bqRepo.WarmCommonTenantAnalytics(context.Background(), []string{"tenant-adeco"})
		dqService.OnSourceChanged()
	})

	// Data loading runs after the HTTP server starts listening (see step 7). Until it finishes,
	// data endpoints wait (up to dataReadyWait) instead of seeing a half-loaded dataset.
	dataReady := make(chan struct{})
	// archiveReady closes once the upload archive is restored (seconds after boot). The uploaded-files
	// list only needs the archive index + BigQuery row counts, so it must not wait minutes for the
	// durable sync / cache warm-up below (that held it past the web client's timeout after a deploy).
	archiveReady := make(chan struct{})
	var archiveReadyOnce sync.Once
	markArchiveReady := func() { archiveReadyOnce.Do(func() { close(archiveReady) }) }
	loadData := func() {
		defer close(dataReady)
		defer markArchiveReady()
		bootStart := time.Now()
		// Wipe all fake/synthetic seed data and restore ONLY real user-uploaded archived files
		_ = ingestProcessor.ClearTenantData(context.Background(), "all")
		mode, err := ingestProcessor.RestoreOrReplay(context.Background())
		if err != nil {
			log.Printf("[Tashil Cloud Run] Warning during archive load (%s): %v", mode, err)
		} else {
			log.Printf("[Tashil Cloud Run] Data ready via %s in %s. Only user-uploaded files are active.", mode, time.Since(bootStart).Round(time.Millisecond))
		}
		markArchiveReady()
		// Converge on the durable Sell-In / Sell-Out rows (BigQuery) before serving, then keep polling for changes.
		// Failures are logged per dataset and keep the archive-replayed data.
		durableTenants := []string{"tenant-adeco"}
		// Every archived upload must be stored in full in BigQuery: write files that are missing there and drop
		// rows of deleted files (idempotent; a no-op once in sync). BQ_ARCHIVE_SYNC=report logs only, =off skips.
		if mode := strings.ToLower(strings.TrimSpace(os.Getenv("BQ_ARCHIVE_SYNC"))); mode != "off" {
			for _, t := range durableTenants {
				rep, err := ingestProcessor.ReconcileArchivesToSink(context.Background(), t, mode != "report")
				if err != nil {
					log.Printf("WARN [archive-sync] tenant=%s: %v", t, err)
				}
				ingestion.LogArchiveSync(rep)
			}
		}
		ingestProcessor.SyncDurableFromStore(context.Background(), "tenant-adeco", true)
		// Re-apply recorded alias_of merges (e.g. Kafr El-Dawar decision saved before
		// attribution remapped). Idempotent; never invents a merge without a decision.
		// Must run again after OnRebuilt (background snapshot rebuild) — see that callback.
		for _, t := range durableTenants {
			ar := ingestProcessor.ApplyCustomerAliasAttributions(context.Background(), t)
			if ar.Decisions > 0 || ar.Remapped > 0 || len(ar.Errors) > 0 {
				log.Printf("[customer-alias] startup tenant=%s decisions=%d remapped=%d sources=%v errs=%v", t, ar.Decisions, ar.Remapped, ar.Sources, ar.Errors)
			}
		}
		// Fill kpiCache + sell-in-returns cache before serving so cold-start YTD
		// and year-scoped المرتجعات do not rebuild on the request path.
		bqRepo.WarmCommonTenantAnalytics(context.Background(), durableTenants)
		log.Printf("[Tashil Cloud Run] Startup data load finished in %s; /readyz now passes.", time.Since(bootStart).Round(time.Millisecond))
		go ingestProcessor.RunDurableSync(context.Background(), durableTenants, ingestion.DefaultDurableSyncInterval)
	}

	// 4. Initialize Handlers and Auth Middleware
	// Demo bypass tokens (demo-*-token) are OFF unless ALLOW_DEMO_TOKENS=true.
	allowDemoTokens, demoErr := config.DemoTokensAllowed(cfg.Environment, os.Getenv("ALLOW_DEMO_TOKENS"))
	if demoErr != nil {
		log.Fatal(demoErr)
	}
	log.Printf("[Tashil Cloud Run] Demo tokens allowed: %v", allowDemoTokens)
	authMiddleware := middleware.NewAuthMiddleware(cfg.JWTSecret, allowDemoTokens)
	uploadHandler := handlers.NewUploadHandler(ingestProcessor)
	// Phase C monthly narrative: deterministic facts from executive KPIs; optional Gemini
	// rewrite only when a live key is present and UseMockServices is false. Ungrounded AI falls back.
	analyticsHandler := handlers.NewAnalyticsHandler(bqRepo).WithMonthlySummary(monthlysummary.Options{
		Generator: monthlysummary.NewGeminiGenerator(cfg.GeminiAPIKey, "", nil),
		Model:     cfg.GeminiModel,
		UseMock:   cfg.UseMockServices || strings.TrimSpace(cfg.GeminiAPIKey) == "",
	})
	customerRegistryHandler := handlers.NewCustomerRegistryHandler(ingestProcessor, fsRepo)
	// Sell-Out explorer totals/SKU summaries/paging + Compare aggregates run in BigQuery when the
	// sink is live (RECORDS_SOURCE=memory forces the in-memory path).
	if bqs, ok := sink.(*bqsink.BigQuerySink); ok && os.Getenv("RECORDS_SOURCE") != "memory" {
		analyticsHandler.WithRecordsQuerier(bqs)
		analyticsHandler.WithCompetitiveMonthlyQuerier(bqs)
		analyticsHandler.WithTargetBreakdownQuerier(bqs)
		customerRegistryHandler.WithSellOutMonthsQuerier(bqs)
		// Sell-In totals and monthly groups too (SELLIN_SOURCE=memory forces the in-memory path).
		if os.Getenv("SELLIN_SOURCE") != "memory" {
			analyticsHandler.WithSellInTotalsQuerier(bqs)
		}
	}
	oosHandler := handlers.NewOOSHandler(fsRepo).WithBigQueryRepo(bqRepo)
	storeHandler := handlers.NewStoreHandler(fsRepo)
	authHandler := handlers.NewAuthHandler(fsRepo, authMiddleware)
	portalHandler := handlers.NewPortalHandler(fsRepo)
	adminHandler := handlers.NewAdminHandler(fsRepo).WithReferencedChains(func(tenantID string) []string {
		// Read-only: chains named by SELLIN_CUSTOMER_CHAIN_MAP rules and chains present in Sell-In memory.
		seen := map[string]bool{}
		var out []string
		add := func(c string) {
			if c = strings.ToLower(strings.TrimSpace(c)); c != "" && !seen[c] {
				seen[c] = true
				out = append(out, c)
			}
		}
		for _, r := range bigquery.ActiveSellInChainRules() {
			add(r[1])
		}
		if snap, ok := interface{}(bqRepo).(interface {
			SellInRecordsSnapshot(string) []domain.SellInRecord
		}); ok {
			for _, r := range snap.SellInRecordsSnapshot(tenantID) {
				add(bigquery.ResolveSellInChain(r.CustomerName, r.RetailerChain))
			}
		}
		return out
	})
	auditHandler := handlers.NewAuditHandler(fsRepo)
	tradeMarketingHandler := handlers.NewTradeMarketingHandler(fsRepo, fsRepo).WithSalesSource(bqRepo)
	competitorHandler := handlers.NewCompetitorHandler(fsRepo, fsRepo)
	competitorSuggestRanker := &competitorsuggest.GeminiRanker{
		APIKey:     cfg.GeminiAPIKey,
		Model:      cfg.GeminiModel,
		Tier2Model: cfg.GeminiTier2Model,
		UseMock:    cfg.UseMockServices || strings.TrimSpace(cfg.GeminiAPIKey) == "",
	}
	log.Printf("[competitor-suggest] gemini model=%s tier2_fallback=%s (404 model-not-found → tier2)",
		cfg.GeminiModel, cfg.GeminiTier2Model)
	competitorSuggestionsHandler := handlers.NewCompetitorSuggestionsHandler(fsRepo, fsRepo, bqRepo, competitorSuggestRanker)
	chainDiscountHandler := handlers.NewChainDiscountHandler(fsRepo, fsRepo, bqRepo).WithKnownChains(bqRepo)
	dataQualityHandler := handlers.NewDataQualityHandler(dqService, fsRepo)
	productMatchHandler := handlers.NewProductMatchHandler(productMatchQueue, bqRepo)
	// Sell-In Gemini assist (layout + SELLIN_CUSTOMER_CHAIN_MAP suggestions). Human approval only;
	// never mutates production data or env. Own package — no edits to hot Gemini ingest paths.
	// Decisions are RAM-only: lost on restart / not shared across instances.
	sellInAssistSvc := sellinassist.New(cfg.GeminiAPIKey, cfg.GeminiModel, cfg.GeminiAPIKey == "").WithTier2Model(cfg.GeminiTier2Model)
	sellInAssistHandler := handlers.NewSellInAssistHandler(sellInAssistSvc)
	uploadHandler.WithSellInAssist(sellInAssistSvc)
	// Phase C Arabic Q&A over BigQuery — read-only, tenant-scoped. Own package; no Excel/ingest hot paths.
	arabicQASvc := arabicqa.New(bqRepo, cfg.GeminiAPIKey, cfg.GeminiModel, cfg.GeminiAPIKey == "")
	arabicQAHandler := handlers.NewArabicQAHandler(arabicQASvc)

	// 5. Setup Mux Router (Go 1.22+ method + path patterns)
	mux := http.NewServeMux()

	// Public Health Probes — readiness fails closed if auth users did not load safely.
	// Prefer /livez and /api/v1/health: Cloud Run reserves /healthz for its own probes
	// (external GET /healthz returns Google's 404 and never reaches the container).
	health := handlers.HealthzWithAuth(fsRepo)
	mux.HandleFunc("GET /livez", health)
	mux.HandleFunc("GET /api/v1/health", health)
	// Startup probe: passes only once the data load finished (see docs/DEPLOY.md).
	mux.HandleFunc("GET /readyz", handlers.Readyz(fsRepo, dataReady))
	mux.HandleFunc("GET /healthz", health) // local/legacy; not reachable via Cloud Run ingress
	mux.HandleFunc("GET /api/v1/version", handlers.Version)
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"service":"Tashil Data Sharing Backend","status":"online","version":"1.0.0"}`)
	})

	// Public Auth & Portal Metadata Routes
	mux.HandleFunc("POST /api/v1/auth/login", authHandler.HandleLogin)
	mux.HandleFunc("POST /api/v1/auth/forgot-password", authHandler.HandleForgotPassword)
	mux.HandleFunc("POST /api/v1/auth/reset-password", authHandler.HandleResetPassword)
	mux.HandleFunc("POST /api/v1/auth/change-password", authHandler.HandleChangePassword)
	mux.HandleFunc("GET /api/v1/me", authHandler.HandleMe)
	mux.HandleFunc("GET /api/v1/portal/{slug}/meta", portalHandler.HandleGetPortalMeta)

	// Super Admin Tenant Provisioning & Management Routes
	mux.HandleFunc("GET /api/v1/admin/tenants", adminHandler.HandleListTenants)
	mux.HandleFunc("POST /api/v1/admin/tenants", adminHandler.HandleCreateTenant)
	mux.HandleFunc("PUT /api/v1/admin/tenants/{id}", adminHandler.HandleUpdateTenant)
	mux.HandleFunc("DELETE /api/v1/admin/tenants/{id}", adminHandler.HandleDeleteTenant)
	mux.HandleFunc("POST /api/v1/admin/tenants/{id}/reset-password", adminHandler.HandleResetTenantPassword)
	mux.HandleFunc("GET /api/v1/admin/chains", adminHandler.HandleListChains)
	mux.HandleFunc("POST /api/v1/admin/chains", adminHandler.HandleCreateChain)
	mux.HandleFunc("PUT /api/v1/admin/chains/{id}", adminHandler.HandleUpdateChain)
	mux.HandleFunc("DELETE /api/v1/admin/chains/{id}", adminHandler.HandleDeleteChain)

	// Protected Data, Analytics & Enterprise Audit Log Routes
	mux.HandleFunc("POST /api/v1/ingest/upload", uploadHandler.HandleUpload)
	mux.HandleFunc("POST /api/v1/ingest/precheck", uploadHandler.HandlePrecheck)
	mux.HandleFunc("POST /api/v1/ingest/commit", uploadHandler.HandleCommit)
	mux.HandleFunc("POST /api/v1/ingest/mapping-correction", uploadHandler.HandleSaveMappingCorrection)
	mux.HandleFunc("POST /api/v1/ingest/discard", uploadHandler.HandleDiscard)
	mux.HandleFunc("POST /api/v1/ingest/clear", uploadHandler.HandleClearData)
	mux.HandleFunc("DELETE /api/v1/ingest/clear", uploadHandler.HandleClearData)
	mux.HandleFunc("POST /api/v1/ingest/load-default-excel", uploadHandler.HandleLoadLocalExcel)
	mux.HandleFunc("POST /api/v1/ingest/load-sell-in-plan", uploadHandler.HandleLoadSellInPlan)
	mux.HandleFunc("GET /api/v1/ingest/archive", uploadHandler.HandleListArchive)
	mux.HandleFunc("DELETE /api/v1/ingest/archive/{id}", uploadHandler.HandleDeleteArchive)
	mux.HandleFunc("DELETE /api/v1/ingest/archive", uploadHandler.HandleDeleteArchive)
	mux.HandleFunc("GET /api/v1/ingest/archive/download", uploadHandler.HandleDownloadArchivedFile)
	mux.HandleFunc("GET /api/v1/ingest/archive/{id}/download", uploadHandler.HandleDownloadArchivedFile)
	mux.HandleFunc("GET /api/v1/product-master", analyticsHandler.HandleGetProductMaster)
	mux.HandleFunc("PUT /api/v1/product-master/item", analyticsHandler.HandleUpdateProductMasterItem)
	mux.HandleFunc("POST /api/v1/product-master/item", analyticsHandler.HandleUpdateProductMasterItem)
	mux.HandleFunc("POST /api/v1/product-master/upload", uploadHandler.HandleUploadProductMaster)
	mux.HandleFunc("GET /api/v1/product-master/chain-discounts", chainDiscountHandler.HandleGet)
	mux.HandleFunc("PUT /api/v1/product-master/chain-discounts", chainDiscountHandler.HandlePut)
	mux.HandleFunc("GET /api/v1/product-master/chains", chainDiscountHandler.HandleListChains)
	mux.HandleFunc("GET /api/v1/analytics/executive-summary", analyticsHandler.HandleExecutiveSummary)
	mux.HandleFunc("GET /api/v1/analytics/executive", analyticsHandler.HandleExecutiveSummary)
	mux.HandleFunc("GET /api/v1/analytics/records", analyticsHandler.HandleRecords)
	mux.HandleFunc("GET /api/v1/analytics/sell-in-records", analyticsHandler.HandleSellInRecords)
	mux.HandleFunc("GET /api/v1/analytics/sell-in-monthly", analyticsHandler.HandleSellInMonthly)
	mux.HandleFunc("GET /api/v1/analytics/competitive-monthly", analyticsHandler.HandleCompetitiveMonthly)
	mux.HandleFunc("GET /api/v1/analytics/sell-in-returns", analyticsHandler.HandleSellInReturns)
	mux.HandleFunc("GET /api/v1/analytics/targets", analyticsHandler.HandleTargets)
	mux.HandleFunc("POST /api/v1/analytics/targets", analyticsHandler.HandleTargets)
	mux.HandleFunc("DELETE /api/v1/analytics/targets", analyticsHandler.HandleTargets)
	mux.HandleFunc("POST /api/v1/analytics/targets/upload", analyticsHandler.HandleUploadTargetsFile)
	mux.HandleFunc("GET /api/v1/sellout/targets/{id}/breakdown", analyticsHandler.HandleTargetBreakdown)
	mux.HandleFunc("GET /api/v1/sellout/share-target/baseline", analyticsHandler.HandleShareTargetBaseline)
	mux.HandleFunc("POST /api/v1/sellout/share-target/preview", analyticsHandler.HandleShareTargetPreview)
	mux.HandleFunc("POST /api/v1/sellout/share-target", analyticsHandler.HandleShareTargetSave)
	mux.HandleFunc("GET /api/v1/analytics/store-matrix", analyticsHandler.HandleStoreMatrix)
	mux.HandleFunc("GET /api/v1/analytics/store-matrix/matched-months", analyticsHandler.HandleStoreMatrixMatchedMonths)
	mux.HandleFunc("GET /api/v1/analytics/pricing-compliance", analyticsHandler.HandlePricingCompliance)
	mux.HandleFunc("GET /api/v1/analytics/cpfr", analyticsHandler.HandleCPFRDashboard)
	mux.HandleFunc("GET /api/v1/analytics/aggregates", analyticsHandler.HandleGetAnalyticsAggregates)
	mux.HandleFunc("GET /api/v1/data-quality/issues", dataQualityHandler.HandleListIssues)
	mux.HandleFunc("PATCH /api/v1/data-quality/issues/{id}", dataQualityHandler.HandlePatchStatus)
	mux.HandleFunc("GET /api/v1/data-quality/summary", dataQualityHandler.HandleSummary)
	mux.HandleFunc("GET /api/v1/customers/registry", customerRegistryHandler.HandleList)
	mux.HandleFunc("POST /api/v1/customers/registry/approve", customerRegistryHandler.HandleApprove)
	mux.HandleFunc("POST /api/v1/customers/registry/reject", customerRegistryHandler.HandleReject)
	mux.HandleFunc("POST /api/v1/customers/registry/unmerge", customerRegistryHandler.HandleUnmerge)
	mux.HandleFunc("POST /api/v1/product-match", productMatchHandler.HandleMatch)
	mux.HandleFunc("POST /api/v1/product-match/enqueue", productMatchHandler.HandleEnqueue)
	mux.HandleFunc("GET /api/v1/product-match/review", productMatchHandler.HandleListReview)
	mux.HandleFunc("POST /api/v1/product-match/review/decide", productMatchHandler.HandleDecide)
	mux.HandleFunc("POST /api/v1/product-match/review/bulk-decide", productMatchHandler.HandleBulkDecide)
	mux.HandleFunc("GET /api/v1/product-match/metrics", productMatchHandler.HandleMetrics)
	mux.HandleFunc("GET /api/v1/sell-in/years", customerRegistryHandler.HandleYears)
	mux.HandleFunc("GET /api/v1/sell-out/months", customerRegistryHandler.HandleMonths)
	mux.HandleFunc("GET /api/v1/sell-in/assist/suggestions", sellInAssistHandler.HandleList)
	mux.HandleFunc("POST /api/v1/sell-in/assist/suggest-layout", sellInAssistHandler.HandleSuggestLayout)
	mux.HandleFunc("POST /api/v1/sell-in/assist/suggest-chains", sellInAssistHandler.HandleSuggestChains)
	mux.HandleFunc("POST /api/v1/sell-in/assist/approve", sellInAssistHandler.HandleApprove)
	mux.HandleFunc("POST /api/v1/sell-in/assist/reject", sellInAssistHandler.HandleReject)
	mux.HandleFunc("GET /api/v1/sell-in/assist/metrics", sellInAssistHandler.HandleMetrics)
	mux.HandleFunc("POST /api/v1/analytics/ask", arabicQAHandler.HandleAsk)
	mux.HandleFunc("GET /api/v1/analytics/ask/capabilities", arabicQAHandler.HandleCapabilities)
	mux.HandleFunc("GET /api/v1/analytics/oos-monitor", oosHandler.HandleOOSMonitor)
	mux.HandleFunc("GET /api/v1/stores", storeHandler.HandleGetStores)
	mux.HandleFunc("GET /api/v1/tenants", storeHandler.HandleGetTenants)
	mux.HandleFunc("GET /api/v1/batches", storeHandler.HandleGetBatches)
	mux.HandleFunc("GET /api/v1/audit/logs", auditHandler.HandleGetAuditLogs)
	mux.HandleFunc("POST /api/v1/audit/logs", auditHandler.HandleCreateAuditLog)
	mux.HandleFunc("GET /api/v1/trade-marketing/expenses", tradeMarketingHandler.HandleListExpenses)
	mux.HandleFunc("POST /api/v1/trade-marketing/expenses", tradeMarketingHandler.HandleCreateExpense)
	mux.HandleFunc("POST /api/v1/trade-marketing/expenses/upload", tradeMarketingHandler.HandleUploadExpenses)
	mux.HandleFunc("GET /api/v1/trade-marketing/roi", tradeMarketingHandler.HandleGetROI)
	mux.HandleFunc("PUT /api/v1/trade-marketing/expenses/{id}", tradeMarketingHandler.HandleUpdateExpense)
	mux.HandleFunc("DELETE /api/v1/trade-marketing/expenses/{id}", tradeMarketingHandler.HandleDeleteExpense)
	mux.HandleFunc("GET /api/v1/competitors/custom-skus", competitorHandler.HandleListCustomSkus)
	mux.HandleFunc("POST /api/v1/competitors/custom-skus", competitorHandler.HandleSaveCustomSku)
	mux.HandleFunc("DELETE /api/v1/competitors/custom-skus/{id}", competitorHandler.HandleDeleteCustomSku)
	mux.HandleFunc("GET /api/v1/competitors/mappings", competitorHandler.HandleListCompetitorMappings)
	mux.HandleFunc("POST /api/v1/competitors/mappings", competitorHandler.HandleSaveCompetitorMapping)
	mux.HandleFunc("DELETE /api/v1/competitors/mappings/{id}", competitorHandler.HandleDeleteCompetitorMapping)
	// AI competitor suggestions quarantine — owner approval required; pending never feeds Compare KPIs.
	mux.HandleFunc("GET /api/v1/competitors/suggestions", competitorSuggestionsHandler.HandleListSuggestions)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/run", competitorSuggestionsHandler.HandleRunSuggestions)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/sku", competitorSuggestionsHandler.HandleSuggestForSku)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/approve", competitorSuggestionsHandler.HandleApproveSuggestion)
	mux.HandleFunc("POST /api/v1/competitors/suggestions/reject", competitorSuggestionsHandler.HandleRejectSuggestion)

	// 6. Wrap Middleware Chain: CORS -> ingest rate limit -> Data-ready gate -> Auth -> Snapshot hook -> Router
	// Ingest rate limit sits inside CORS so 429s keep Access-Control-* headers for Flutter Web.
	// OPTIONS is answered by CORS (and also exempt inside the limiter) so preflights never 429.
	protectedHandler := authMiddleware.Handler(middleware.ETag(newAsyncJobs(archDir).wrap(snapshotOnMutation(mux, ingestProcessor))))
	gated := waitForData(protectedHandler, dataReady, archiveReady)
	corsHandler := middleware.CORS(middleware.NewIngestRateLimiter().Handler(gated))

	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      corsHandler,
		ReadTimeout:  180 * time.Second,
		WriteTimeout: 180 * time.Second,
		IdleTimeout:  180 * time.Second,
	}

	// 7. Start Server in Goroutine
	go func() {
		log.Printf("[Tashil Cloud Run] Server listening on http://0.0.0.0:%s", cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[Tashil Cloud Run] Server failed: %v", err)
		}
	}()

	go loadData()

	// 8. Graceful Shutdown on SIGINT/SIGTERM (Cloud Run lifecycle)
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("[Tashil Cloud Run] Gracefully shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("[Tashil Cloud Run] Server forced to shutdown: %v", err)
	}

	log.Println("[Tashil Cloud Run] Server stopped cleanly.")
}

const dataReadyWait = 170 * time.Second

// waitForData holds data requests until the startup load has finished. Health, version,
// auth and portal metadata do not depend on the replayed dataset and are served immediately.
// The uploaded-files list (GET /api/v1/ingest/archive) waits only for archiveReady.
func waitForData(next http.Handler, ready, archiveReady <-chan struct{}) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if !strings.HasPrefix(p, "/api/v1/") || strings.HasPrefix(p, "/api/v1/auth/") ||
			strings.HasPrefix(p, "/api/v1/portal/") || p == "/api/v1/version" ||
			p == "/api/v1/health" {
			next.ServeHTTP(w, r)
			return
		}
		gate := ready
		if r.Method == http.MethodGet && p == "/api/v1/ingest/archive" && archiveReady != nil {
			gate = archiveReady
		}
		select {
		case <-gate:
			next.ServeHTTP(w, r)
		case <-r.Context().Done():
			// Always write a JSON body so CORS middleware has a real response. A silent
			// return after Cloud Run / client cancel looks like a CORS failure in the
			// browser (no Access-Control-Allow-Origin on the empty/aborted transfer).
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Retry-After", "5")
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprint(w, `{"status":"cancelled","error":"Request cancelled while data was still loading"}`)
		case <-time.After(dataReadyWait):
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Retry-After", "10")
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprint(w, `{"status":"loading","error":"Data is still loading, please retry shortly"}`)
		}
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Flush() {
	if f, ok := s.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// snapshotOnMutation schedules a (debounced) startup snapshot after every successful data change.
func snapshotOnMutation(next http.Handler, p *ingestion.Processor) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !ingestion.IsSnapshotMutation(r.Method, r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		if rec.status >= 200 && rec.status < 300 {
			p.ScheduleSnapshot()
		}
	})
}

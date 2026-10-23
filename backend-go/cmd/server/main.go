package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tashil/data-sharing/backend/internal/config"
	"github.com/tashil/data-sharing/backend/internal/handlers"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func main() {
	cfg := config.Load()
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
	ingestProcessor := ingestion.NewProcessor(geminiAgent, bqRepo, fsRepo).WithArchiveDir(archDir)

	// Durable BigQuery persistence of uploaded sheets (off unless BIGQUERY_SINK_ENABLED=true)
	ingestProcessor.WithSink(bqsink.New(context.Background(), bqsink.ConfigFromEnv(cfg.ProjectID, cfg.BigQueryDataset)))

	// Wipe all fake/synthetic seed data on server startup and replay ONLY real user-uploaded archived files
	_ = ingestProcessor.ClearTenantData(context.Background(), "all")
	if err := ingestProcessor.ReplayArchivedFilesToDatabase(context.Background()); err != nil {
		log.Printf("[Tashil Cloud Run] Warning during archive replay: %v", err)
	} else {
		log.Printf("[Tashil Cloud Run] Archive replayed successfully. Only user-uploaded files are active.")
	}

	// 4. Initialize Handlers and Auth Middleware
	// Demo bypass tokens (demo-*-token) are OFF unless ALLOW_DEMO_TOKENS=true.
	allowDemoTokens := os.Getenv("ALLOW_DEMO_TOKENS") == "true"
	log.Printf("[Tashil Cloud Run] Demo tokens allowed: %v", allowDemoTokens)
	authMiddleware := middleware.NewAuthMiddleware(cfg.JWTSecret, allowDemoTokens)
	uploadHandler := handlers.NewUploadHandler(ingestProcessor)
	analyticsHandler := handlers.NewAnalyticsHandler(bqRepo)
	oosHandler := handlers.NewOOSHandler(fsRepo).WithBigQueryRepo(bqRepo)
	storeHandler := handlers.NewStoreHandler(fsRepo)
	authHandler := handlers.NewAuthHandler(fsRepo, authMiddleware)
	portalHandler := handlers.NewPortalHandler(fsRepo)
	adminHandler := handlers.NewAdminHandler(fsRepo)
	auditHandler := handlers.NewAuditHandler(fsRepo)
	tradeMarketingHandler := handlers.NewTradeMarketingHandler(fsRepo, fsRepo).WithSalesSource(bqRepo)
	competitorHandler := handlers.NewCompetitorHandler(fsRepo, fsRepo)

	// 5. Setup Mux Router (Go 1.22+ method + path patterns)
	mux := http.NewServeMux()

	// Public Health Probes
	mux.HandleFunc("GET /healthz", handlers.Healthz)
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"service":"Tashil Data Sharing Backend","status":"online","version":"1.0.0"}`)
	})

	// Public Auth & Portal Metadata Routes
	mux.HandleFunc("POST /api/v1/auth/login", authHandler.HandleLogin)
	mux.HandleFunc("POST /api/v1/auth/forgot-password", authHandler.HandleForgotPassword)
	mux.HandleFunc("POST /api/v1/auth/reset-password", authHandler.HandleResetPassword)
	mux.HandleFunc("POST /api/v1/auth/change-password", authHandler.HandleChangePassword)
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
	mux.HandleFunc("POST /api/v1/ingest/commit", uploadHandler.HandleCommit)
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
	mux.HandleFunc("GET /api/v1/analytics/executive-summary", analyticsHandler.HandleExecutiveSummary)
	mux.HandleFunc("GET /api/v1/analytics/executive", analyticsHandler.HandleExecutiveSummary)
	mux.HandleFunc("GET /api/v1/analytics/records", analyticsHandler.HandleRecords)
	mux.HandleFunc("GET /api/v1/analytics/sell-in-records", analyticsHandler.HandleSellInRecords)
	mux.HandleFunc("GET /api/v1/analytics/targets", analyticsHandler.HandleTargets)
	mux.HandleFunc("POST /api/v1/analytics/targets", analyticsHandler.HandleTargets)
	mux.HandleFunc("DELETE /api/v1/analytics/targets", analyticsHandler.HandleTargets)
	mux.HandleFunc("POST /api/v1/analytics/targets/upload", analyticsHandler.HandleUploadTargetsFile)
	mux.HandleFunc("GET /api/v1/analytics/store-matrix", analyticsHandler.HandleStoreMatrix)
	mux.HandleFunc("GET /api/v1/analytics/pricing-compliance", analyticsHandler.HandlePricingCompliance)
	mux.HandleFunc("GET /api/v1/analytics/cpfr", analyticsHandler.HandleCPFRDashboard)
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

	// 6. Wrap Middleware Chain: CORS -> Auth -> Router
	protectedHandler := authMiddleware.Handler(mux)
	corsHandler := middleware.CORS(protectedHandler)

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

package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)


const (
	DefaultAdcoWorkbookPath    = "/Users/fathalla/Downloads/40-Adco -2026.xlsx"
	DefaultGomlaWorkbookPath   = "/Users/fathalla/Downloads/Book1 (2).xlsx"
	DefaultAdcoSellInCleanPath = "/Users/fathalla/Downloads/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx"
	DefaultAdcoSellInRawPath   = "/Users/fathalla/Downloads/plan 10 aswak.xlsx"
)

// UploadHandler manages Excel/CSV uploads, data clearing, and orchestrates Gemini agent ingestion.
type UploadHandler struct {
	processor *ingestion.Processor
}

// NewUploadHandler creates a new UploadHandler.
func NewUploadHandler(processor *ingestion.Processor) *UploadHandler {
	return &UploadHandler{processor: processor}
}

// HandleClearData handles POST /api/v1/ingest/clear to wipe fake/previous data to zero.
func (h *UploadHandler) HandleClearData(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodDelete {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	if r.URL.Query().Get("scope") == "all" {
		tenantID = "all"
	}

	if err := h.processor.PurgeTenantData(r.Context(), tenantID); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "clear_failed",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "cleared",
		"tenant_id": tenantID,
		"message":   "تم مسح كافة بيانات الأصناف والفروع والمبيعات غير الحقيقية بنجاح",
	})
}

// HandleLoadSellInPlan handles POST /api/v1/ingest/load-sell-in-plan (and direct Sell-In file uploads from the CPFR screen).
func (h *UploadHandler) HandleLoadSellInPlan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	if qTenant := strings.TrimSpace(r.URL.Query().Get("tenant_id")); qTenant != "" {
		tenantID = qTenant
	}

	targetChain := strings.TrimSpace(r.URL.Query().Get("chain"))
	filename := strings.TrimSpace(r.URL.Query().Get("filename"))
	replaceArchiveID := strings.TrimSpace(r.URL.Query().Get("replace_archive_id"))
	periodDate := strings.TrimSpace(r.URL.Query().Get("period_date"))
	qYear := strings.TrimSpace(r.URL.Query().Get("year"))
	qMonth := strings.TrimSpace(r.URL.Query().Get("month"))
	var fileBytes []byte

	// Check if a Sell-In file (.xlsx or .csv) was uploaded directly from the CPFR or Sell-In screen
	contentType := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.Contains(contentType, "multipart/form-data") {
		if err := r.ParseMultipartForm(64 << 20); err == nil {
			if formChain := strings.TrimSpace(r.FormValue("chain")); formChain != "" {
				targetChain = formChain
			}
			if formTenant := strings.TrimSpace(r.FormValue("tenant_id")); formTenant != "" {
				tenantID = formTenant
			}
			if formReplace := strings.TrimSpace(r.FormValue("replace_archive_id")); formReplace != "" {
				replaceArchiveID = formReplace
			}
			if formPeriod := strings.TrimSpace(r.FormValue("period_date")); formPeriod != "" {
				periodDate = formPeriod
			}
			if formYear := strings.TrimSpace(r.FormValue("year")); formYear != "" {
				qYear = formYear
			}
			if formMonth := strings.TrimSpace(r.FormValue("month")); formMonth != "" {
				qMonth = formMonth
			}
			file, header, fErr := r.FormFile("file")
			if fErr == nil && file != nil {
				defer file.Close()
				fileBytes, _ = io.ReadAll(file)
				if header != nil && header.Filename != "" {
					filename = header.Filename
				}
			}
		}
	} else if r.ContentLength > 0 && filename != "" {
		fileBytes, _ = io.ReadAll(r.Body)
	}

	if len(fileBytes) == 0 {
		candidatePaths := []string{
			"data/cpfr_seed/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
			"/app/data/cpfr_seed/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
			DefaultAdcoSellInCleanPath,
			DefaultAdcoSellInRawPath,
		}
		for _, p := range candidatePaths {
			if b, readErr := os.ReadFile(p); readErr == nil && len(b) > 0 {
				fileBytes = b
				filename = filepath.Base(p)
				break
			}
		}
	}

	if len(fileBytes) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "file_not_found",
			"message": "يرجى اختيار ملف التوريد (Sell-In Excel أو CSV) لرفعه مباشرة من شاشة CPFR",
		})
		return
	}

	if filename == "" {
		filename = "CPFR_Sell_In_Plan.xlsx"
	}
	if targetChain == "" || targetChain == "all" {
		targetChain = "fathalla"
	}

	if replaceArchiveID != "" {
		_, _ = h.processor.DeleteArchivedFile(r.Context(), tenantID, replaceArchiveID)
	}

	if periodDate == "" && qYear != "" && qYear != "0" && qYear != "all" {
		m := "01"
		if qMonth != "" && qMonth != "0" && qMonth != "all" {
			if len(qMonth) == 1 {
				m = "0" + qMonth
			} else {
				m = qMonth
			}
		}
		periodDate = fmt.Sprintf("%s-%s-15", qYear, m)
	}

	ctx := r.Context()
	if periodDate != "" {
		ctx = gemini.WithRequestedPeriodDate(ctx, periodDate)
	}

	result, err := h.processor.ProcessSellInPlan(ctx, tenantID, filename, fileBytes, false, targetChain)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "sell_in_ingestion_failed",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

// HandleUploadProductMaster handles POST /api/v1/product-master/upload to ingest or update an Adeco Product Master & Price List workbook (.xlsx or .csv).
func (h *UploadHandler) HandleUploadProductMaster(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	if qTenant := strings.TrimSpace(r.URL.Query().Get("tenant_id")); qTenant != "" {
		tenantID = qTenant
	}

	filename := strings.TrimSpace(r.URL.Query().Get("filename"))
	replaceArchiveID := strings.TrimSpace(r.URL.Query().Get("replace_archive_id"))
	dryRun := r.URL.Query().Get("dry_run") == "true"
	var fileBytes []byte

	contentType := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.Contains(contentType, "multipart/form-data") {
		if err := r.ParseMultipartForm(64 << 20); err == nil {
			if formTenant := strings.TrimSpace(r.FormValue("tenant_id")); formTenant != "" {
				tenantID = formTenant
			}
			if formReplace := strings.TrimSpace(r.FormValue("replace_archive_id")); formReplace != "" {
				replaceArchiveID = formReplace
			}
			if strings.TrimSpace(r.FormValue("dry_run")) == "true" {
				dryRun = true
			}
			file, header, fErr := r.FormFile("file")
			if fErr == nil && file != nil {
				defer file.Close()
				fileBytes, _ = io.ReadAll(file)
				if header != nil && header.Filename != "" {
					filename = header.Filename
				}
			}
		}
	} else if r.ContentLength > 0 {
		fileBytes, _ = io.ReadAll(r.Body)
	}

	if len(fileBytes) == 0 {
		candidatePaths := []string{
			"data/product_master/adeco_product_master_2026_08_01.xlsx",
			"/app/data/product_master/adeco_product_master_2026_08_01.xlsx",
		}
		for _, p := range candidatePaths {
			if b, readErr := os.ReadFile(p); readErr == nil && len(b) > 0 {
				fileBytes = b
				filename = filepath.Base(p)
				break
			}
		}
	}

	if len(fileBytes) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "file_not_found",
			"message": "يرجى اختيار ملف كارتة الأصناف والأسعار (Product Master Excel أو CSV) لرفعه",
		})
		return
	}

	if filename == "" {
		filename = "adeco_product_master_2026_08_01.xlsx"
	}

	if replaceArchiveID != "" {
		_, _ = h.processor.DeleteArchivedFile(r.Context(), tenantID, replaceArchiveID)
	}

	result, err := h.processor.ProcessProductMaster(r.Context(), tenantID, filename, fileBytes, dryRun)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "product_master_ingestion_failed",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

// HandleLoadLocalExcel handles POST /api/v1/ingest/load-default-excel to ingest the local Adco (Fathalla + Gomla) Excel workbooks.
func (h *UploadHandler) HandleLoadLocalExcel(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	targetPath := DefaultAdcoWorkbookPath
	targetChain := r.URL.Query().Get("chain")
	var reqBody struct {
		Path  string `json:"path"`
		Chain string `json:"chain"`
	}
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&reqBody)
		if reqBody.Path != "" {
			targetPath = reqBody.Path
		}
		if reqBody.Chain != "" {
			targetChain = reqBody.Chain
		}
	}
	if reqBody.Path == "" && targetChain == "gomla" {
		targetPath = DefaultGomlaWorkbookPath
	} else if reqBody.Path == "" && (targetChain == "sellin" || targetChain == "fathalla_sellin") {
		h.HandleLoadSellInPlan(w, r)
		return
	}

	fileBytes, err := os.ReadFile(targetPath)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "file_not_found",
			"message": "تعذر قراءة ملف الإكسيل: " + err.Error(),
		})
		return
	}

	filename := filepath.Base(targetPath)
	result, err := h.processor.ProcessUpload(r.Context(), tenantID, filename, fileBytes, targetChain)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "ingestion_failed",
			"message": err.Error(),
		})
		return
	}

	// If default load was invoked without a specific path/chain, also ingest Gomla Market and Sell-In Plan workbooks if available
	if reqBody.Path == "" && targetChain == "" {
		if gomlaBytes, gErr := os.ReadFile(DefaultGomlaWorkbookPath); gErr == nil {
			_, _ = h.processor.ProcessUpload(r.Context(), tenantID, filepath.Base(DefaultGomlaWorkbookPath), gomlaBytes, "gomla")
		}
		if sellInBytes, sErr := os.ReadFile(DefaultAdcoSellInCleanPath); sErr == nil {
			_, _ = h.processor.ProcessSellInPlan(r.Context(), tenantID, filepath.Base(DefaultAdcoSellInCleanPath), sellInBytes, false, "fathalla")
		} else if rawSellInBytes, rErr := os.ReadFile(DefaultAdcoSellInRawPath); rErr == nil {
			_, _ = h.processor.ProcessSellInPlan(r.Context(), tenantID, filepath.Base(DefaultAdcoSellInRawPath), rawSellInBytes, false, "fathalla")
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

// HandleUpload handles POST /api/v1/ingest/upload.
func (h *UploadHandler) HandleUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	// Limit max file upload to 200MB
	_ = r.ParseMultipartForm(200 << 20)

	var filename string
	var fileBytes []byte

	file, header, err := r.FormFile("file")
	if err == nil {
		defer file.Close()
		filename = header.Filename
		fileBytes, err = io.ReadAll(file)
		if err != nil {
			http.Error(w, `{"error":"failed to read uploaded file"}`, http.StatusBadRequest)
			return
		}
	} else {
		// Fallback to raw request body if sent directly
		filename = r.URL.Query().Get("filename")
		if filename == "" {
			filename = "retail_sales_upload.csv"
		}
		fileBytes, err = io.ReadAll(r.Body)
		if err != nil || len(fileBytes) == 0 {
			http.Error(w, `{"error":"no file provided in multipart 'file' field or body"}`, http.StatusBadRequest)
			return
		}
	}

	// Extract optional tenant override (Super Admin or explicit header/query/form)
	tenantOverride := r.URL.Query().Get("tenant")
	if tenantOverride == "" {
		tenantOverride = r.Header.Get("X-Tenant-ID")
	}
	if tenantOverride == "" && r.MultipartForm != nil {
		vals := r.MultipartForm.Value["tenant"]
		if len(vals) > 0 {
			tenantOverride = vals[0]
		}
	}
	if tenantOverride != "" && (tenantID == "system" || tenantID == "all" || tenantID == "tenant-system" || tenantID == "tenant-all") {
		tenantID = tenantOverride
	}

	// Extract optional target retailer chain
	targetChain := r.URL.Query().Get("chain")
	if targetChain == "" {
		targetChain = r.Header.Get("X-Retail-Chain")
	}
	if targetChain == "" && r.MultipartForm != nil {
		vals := r.MultipartForm.Value["chain"]
		if len(vals) > 0 {
			targetChain = vals[0]
		}
	}

	// Extract optional dry_run flag
	dryRun := r.URL.Query().Get("dry_run") == "true"
	if !dryRun && r.MultipartForm != nil {
		vals := r.MultipartForm.Value["dry_run"]
		if len(vals) > 0 && vals[0] == "true" {
			dryRun = true
		}
	}

	// Extract optional ai_tier ("auto", "tier1", "tier2")
	aiTier := r.URL.Query().Get("ai_tier")
	if aiTier == "" {
		aiTier = r.Header.Get("X-AI-Tier")
	}
	if aiTier == "" && r.MultipartForm != nil {
		vals := r.MultipartForm.Value["ai_tier"]
		if len(vals) > 0 {
			aiTier = vals[0]
		}
	}

	// Extract optional period_date override (e.g., "2025-01-15" or "2026-02-15")
	periodDate := r.URL.Query().Get("period_date")
	if periodDate == "" {
		periodDate = r.Header.Get("X-Period-Date")
	}
	if periodDate == "" && r.MultipartForm != nil {
		vals := r.MultipartForm.Value["period_date"]
		if len(vals) > 0 {
			periodDate = vals[0]
		}
	}

	ctx := gemini.WithRequestedTier(r.Context(), aiTier)
	if periodDate != "" {
		ctx = gemini.WithRequestedPeriodDate(ctx, periodDate)
	}

	result, err := h.processor.ProcessUploadWithDryRun(ctx, tenantID, filename, fileBytes, dryRun, targetChain)

	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "ingestion_failed",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

// HandleCommit handles POST /api/v1/ingest/commit to persist a reviewed staged upload.
func (h *UploadHandler) HandleCommit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	var req struct {
		BatchID     string `json:"batch_id"`
		TargetChain string `json:"chain"`
		Tenant      string `json:"tenant"`
		PeriodDate  string `json:"period_date"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid json body"}`, http.StatusBadRequest)
		return
	}
	if req.BatchID == "" {
		http.Error(w, `{"error":"batch_id is required"}`, http.StatusBadRequest)
		return
	}
	if req.Tenant != "" && (tenantID == "system" || tenantID == "all" || tenantID == "tenant-system" || tenantID == "tenant-all") {
		tenantID = req.Tenant
	}

	commitCtx := r.Context()
	if req.PeriodDate != "" {
		commitCtx = gemini.WithRequestedPeriodDate(commitCtx, req.PeriodDate)
	}

	result, err := h.processor.CommitStagedUpload(commitCtx, tenantID, req.BatchID, req.TargetChain)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "commit_failed",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

// HandleDiscard handles POST /api/v1/ingest/discard to cancel a reviewed staged upload.
func (h *UploadHandler) HandleDiscard(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	var req struct {
		BatchID string `json:"batch_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid json body"}`, http.StatusBadRequest)
		return
	}

	_ = h.processor.DiscardStagedUpload(r.Context(), tenantID, req.BatchID)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status":  "discarded",
		"message": "تم تفريغ وإلغاء المعاينة بنجاح دون المساس بقاعدة البيانات",
	})
}

func (h *UploadHandler) ensureDefaultAdcoArchiveIfEmpty(tenantID string) {
	// Only seed if tenant archive has never been created or populated (0 files total).
	// NEVER resurrect files that the user intentionally deleted!
	slug := strings.TrimPrefix(strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-"), "tenant_")
	if slug != "" && slug != "adeco" && slug != "system" && slug != "all" {
		return
	}
	res := h.processor.ListArchivedFiles(nil, "tenant-adeco", "", "", "")
	if len(res.Files) > 0 {
		return
	}
	if excelBytes, err := os.ReadFile(DefaultAdcoWorkbookPath); err == nil && len(excelBytes) > 0 {
		h.processor.SaveArchivedFile(
			"tenant-adeco",
			"batch_seed_fathalla_2026",
			"40-Adco -2026.xlsx",
			excelBytes,
			"fathalla",
			"2026",
			"01-12",
			164733,
			35,
			9537094.70,
		)
	}
	if gomlaBytes, err := os.ReadFile(DefaultGomlaWorkbookPath); err == nil && len(gomlaBytes) > 0 {
		h.processor.SaveArchivedFile(
			"tenant-adeco",
			"batch_seed_gomla_2026",
			"Book1 (2).xlsx",
			gomlaBytes,
			"gomla",
			"2026",
			"01",
			5330,
			33,
			6573015.00,
		)
	}
}

// HandleListArchive handles GET /api/v1/ingest/archive to list archived uploaded Excel/CSV files by retail chain.
func (h *UploadHandler) HandleListArchive(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	tenantOverride := r.URL.Query().Get("tenant")
	if tenantOverride == "" {
		tenantOverride = r.Header.Get("X-Tenant-ID")
	}
	if tenantOverride != "" && (tenantID == "system" || tenantID == "all" || tenantID == "tenant-system" || tenantID == "tenant-all") {
		tenantID = tenantOverride
	}

	chainFilter := r.URL.Query().Get("chain")
	yearFilter := r.URL.Query().Get("year")
	fileType := strings.TrimSpace(r.URL.Query().Get("file_type"))
	if fileType == "" {
		fileType = strings.TrimSpace(r.URL.Query().Get("type"))
	}
	searchQuery := r.URL.Query().Get("q")
	if searchQuery == "" {
		searchQuery = r.URL.Query().Get("search")
	}

	archiveResp := h.processor.ListArchivedFiles(r.Context(), tenantID, chainFilter, yearFilter, searchQuery, fileType)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(archiveResp)
}

// HandleDownloadArchivedFile handles GET /api/v1/ingest/archive/{id}/download (and ?id=...) to stream back the original Excel/CSV file.
func (h *UploadHandler) HandleDownloadArchivedFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	tenantOverride := r.URL.Query().Get("tenant")
	if tenantOverride == "" {
		tenantOverride = r.Header.Get("X-Tenant-ID")
	}
	if tenantOverride != "" && (tenantID == "system" || tenantID == "all" || tenantID == "tenant-system" || tenantID == "tenant-all") {
		tenantID = tenantOverride
	}

	archiveID := r.PathValue("id")
	if archiveID == "" {
		archiveID = r.URL.Query().Get("id")
	}
	if archiveID == "" {
		// Fallback extraction from path /api/v1/ingest/archive/<id>/download
		trimmed := strings.TrimPrefix(r.URL.Path, "/api/v1/ingest/archive/")
		trimmed = strings.TrimSuffix(trimmed, "/download")
		trimmed = strings.Trim(trimmed, "/")
		if trimmed != "" && trimmed != "download" {
			archiveID = trimmed
		}
	}

	if archiveID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "missing_archive_id",
			"message": "معرف الملف المؤرشف مطلوب للتحميل",
		})
		return
	}

	entry, fileBytes, err := h.processor.GetArchivedFile(r.Context(), tenantID, archiveID)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "archive_file_not_found",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", entry.ContentType)
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", entry.FileName))
	w.Header().Set("Content-Length", strconv.Itoa(len(fileBytes)))
	w.Header().Set("Access-Control-Expose-Headers", "Content-Disposition, Content-Length, Content-Type")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(fileBytes)
}

// HandleDeleteArchive handles DELETE /api/v1/ingest/archive/{id} (or DELETE /api/v1/ingest/archive?id=...)
func (h *UploadHandler) HandleDeleteArchive(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	archiveID := r.PathValue("id")
	if archiveID == "" {
		archiveID = r.URL.Query().Get("id")
	}
	if archiveID == "" {
		trimmed := strings.TrimPrefix(r.URL.Path, "/api/v1/ingest/archive/")
		trimmed = strings.TrimSuffix(trimmed, "/delete")
		if trimmed != "" && trimmed != r.URL.Path && !strings.Contains(trimmed, "/") {
			archiveID = trimmed
		}
	}

	if archiveID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "missing_archive_id",
			"message": "archive file id is required in path or query param",
		})
		return
	}

	deleted, err := h.processor.DeleteArchivedFile(r.Context(), tenantID, archiveID)
	if err != nil {
		if fileName := strings.TrimSpace(r.URL.Query().Get("file_name")); fileName != "" && fileName != archiveID {
			deleted, err = h.processor.DeleteArchivedFile(r.Context(), tenantID, fileName)
		}
	}
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "delete_failed",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":     "deleted",
		"archive_id": archiveID,
		"file_name":  deleted.FileName,
		"chain":      deleted.RetailChain,
		"message":    fmt.Sprintf("تم حذف شيت '%s' ومسح سجلاته التحليلية بنجاح", deleted.FileName),
	})
}


package handlers

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// PaginatedSellInRecordsResponse formats the Sell-In Explorer table payload and summary metrics,
// including the full Tax & Discount Waterfall derived from the canonical Product Master.
type PaginatedSellInRecordsResponse struct {
	Records                      []domain.SellInRecord `json:"records"`
	TotalCount                   int                   `json:"total_count"`
	Limit                        int                   `json:"limit"`
	Offset                       int                   `json:"offset"`
	TotalValueEGP                float64               `json:"total_value_egp"`
	TotalCases                   float64               `json:"total_cases"`
	TotalUnitsPieces             int                   `json:"total_units_pieces"`
	TotalWeightTons              float64               `json:"total_weight_tons"`
	TotalExpectedEGP             float64               `json:"total_expected_egp"`
	TotalOfficialListExclVATEGP  float64               `json:"total_official_list_excl_vat_egp"`
	TotalOfficialListInclVATEGP  float64               `json:"total_official_list_incl_vat_egp"`
	TotalDiscountGrantedEGP      float64               `json:"total_discount_granted_egp"`
	EffectiveDiscountPct         float64               `json:"effective_discount_pct"`
	TotalNetExclVATEGP           float64               `json:"total_net_excl_vat_egp"`
	TotalVAT14EGP                float64               `json:"total_vat_14_egp"`
	TotalGrossInclVATEGP         float64               `json:"total_gross_incl_vat_egp"`
	MatchedCatalogSKUsCount      int                   `json:"matched_catalog_skus_count"`
	ByChain                      []SellInBreakdownItem `json:"by_chain,omitempty"`
	ByBrand                      []SellInBreakdownItem `json:"by_brand,omitempty"`
}

// HandleSellInRecords serves GET /api/v1/analytics/sell-in-records for the Sell-In Explorer page.
func (h *AnalyticsHandler) HandleSellInRecords(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 250
	}
	offset, _ := strconv.Atoi(q.Get("offset"))
	if offset < 0 {
		offset = 0
	}
	year, _ := strconv.Atoi(q.Get("year"))
	month, _ := strconv.Atoi(q.Get("month"))

	filter := bigquery.SellInRecordFilter{
		RetailerChain: q.Get("chain"),
		Year:          year,
		Month:         month,
		RegionCode:    q.Get("region"),
		Sector:        q.Get("sector"),
		Brand:         q.Get("brand"),
		SearchQuery:   q.Get("q"),
		Limit:         limit,
		Offset:        offset,
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			filter.RetailerChain = strings.TrimSpace(claims.AssignedChain)
		}
	}

	// Totals in BigQuery (latest batch per chain/month, Stage B math); only the page comes from memory.
	started := time.Now()
	if resp, ok := h.sellInRecordsFromBigQuery(r.Context(), tenantID, filter); ok {
		setRecordsSource(w, "bigquery")
		log.Printf("[sell-in-records] tenant=%s chain=%q year=%d month=%d source=bigquery rows=%d took=%s", tenantID, filter.RetailerChain, filter.Year, filter.Month, resp.TotalCount, time.Since(started).Round(time.Millisecond))
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(resp)
		return
	}
	setRecordsSource(w, "memory")
	defer func() {
		log.Printf("[sell-in-records] tenant=%s chain=%q year=%d month=%d source=memory took=%s", tenantID, filter.RetailerChain, filter.Year, filter.Month, time.Since(started).Round(time.Millisecond))
	}()

	// First fetch all matching for accurate summary KPIs
	allFilter := filter
	allFilter.Limit = 0
	allFilter.Offset = 0
	allRecords, total, err := h.bqRepo.GetSellInRecords(r.Context(), tenantID, allFilter)
	if err != nil {
		http.Error(w, `{"error":"failed to query sell-in records"}`, http.StatusInternalServerError)
		return
	}

	var pageRecords []domain.SellInRecord
	if offset < len(allRecords) {
		end := offset + limit
		if end > len(allRecords) {
			end = len(allRecords)
		}
		pageRecords = allRecords[offset:end]
	} else {
		pageRecords = []domain.SellInRecord{}
	}
	resp := buildSellInRecordsResponse(sellInTotalsFromRecords(allRecords), pageRecords, total, limit, offset)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// HandleTargets serves GET, POST, and DELETE /api/v1/analytics/targets for Sell-Out and Sell-In Target management.
func (h *AnalyticsHandler) HandleTargets(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	targetType := strings.ToLower(strings.TrimSpace(q.Get("target_type")))
	if targetType == "" {
		targetType = strings.ToLower(strings.TrimSpace(q.Get("type")))
	}
	if targetType != "sell_in" {
		targetType = "sell_out"
	}

	switch r.Method {
	case http.MethodGet:
		chain := q.Get("chain")
		year, _ := strconv.Atoi(q.Get("year"))
		summary, err := h.bqRepo.GetTargetsSummary(r.Context(), tenantID, targetType, chain, year)
		if err != nil {
			http.Error(w, `{"error":"failed to get targets"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(summary)

	case http.MethodPost, http.MethodPut:
		var raw map[string]interface{}
		bodyBytes, _ := io.ReadAll(r.Body)
		if err := json.Unmarshal(bodyBytes, &raw); err != nil {
			http.Error(w, `{"error":"invalid JSON payload"}`, http.StatusBadRequest)
			return
		}

		// Support either batch {"targets": [...]} or single TargetRecord JSON
		if listRaw, hasBatch := raw["targets"]; hasBatch {
			b, _ := json.Marshal(listRaw)
			var list []domain.TargetRecord
			if err := json.Unmarshal(b, &list); err == nil {
				for _, item := range list {
					if item.TargetType == "" {
						item.TargetType = targetType
					}
					_, _ = h.bqRepo.UpsertTarget(r.Context(), tenantID, item)
				}
			}
		} else {
			var single domain.TargetRecord
			if err := json.Unmarshal(bodyBytes, &single); err == nil {
				if single.TargetType == "" {
					single.TargetType = targetType
				}
				if single.TargetType != "" {
					targetType = single.TargetType
				}
				_, _ = h.bqRepo.UpsertTarget(r.Context(), tenantID, single)
			}
		}

		summary, _ := h.bqRepo.GetTargetsSummary(r.Context(), tenantID, targetType, q.Get("chain"), 0)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(summary)

	case http.MethodDelete:
		id := strings.TrimSpace(q.Get("id"))
		if id == "" {
			http.Error(w, `{"error":"missing target id"}`, http.StatusBadRequest)
			return
		}
		if err := h.bqRepo.DeleteTarget(r.Context(), tenantID, id); err != nil {
			http.Error(w, `{"error":"target not found"}`, http.StatusNotFound)
			return
		}
		summary, _ := h.bqRepo.GetTargetsSummary(r.Context(), tenantID, targetType, q.Get("chain"), 0)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(summary)

	default:
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

// HandleUploadTargetsFile serves POST /api/v1/analytics/targets/upload to import targets from an Excel (.xlsx) or CSV file.
func (h *AnalyticsHandler) HandleUploadTargetsFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	targetType := strings.ToLower(strings.TrimSpace(q.Get("target_type")))
	if targetType != "sell_in" {
		targetType = "sell_out"
	}
	defaultChain := strings.ToLower(strings.TrimSpace(q.Get("chain")))
	defaultYear, _ := strconv.Atoi(q.Get("year"))
	filename := strings.TrimSpace(q.Get("filename"))

	var fileBytes []byte
	contentType := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.Contains(contentType, "multipart/form-data") {
		if err := r.ParseMultipartForm(32 << 20); err == nil {
			if ft := strings.TrimSpace(r.FormValue("target_type")); ft != "" {
				targetType = strings.ToLower(ft)
			}
			if fc := strings.TrimSpace(r.FormValue("chain")); fc != "" {
				defaultChain = strings.ToLower(fc)
			}
			if fy, err := strconv.Atoi(strings.TrimSpace(r.FormValue("year"))); err == nil && fy > 0 {
				defaultYear = fy
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
	} else {
		fileBytes, _ = io.ReadAll(r.Body)
	}

	if len(fileBytes) == 0 {
		http.Error(w, `{"error":"empty target file"}`, http.StatusBadRequest)
		return
	}

	rows := parseUploadedTargetRows(filename, fileBytes)
	if len(rows) < 2 {
		http.Error(w, `{"error":"no valid rows found in target file"}`, http.StatusUnprocessableEntity)
		return
	}

	importedCount := importTargetRowsToRepo(r, h.bqRepo, tenantID, targetType, defaultChain, defaultYear, rows)
	summary, _ := h.bqRepo.GetTargetsSummary(r.Context(), tenantID, targetType, "", 0)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":        "imported",
		"rows_imported": importedCount,
		"summary":       summary,
	})
}

func parseUploadedTargetRows(_ string, fileBytes []byte) [][]string {
	rows, _ := gemini.ExtractXLSXOrCSVRows(fileBytes)
	return rows
}

func importTargetRowsToRepo(
	r *http.Request,
	bqRepo bigquery.Repository,
	tenantID, targetType, defaultChain string,
	defaultYear int,
	rows [][]string,
) int {
	headerIdx := -1
	chainCol, yearCol, monthCol, branchCol, catCol, revCol, unitsCol, notesCol := -1, -1, -1, -1, -1, -1, -1, -1

	for i := 0; i < len(rows) && i < 10; i++ {
		row := rows[i]
		cCol, yCol, mCol, bCol, kCol, rCol, uCol, nCol := -1, -1, -1, -1, -1, -1, -1, -1
		for colIdx, cell := range row {
			h := strings.ToLower(strings.TrimSpace(cell))
			if h == "" {
				continue
			}
			switch {
			case cCol == -1 && (strings.Contains(h, "chain") || strings.Contains(h, "سلسلة") || strings.Contains(h, "السلسلة") || strings.Contains(h, "عميل")):
				cCol = colIdx
			case yCol == -1 && (strings.Contains(h, "year") || strings.Contains(h, "سنة") || strings.Contains(h, "السنة") || strings.Contains(h, "عام")):
				yCol = colIdx
			case mCol == -1 && (strings.Contains(h, "month") || strings.Contains(h, "شهر") || strings.Contains(h, "الشهر")):
				mCol = colIdx
			case bCol == -1 && (strings.Contains(h, "branch") || strings.Contains(h, "store") || strings.Contains(h, "فرع") || strings.Contains(h, "الفرع")):
				bCol = colIdx
			case kCol == -1 && (strings.Contains(h, "category") || strings.Contains(h, "brand") || strings.Contains(h, "فئة") || strings.Contains(h, "الفئة") || strings.Contains(h, "ماركة") || strings.Contains(h, "علامة")):
				kCol = colIdx
			case rCol == -1 && (strings.Contains(h, "value") || strings.Contains(h, "revenue") || strings.Contains(h, "egp") || strings.Contains(h, "target_value") || strings.Contains(h, "قيمة") || strings.Contains(h, "القيمة") || strings.Contains(h, "جنيه") || strings.Contains(h, "مبيعات مستهدفة") || strings.Contains(h, "المستهدف بالجنيه")):
				rCol = colIdx
			case uCol == -1 && (strings.Contains(h, "unit") || strings.Contains(h, "case") || strings.Contains(h, "qty") || strings.Contains(h, "quantity") || strings.Contains(h, "كمية") || strings.Contains(h, "الكمية") || strings.Contains(h, "وحدات") || strings.Contains(h, "كرتونة")):
				uCol = colIdx
			case nCol == -1 && (strings.Contains(h, "note") || strings.Contains(h, "ملاحظات") || strings.Contains(h, "بيان")):
				nCol = colIdx
			}
		}
		if rCol != -1 || uCol != -1 {
			headerIdx = i
			chainCol, yearCol, monthCol, branchCol, catCol, revCol, unitsCol, notesCol = cCol, yCol, mCol, bCol, kCol, rCol, uCol, nCol
			break
		}
	}

	if headerIdx == -1 {
		headerIdx = 0
		// Default positional fallback: Chain(0), Year(1), Month(2), Branch(3), Category(4), TargetRevenueEGP(5), TargetUnits(6), Notes(7)
		chainCol, yearCol, monthCol, branchCol, catCol, revCol, unitsCol, notesCol = 0, 1, 2, 3, 4, 5, 6, 7
	}

	if defaultYear <= 0 {
		defaultYear = 2025
	}
	if defaultChain == "" || defaultChain == "الكل" {
		defaultChain = "fathalla"
	}

	imported := 0
	for i := headerIdx + 1; i < len(rows); i++ {
		row := rows[i]
		if len(row) == 0 {
			continue
		}
		firstCell := strings.TrimSpace(row[0])
		if strings.Contains(firstCell, "سطر إرشادي") || strings.HasPrefix(firstCell, "#") {
			continue
		}

		revVal := parseTargetNumber(getTargetCell(row, revCol))
		unitsVal := parseTargetNumber(getTargetCell(row, unitsCol))
		if revVal <= 0 && unitsVal <= 0 {
			continue
		}

		ch := normalizeChainCodeFromText(getTargetCell(row, chainCol), defaultChain)
		yr := parseTargetYear(getTargetCell(row, yearCol), defaultYear)
		mo := parseTargetMonth(getTargetCell(row, monthCol))
		br := strings.TrimSpace(getTargetCell(row, branchCol))
		cat := strings.TrimSpace(getTargetCell(row, catCol))
		notes := strings.TrimSpace(getTargetCell(row, notesCol))

		_, err := bqRepo.UpsertTarget(r.Context(), tenantID, domain.TargetRecord{
			TargetType:       targetType,
			RetailerChain:    ch,
			Year:             yr,
			Month:            mo,
			BranchName:       br,
			Category:         cat,
			TargetRevenueEGP: revVal,
			TargetUnits:      unitsVal,
			Notes:            notes,
		})
		if err == nil {
			imported++
		}
	}
	return imported
}

func getTargetCell(row []string, idx int) string {
	if idx < 0 || idx >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[idx])
}

func parseTargetNumber(s string) float64 {
	clean := strings.NewReplacer(",", "", " ", "", "ج.م", "", "EGP", "", "egp", "").Replace(strings.TrimSpace(s))
	val, _ := strconv.ParseFloat(clean, 64)
	return val
}

func parseTargetYear(s string, fallback int) int {
	clean := strings.TrimSpace(s)
	if yr, err := strconv.Atoi(clean); err == nil {
		if yr >= 20 && yr <= 35 {
			return 2000 + yr
		}
		if yr >= 2020 && yr <= 2035 {
			return yr
		}
	}
	for yr := 2020; yr <= 2035; yr++ {
		if strings.Contains(clean, strconv.Itoa(yr)) {
			return yr
		}
	}
	return fallback
}

func parseTargetMonth(s string) int {
	clean := strings.ToLower(strings.TrimSpace(s))
	if clean == "" || clean == "0" || clean == "all" || strings.Contains(clean, "كل") || strings.Contains(clean, "سنوي") {
		return 0
	}
	if m, err := strconv.Atoi(clean); err == nil && m >= 1 && m <= 12 {
		return m
	}
	monthTokens := []struct {
		m      int
		tokens []string
	}{
		{1, []string{"يناير", "jan"}},
		{2, []string{"فبراير", "feb"}},
		{3, []string{"مارس", "mar"}},
		{4, []string{"أبريل", "ابريل", "apr"}},
		{5, []string{"مايو", "may"}},
		{6, []string{"يونيو", "يونية", "jun"}},
		{7, []string{"يوليو", "يولية", "jul"}},
		{8, []string{"أغسطس", "اغسطس", "aug"}},
		{9, []string{"سبتمبر", "sep"}},
		{10, []string{"أكتوبر", "اكتوبر", "oct"}},
		{11, []string{"نوفمبر", "nov"}},
		{12, []string{"ديسمبر", "dec"}},
	}
	for _, entry := range monthTokens {
		for _, tok := range entry.tokens {
			if strings.Contains(clean, tok) {
				return entry.m
			}
		}
	}
	return 0
}

func normalizeChainCodeFromText(s, fallback string) string {
	clean := strings.ToLower(strings.TrimSpace(s))
	if clean == "" {
		return fallback
	}
	switch {
	case clean == "all" || strings.Contains(clean, "كل السلاسل") || clean == "الكل":
		return "all"
	case strings.Contains(clean, "فتح الله") || strings.Contains(clean, "fathalla"):
		return "fathalla"
	case strings.Contains(clean, "بيت الجملة") || strings.Contains(clean, "بيت الجمله") || strings.Contains(clean, "beet"):
		return "beet-elgomla"
	case strings.Contains(clean, "جملة ماركت") || strings.Contains(clean, "جمله ماركت") || clean == "gomla":
		return "gomla"
	case strings.Contains(clean, "الوكالة") || strings.Contains(clean, "الوكاله") || strings.Contains(clean, "wakala"):
		return "chain-1080314"
	case strings.Contains(clean, "كارفور") || strings.Contains(clean, "carrefour"):
		return "carrefour"
	case strings.Contains(clean, "سبينيس") || strings.Contains(clean, "سبينس") || strings.Contains(clean, "spinneys"):
		return "spinneys"
	case strings.Contains(clean, "مترو") || strings.Contains(clean, "metro"):
		return "metro"
	case strings.Contains(clean, "سعودي") || strings.Contains(clean, "seoudi"):
		return "seoudi"
	case strings.Contains(clean, "كازيون") || strings.Contains(clean, "kazyon"):
		return "kazyon"
	default:
		return clean
	}
}

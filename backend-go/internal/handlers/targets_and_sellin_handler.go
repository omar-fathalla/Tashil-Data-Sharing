package handlers

import (
	"context"
	"encoding/json"
	"errors"
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
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// PaginatedSellInRecordsResponse formats the Sell-In Explorer table payload and summary metrics,
// including the full Tax & Discount Waterfall derived from the canonical Product Master.
type PaginatedSellInRecordsResponse struct {
	Records                     []domain.SellInRecord `json:"records"`
	TotalCount                  int                   `json:"total_count"`
	Limit                       int                   `json:"limit"`
	Offset                      int                   `json:"offset"`
	TotalValueEGP               float64               `json:"total_value_egp"`
	TotalCases                  float64               `json:"total_cases"`
	TotalUnitsPieces            int                   `json:"total_units_pieces"`
	TotalWeightTons             float64               `json:"total_weight_tons"`
	TotalExpectedEGP            float64               `json:"total_expected_egp"`
	TotalOfficialListExclVATEGP float64               `json:"total_official_list_excl_vat_egp"`
	TotalOfficialListInclVATEGP float64               `json:"total_official_list_incl_vat_egp"`
	TotalDiscountGrantedEGP     float64               `json:"total_discount_granted_egp"`
	EffectiveDiscountPct        float64               `json:"effective_discount_pct"`
	// «من السعر الرسمي إلى الفاتورة» card, exact to the piastre:
	//   official − invoice − extra = expected net (chain terms: saved, else invoice 10% / extra 0%)
	//   expected − execution difference + unpriced net = TotalNetExclVATEGP (Excel Net V)
	//   net + VAT = TotalGrossInclVATEGP
	TotalInvoiceDiscountEGP    float64 `json:"total_invoice_discount_egp"`
	TotalExtraChainDiscountEGP float64 `json:"total_extra_chain_discount_egp"`
	TotalExpectedNetEGP        float64 `json:"total_expected_net_egp"`
	// Expected net − file net of the priced rows (promotions / price deviation); negative when above it.
	TotalExecutionDiffEGP float64 `json:"total_execution_difference_egp"`
	// Deprecated alias of TotalExecutionDiffEGP for older web builds.
	TotalOtherDifferenceEGP float64 `json:"total_other_difference_egp"`
	// File net of rows with no official price (no Product Master match).
	TotalUnpricedNetEGP float64 `json:"total_unpriced_net_egp"`
	// Invoice / extra discount % for the badges: one chain = its saved terms exactly; several chains =
	// official-weighted averages (TermsAveraged), with ChainTerms as the breakdown.
	InvoiceDiscountPct      float64                `json:"invoice_discount_pct"`
	ExtraDiscountPct        float64                `json:"extra_discount_pct"`
	TermsAveraged           bool                   `json:"terms_averaged"`
	ChainTerms              []SellInChainTermsItem `json:"chain_terms,omitempty"`
	VATRatePct              float64                `json:"vat_rate_pct"`
	TotalNetExclVATEGP      float64                `json:"total_net_excl_vat_egp"`
	TotalVAT14EGP           float64                `json:"total_vat_14_egp"`
	TotalGrossInclVATEGP    float64                `json:"total_gross_incl_vat_egp"`
	MatchedCatalogSKUsCount int                    `json:"matched_catalog_skus_count"`
	ByChain                 []SellInBreakdownItem  `json:"by_chain,omitempty"`
	ByBrand                 []SellInBreakdownItem  `json:"by_brand,omitempty"`
}

// maxSellInRecordsLimit caps one sell-in-records page; larger requests are clamped (the effective
// value is echoed in the response "limit") so a client paging by it still reaches total_count.
const maxSellInRecordsLimit = 1000

// HandleSellInRecords serves GET /api/v1/analytics/sell-in-records for the Sell-In Explorer page.
func (h *AnalyticsHandler) HandleSellInRecords(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 {
		limit = 250
	}
	if limit > maxSellInRecordsLimit {
		limit = maxSellInRecordsLimit
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
	totals, chainGroups := sellInTotalsAndChainsFromRecords(allRecords)
	resp := buildSellInRecordsResponse(totals, pageRecords, total, limit, offset)
	applySellInChainTerms(&resp, chainGroups, h.sellInChainProfiles(r.Context(), tenantID))

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// sellInTargetsDerivedMessage explains why Sell-In targets cannot be written.
const sellInTargetsDerivedMessage = "Sell-In targets are derived automatically from Sell-Out targets; create, upload or delete the Sell-Out target instead"

// writeSellInTargetsDerived rejects a write to Sell-In targets with a clear 4xx (they are read-only, computed on read).
func writeSellInTargetsDerived(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadRequest)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"error":     sellInTargetsDerivedMessage,
		"code":      "sell_in_targets_are_derived",
		"error_ar":  "مستهدفات Sell-In تُحسب تلقائياً من مستهدف Sell-Out ولا يمكن إضافتها أو رفعها أو حذفها. عدّل مستهدف Sell-Out بدلاً من ذلك.",
		"hint_path": "target_type=sell_out",
	})
}

// requestedSellInBrands reads the multi-select brand filter: repeated ?brand= and/or comma-separated ?brands=.
func requestedSellInBrands(q map[string][]string) []string {
	var out []string
	seen := map[string]bool{}
	add := func(v string) {
		v = strings.TrimSpace(v)
		if v == "" || seen[v] {
			return
		}
		seen[v] = true
		out = append(out, v)
	}
	for _, v := range q["brand"] {
		add(v)
	}
	for _, v := range q["brands"] {
		for _, part := range strings.Split(v, ",") {
			add(part)
		}
	}
	return out
}

// derivedBreakdownFunc feeds the derived Sell-In targets with the BigQuery Sell-Out allocation when configured.
func (h *AnalyticsHandler) derivedBreakdownFunc(tenantID string) bigquery.DerivedBreakdownFunc {
	if h.targetBreakdown == nil {
		return nil
	}
	return func(ctx context.Context, t domain.TargetRecord) (domain.TargetBreakdownResponse, bool) {
		c, cancel := context.WithTimeout(ctx, targetBreakdownBQTimeout)
		defer cancel()
		chain := targetalloc.ChainFilter(t.RetailerChain)
		resp, found, err := targetalloc.ComputeFiltered(c, h.targetBreakdown.TargetBreakdownSource(tenantID, chain), t, "bigquery", targetalloc.Filters{})
		if err != nil || !found {
			return domain.TargetBreakdownResponse{}, false
		}
		return resp, true
	}
}

// HandleTargets serves GET, POST, and DELETE /api/v1/analytics/targets.
// Sell-Out targets are managed here; Sell-In targets are derived on read (GET) and read-only (POST/PUT/DELETE are rejected).
func (h *AnalyticsHandler) HandleTargets(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		if _, ok := requireWriteRole(w, r, ingestWriteRoles); !ok {
			return
		}
	}
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

	if r.Method != http.MethodGet && r.Method != http.MethodHead && targetType == "sell_in" {
		writeSellInTargetsDerived(w)
		return
	}

	switch r.Method {
	case http.MethodGet:
		chain := q.Get("chain")
		year, _ := strconv.Atoi(q.Get("year"))
		var summary *domain.TargetsSummaryResponse
		var err error
		if targetType == "sell_in" {
			summary, err = h.bqRepo.GetDerivedSellInTargetsSummary(r.Context(), tenantID, bigquery.DerivedSellInOptions{
				Chain:     chain,
				Year:      year,
				Brands:    requestedSellInBrands(q),
				Breakdown: h.derivedBreakdownFunc(tenantID),
			})
		} else {
			summary, err = h.bqRepo.GetTargetsSummary(r.Context(), tenantID, targetType, chain, year)
		}
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
					if strings.EqualFold(strings.TrimSpace(item.TargetType), "sell_in") {
						writeSellInTargetsDerived(w)
						return
					}
				}
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
				if strings.EqualFold(strings.TrimSpace(single.TargetType), "sell_in") {
					writeSellInTargetsDerived(w)
					return
				}
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
		if bigquery.IsDerivedSellInTargetID(id) {
			writeSellInTargetsDerived(w)
			return
		}
		if existing, ok := h.bqRepo.GetTarget(r.Context(), tenantID, id); ok && existing != nil && strings.EqualFold(existing.TargetType, "sell_in") {
			writeSellInTargetsDerived(w)
			return
		}
		if err := h.bqRepo.DeleteTarget(r.Context(), tenantID, id); err != nil {
			if errors.Is(err, bigquery.ErrSellInTargetsDerived) {
				writeSellInTargetsDerived(w)
				return
			}
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
	if _, ok := requireWriteRole(w, r, ingestWriteRoles); !ok {
		return
	}
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
	if targetType == "sell_in" {
		writeSellInTargetsDerived(w)
		return
	}
	targetType = "sell_out"
	defaultChain := strings.ToLower(strings.TrimSpace(q.Get("chain")))
	defaultYear, _ := strconv.Atoi(q.Get("year"))
	filename := strings.TrimSpace(q.Get("filename"))

	var fileBytes []byte
	contentType := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.Contains(contentType, "multipart/form-data") {
		if err := r.ParseMultipartForm(32 << 20); err == nil {
			if ft := strings.ToLower(strings.TrimSpace(r.FormValue("target_type"))); ft == "sell_in" {
				writeSellInTargetsDerived(w)
				return
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
		defaultYear = time.Now().Year()
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

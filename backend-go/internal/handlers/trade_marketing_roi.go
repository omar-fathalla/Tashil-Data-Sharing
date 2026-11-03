package handlers

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// TradeMarketingSalesSource is the subset of the existing BigQuery repository used for ROI.
// *bigquery.Client satisfies it; sales come from Excel-ingested sell-out and sell-in data.
type TradeMarketingSalesSource interface {
	GetSellOutRecords(ctx context.Context, tenantID string, filter bigquery.RecordFilter) ([]domain.SellOutFact, int, error)
	GetSellInRecords(ctx context.Context, tenantID string, filter bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error)
}

// WithSalesSource attaches the sell-out/sell-in source used by the ROI endpoint.
func (h *TradeMarketingHandler) WithSalesSource(src TradeMarketingSalesSource) *TradeMarketingHandler {
	h.sales = src
	return h
}

// MonthlyChainRoiSummary mirrors the Flutter MonthlyChainRoiSummary model.
type MonthlyChainRoiSummary struct {
	Year                      int                       `json:"year"`
	Month                     int                       `json:"month"`
	ChainName                 string                    `json:"chain_name"`
	MarketingSpendEGP         float64                   `json:"marketing_spend_egp"`
	ActivitiesCount           int                       `json:"activities_count"`
	Expenses                  []domain.MarketingExpense `json:"expenses"`
	CurrentMonthSalesEGP      float64                   `json:"current_month_sales_egp"`
	PreviousMonthSalesEGP     float64                   `json:"previous_month_sales_egp"`
	LastYearSameMonthSalesEGP float64                   `json:"last_year_same_month_sales_egp"`
	CurrentMonthSellInEGP     float64                   `json:"current_month_sell_in_egp"`
	MoMGrowthPct              float64                   `json:"mom_growth_pct"`
	YoYGrowthPct              float64                   `json:"yoy_growth_pct"`
	RomiMultiple              float64                   `json:"romi_multiple"`
}

// normChain makes "Beet El Gomla", "beet-elgomla" and "BEET_ELGOMLA" compare equal.
func normChain(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// monthBounds returns YYYY-MM-DD first/last day using the real month length.
func monthBounds(year, month int) (string, string) {
	first := time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
	last := first.AddDate(0, 1, -1)
	return first.Format("2006-01-02"), last.Format("2006-01-02")
}

func prevMonth(year, month int) (int, int) {
	if month == 1 {
		return year - 1, 12
	}
	return year, month - 1
}

type salesAgg struct {
	src    TradeMarketingSalesSource
	tenant string
	ctx    context.Context
	out    map[string]map[string]float64 // "y-m" -> normChain -> EGP
	in     map[string]map[string]float64
}

func (a *salesAgg) sellOut(year, month int, chain string) (float64, error) {
	key := fmt.Sprintf("%d-%d", year, month)
	if _, ok := a.out[key]; !ok {
		start, end := monthBounds(year, month)
		recs, _, err := a.src.GetSellOutRecords(a.ctx, a.tenant, bigquery.RecordFilter{StartDate: start, EndDate: end})
		if err != nil {
			return 0, err
		}
		m := map[string]float64{}
		for _, r := range recs {
			m[normChain(r.RetailerChain)] += r.NetRevenue
		}
		a.out[key] = m
	}
	return a.out[key][normChain(chain)], nil
}

func (a *salesAgg) sellIn(year, month int, chain string) (float64, error) {
	key := fmt.Sprintf("%d-%d", year, month)
	if _, ok := a.in[key]; !ok {
		recs, _, err := a.src.GetSellInRecords(a.ctx, a.tenant, bigquery.SellInRecordFilter{Year: year, Month: month})
		if err != nil {
			return 0, err
		}
		m := map[string]float64{}
		for _, r := range recs {
			m[normChain(r.RetailerChain)] += r.NetValueEGP
		}
		a.in[key] = m
	}
	return a.in[key][normChain(chain)], nil
}

func pct(cur, base float64) float64 {
	if base <= 0 {
		return 0
	}
	return (cur - base) / base * 100
}

// romi mirrors the Flutter romiMultiple getter (MoM lift, falling back to positive YoY lift).
func romi(spend, cur, prev, ly float64) float64 {
	if spend <= 0 {
		return 0
	}
	mom, yoy := cur-prev, cur-ly
	lift := mom
	if mom < 0 && yoy > 0 {
		lift = yoy
	}
	return lift / spend
}

// HandleGetROI serves GET /api/v1/trade-marketing/roi?year=&month=&chain=
func (h *TradeMarketingHandler) HandleGetROI(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	if h.sales == nil {
		writeErr(w, http.StatusServiceUnavailable, "sales data source not configured")
		return
	}
	q := r.URL.Query()
	year, _ := strconv.Atoi(q.Get("year"))
	month, _ := strconv.Atoi(q.Get("month"))
	if q.Get("year") != "" && (year < 2000 || year > 2100) {
		writeErr(w, http.StatusBadRequest, "year must be between 2000 and 2100")
		return
	}
	if month < 0 || month > 12 {
		writeErr(w, http.StatusBadRequest, "month must be 1-12")
		return
	}
	chain := strings.TrimSpace(q.Get("chain"))
	if strings.EqualFold(chain, "all") {
		chain = ""
	}
	if k := kamChain(c); k != "" {
		chain = k
	}
	items, err := h.repo.ListMarketingExpenses(r.Context(), c.TenantID, domain.MarketingExpenseFilter{Year: year, Month: month})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to list expenses")
		return
	}
	type gkey struct {
		y, m int
		ch   string
	}
	groups := map[gkey]*MonthlyChainRoiSummary{}
	var order []gkey
	for _, e := range items {
		if chain != "" && normChain(e.ChainName) != normChain(chain) {
			continue
		}
		k := gkey{e.Year, e.Month, normChain(e.ChainName)}
		s, ok := groups[k]
		if !ok {
			s = &MonthlyChainRoiSummary{Year: e.Year, Month: e.Month, ChainName: e.ChainName, Expenses: []domain.MarketingExpense{}}
			groups[k] = s
			order = append(order, k)
		}
		s.MarketingSpendEGP += e.AmountEGP
		s.ActivitiesCount++
		s.Expenses = append(s.Expenses, e)
	}
	// A specific chain+month with no spend still gets a baseline row (used by the simulator).
	if chain != "" && year > 0 && month > 0 {
		k := gkey{year, month, normChain(chain)}
		if _, ok := groups[k]; !ok {
			groups[k] = &MonthlyChainRoiSummary{Year: year, Month: month, ChainName: chain, Expenses: []domain.MarketingExpense{}}
			order = append(order, k)
		}
	}
	agg := &salesAgg{src: h.sales, tenant: c.TenantID, ctx: r.Context(), out: map[string]map[string]float64{}, in: map[string]map[string]float64{}}
	out := make([]MonthlyChainRoiSummary, 0, len(order))
	for _, k := range order {
		s := groups[k]
		py, pm := prevMonth(s.Year, s.Month)
		var errs [4]error
		s.CurrentMonthSalesEGP, errs[0] = agg.sellOut(s.Year, s.Month, s.ChainName)
		s.PreviousMonthSalesEGP, errs[1] = agg.sellOut(py, pm, s.ChainName)
		s.LastYearSameMonthSalesEGP, errs[2] = agg.sellOut(s.Year-1, s.Month, s.ChainName)
		s.CurrentMonthSellInEGP, errs[3] = agg.sellIn(s.Year, s.Month, s.ChainName)
		for _, e := range errs {
			if e != nil {
				writeErr(w, http.StatusInternalServerError, "failed to load sales data")
				return
			}
		}
		s.MoMGrowthPct = pct(s.CurrentMonthSalesEGP, s.PreviousMonthSalesEGP)
		s.YoYGrowthPct = pct(s.CurrentMonthSalesEGP, s.LastYearSameMonthSalesEGP)
		s.RomiMultiple = romi(s.MarketingSpendEGP, s.CurrentMonthSalesEGP, s.PreviousMonthSalesEGP, s.LastYearSameMonthSalesEGP)
		out = append(out, *s)
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i].Year*100+out[i].Month, out[j].Year*100+out[j].Month
		if a != b {
			return a < b
		}
		return out[i].ChainName < out[j].ChainName
	})
	writeJSON(w, http.StatusOK, map[string]interface{}{"summaries": out, "count": len(out)})
}

// uploadRejection explains why an uploaded expense row was not saved.
type uploadRejection struct {
	Row    int    `json:"row"`
	Reason string `json:"reason"`
}

var expenseHeaderAliases = map[string]string{
	"year": "year", "السنة": "year", "month": "month", "الشهر": "month",
	"chain": "chain_name", "chain_name": "chain_name", "السلسلة": "chain_name",
	"category": "category", "الفئة": "category", "brand": "brand_name", "brand_name": "brand_name", "البراند": "brand_name",
	"campaign": "campaign_title", "campaign_title": "campaign_title", "الحملة": "campaign_title",
	"vendor": "vendor_or_agency", "vendor_or_agency": "vendor_or_agency", "agency": "vendor_or_agency", "المورد": "vendor_or_agency",
	"amount": "amount_egp", "amount_egp": "amount_egp", "المبلغ": "amount_egp", "notes": "notes", "ملاحظات": "notes",
}

func normHeader(s string) string {
	s = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(s, "\ufeff")))
	return strings.ReplaceAll(strings.ReplaceAll(s, " ", "_"), "-", "_")
}

// HandleUploadExpenses serves POST /api/v1/trade-marketing/expenses/upload (multipart "file": .xlsx or .csv).
// Expected header row: year, month, chain_name, category, brand_name, campaign_title, vendor_or_agency, amount_egp, notes.
func (h *TradeMarketingHandler) HandleUploadExpenses(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify trade marketing expenses")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeErr(w, http.StatusBadRequest, "expected multipart form with a file field")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "missing file field")
		return
	}
	defer file.Close()
	name := strings.ToLower(header.Filename)
	if !strings.HasSuffix(name, ".xlsx") && !strings.HasSuffix(name, ".csv") {
		writeErr(w, http.StatusBadRequest, "only .xlsx or .csv files are supported")
		return
	}
	raw, err := io.ReadAll(file)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "failed to read file")
		return
	}
	rows, err := gemini.ExtractXLSXOrCSVRows(raw)
	if err != nil || len(rows) < 2 {
		writeErr(w, http.StatusBadRequest, "file has no data rows")
		return
	}
	col := map[string]int{}
	for i, hname := range rows[0] {
		if f, ok := expenseHeaderAliases[normHeader(hname)]; ok {
			col[f] = i
		} else if f, ok := expenseHeaderAliases[strings.TrimSpace(hname)]; ok {
			col[f] = i
		}
	}
	for _, req := range []string{"year", "month", "chain_name", "category", "amount_egp"} {
		if _, ok := col[req]; !ok {
			writeErr(w, http.StatusBadRequest, "missing required column: "+req)
			return
		}
	}
	get := func(row []string, f string) string {
		i, ok := col[f]
		if !ok || i >= len(row) {
			return ""
		}
		return strings.TrimSpace(row[i])
	}
	saved := 0
	rejected := []uploadRejection{}
	for idx, row := range rows[1:] {
		rowNum := idx + 2
		empty := true
		for _, v := range row {
			if strings.TrimSpace(v) != "" {
				empty = false
				break
			}
		}
		if empty {
			continue
		}
		yr, e1 := strconv.Atoi(get(row, "year"))
		mo, e2 := strconv.Atoi(get(row, "month"))
		amt, e3 := strconv.ParseFloat(strings.ReplaceAll(get(row, "amount_egp"), ",", ""), 64)
		if e1 != nil || e2 != nil || e3 != nil {
			rejected = append(rejected, uploadRejection{rowNum, "year, month and amount_egp must be numeric"})
			continue
		}
		p := expensePayload{Year: yr, Month: mo, ChainName: get(row, "chain_name"),
			Category: strings.ToLower(get(row, "category")), BrandName: get(row, "brand_name"),
			CampaignTitle: get(row, "campaign_title"), VendorOrAgency: get(row, "vendor_or_agency"),
			AmountEGP: amt, Notes: get(row, "notes")}
		if err := p.validate(); err != nil {
			rejected = append(rejected, uploadRejection{rowNum, err.Error()})
			continue
		}
		if k := kamChain(c); k != "" && !strings.EqualFold(k, p.ChainName) {
			rejected = append(rejected, uploadRejection{rowNum, "chain KAM can only record expenses for the assigned chain"})
			continue
		}
		e := &domain.MarketingExpense{TenantID: c.TenantID, Year: p.Year, Month: p.Month, ChainName: p.ChainName,
			Category: p.Category, BrandName: p.BrandName, CampaignTitle: p.CampaignTitle,
			VendorOrAgency: p.VendorOrAgency, AmountEGP: p.AmountEGP, Notes: p.Notes, CreatedBy: c.Email}
		if err := h.repo.SaveMarketingExpense(r.Context(), e); err != nil {
			rejected = append(rejected, uploadRejection{rowNum, "failed to save"})
			continue
		}
		saved++
	}
	h.recordAudit(r, c, "UPLOAD_MARKETING_EXPENSES", fmt.Sprintf("%s: %d saved, %d rejected", header.Filename, saved, len(rejected)))
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"filename": header.Filename, "saved_count": saved, "rejected_count": len(rejected), "rejected": rejected,
	})
}

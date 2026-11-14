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
	// YoYAvailable is false when the same month last year has no Sell-Out;
	// YoYGrowthPct is then 0 and the UI shows "—" instead of +0.0%.
	YoYAvailable bool `json:"yoy_available"`
	// Seasonal YoY baseline and incremental ROMI (see domain.ComputeRoiLift).
	BaselineSalesEGP   *float64 `json:"baseline_sales_egp"`
	BaselineAvailable  bool     `json:"baseline_available"`
	BaselineMethod     string   `json:"baseline_method"`
	OrganicYoYRatio    *float64 `json:"organic_yoy_ratio"`
	OrganicMonthsUsed  int      `json:"organic_months_used"`
	IncrementalLiftEGP *float64 `json:"incremental_lift_egp"`
	LiftVsBaselinePct  *float64 `json:"lift_vs_baseline_pct"`
	RomiMultiple       *float64 `json:"romi_multiple"`
	NetRoiPct          *float64 `json:"net_roi_pct"`
	BaselineMethodAR   string   `json:"baseline_method_ar"`
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

func ymKey(year, month int) string { return fmt.Sprintf("%d-%d", year, month) }

func dateYearMonth(d string) (int, int, bool) {
	if len(d) < 7 {
		return 0, 0, false
	}
	t, err := time.Parse("2006-01-02", d[:10])
	if err != nil {
		// Accept YYYY-MM
		t, err = time.Parse("2006-01", d[:7])
		if err != nil {
			return 0, 0, false
		}
	}
	return t.Year(), int(t.Month()), true
}

// loadSellOutWindow fills a.out for every month in [from, to] inclusive
// with one GetSellOutRecords call (same NetRevenue sum as sellOut).
func (a *salesAgg) loadSellOutWindow(from, to domain.RoiMonthKey) error {
	start, _ := monthBounds(from.Year, from.Month)
	_, end := monthBounds(to.Year, to.Month)
	recs, _, err := a.src.GetSellOutRecords(a.ctx, a.tenant, bigquery.RecordFilter{StartDate: start, EndDate: end})
	if err != nil {
		return err
	}
	for _, r := range recs {
		y, m, ok := dateYearMonth(r.TransactionDate)
		if !ok {
			continue
		}
		key := ymKey(y, m)
		if a.out[key] == nil {
			a.out[key] = map[string]float64{}
		}
		a.out[key][normChain(r.RetailerChain)] += r.NetRevenue
	}
	// Ensure every month in the window has a map so later lookups are cheap.
	for cur := from; ; {
		key := ymKey(cur.Year, cur.Month)
		if a.out[key] == nil {
			a.out[key] = map[string]float64{}
		}
		if cur == to {
			break
		}
		if cur.Month == 12 {
			cur = domain.RoiMonthKey{Year: cur.Year + 1, Month: 1}
		} else {
			cur = domain.RoiMonthKey{Year: cur.Year, Month: cur.Month + 1}
		}
	}
	return nil
}

func (a *salesAgg) chainSalesMap(chain string) map[domain.RoiMonthKey]float64 {
	nc := normChain(chain)
	out := map[domain.RoiMonthKey]float64{}
	for key, m := range a.out {
		var y, mo int
		if _, err := fmt.Sscanf(key, "%d-%d", &y, &mo); err != nil {
			continue
		}
		if v := m[nc]; v != 0 {
			out[domain.RoiMonthKey{Year: y, Month: mo}] = v
		}
	}
	return out
}

func applyLift(s *MonthlyChainRoiSummary, sales map[domain.RoiMonthKey]float64, campaigns map[domain.RoiMonthKey]bool) {
	res := domain.ComputeRoiLift(
		s.CurrentMonthSalesEGP,
		s.LastYearSameMonthSalesEGP,
		s.MarketingSpendEGP,
		domain.RoiMonthKey{Year: s.Year, Month: s.Month},
		sales,
		campaigns,
	)
	s.BaselineAvailable = res.Available
	s.BaselineMethod = res.Method
	s.OrganicMonthsUsed = res.OrganicMonthsUsed
	s.BaselineMethodAR = res.MethodAR
	s.RomiMultiple = res.RomiMultiple
	s.NetRoiPct = res.NetRoiPct
	if res.Available {
		b, lift, pct := res.BaselineSalesEGP, res.IncrementalLiftEGP, res.LiftVsBaselinePct
		s.BaselineSalesEGP = &b
		s.IncrementalLiftEGP = &lift
		s.LiftVsBaselinePct = &pct
		if res.Method == domain.RoiBaselineMethodYoySeasonal {
			r := res.OrganicYoYRatio
			s.OrganicYoYRatio = &r
		}
	}
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
	// All expenses (not just the requested month) so campaign months can
	// be excluded from the organic-trend window. Output is still filtered
	// to the requested year/month/chain below.
	allItems, err := h.repo.ListMarketingExpenses(r.Context(), c.TenantID, domain.MarketingExpenseFilter{})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to list expenses")
		return
	}
	items := make([]domain.MarketingExpense, 0, len(allItems))
	for _, e := range allItems {
		if year > 0 && e.Year != year {
			continue
		}
		if month > 0 && e.Month != month {
			continue
		}
		items = append(items, e)
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
	// Campaign months by chain (spend > 0), used to exclude promoted
	// months from the organic YoY trend and the prior-organic average.
	campaignsByChain := map[string]map[domain.RoiMonthKey]bool{}
	for _, e := range allItems {
		if e.AmountEGP <= 0 {
			continue
		}
		nc := normChain(e.ChainName)
		if campaignsByChain[nc] == nil {
			campaignsByChain[nc] = map[domain.RoiMonthKey]bool{}
		}
		campaignsByChain[nc][domain.RoiMonthKey{Year: e.Year, Month: e.Month}] = true
	}

	agg := &salesAgg{src: h.sales, tenant: c.TenantID, ctx: r.Context(), out: map[string]map[string]float64{}, in: map[string]map[string]float64{}}
	// One window covering last-year comparables and a 12-month lookback
	// for every summary month (~24 months).
	if len(order) > 0 {
		from, to := domain.RoiMonthKey{Year: order[0].y, Month: order[0].m}, domain.RoiMonthKey{Year: order[0].y, Month: order[0].m}
		for _, k := range order {
			cur := domain.RoiMonthKey{Year: k.y, Month: k.m}
			start := domain.RoiMonthKey{Year: k.y - 2, Month: k.m} // lookback + last-year of those months
			if start.Year < from.Year || (start.Year == from.Year && start.Month < from.Month) {
				from = start
			}
			if cur.Year > to.Year || (cur.Year == to.Year && cur.Month > to.Month) {
				to = cur
			}
		}
		if err := agg.loadSellOutWindow(from, to); err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load sales data")
			return
		}
	}
	out := make([]MonthlyChainRoiSummary, 0, len(order))
	for _, k := range order {
		s := groups[k]
		py, pm := prevMonth(s.Year, s.Month)
		var err error
		s.CurrentMonthSalesEGP, err = agg.sellOut(s.Year, s.Month, s.ChainName)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load sales data")
			return
		}
		s.PreviousMonthSalesEGP, err = agg.sellOut(py, pm, s.ChainName)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load sales data")
			return
		}
		s.LastYearSameMonthSalesEGP, err = agg.sellOut(s.Year-1, s.Month, s.ChainName)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load sales data")
			return
		}
		s.CurrentMonthSellInEGP, err = agg.sellIn(s.Year, s.Month, s.ChainName)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load sales data")
			return
		}
		s.MoMGrowthPct = pct(s.CurrentMonthSalesEGP, s.PreviousMonthSalesEGP)
		s.YoYGrowthPct = pct(s.CurrentMonthSalesEGP, s.LastYearSameMonthSalesEGP)
		s.YoYAvailable = s.LastYearSameMonthSalesEGP > 0
		applyLift(s, agg.chainSalesMap(s.ChainName), campaignsByChain[normChain(s.ChainName)])
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

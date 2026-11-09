package bigquery

import (
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// SellInReturnsFilter scopes the Phase-1 المرتجعات report.
type SellInReturnsFilter struct {
	Year         int
	Month        int    // 0 = all months in year
	Chain        string // optional retailer chain
	Branch       string // customer name / branch code contains (case-insensitive)
	Product      string // item name / code / barcode contains
	ProductGroup string // ItemGroup / ProductFamily / SubCategory exact-or-contains
}

// SellInReturnsCell is one branch×month (or monthly total) bucket.
type SellInReturnsCell struct {
	GrossValueEGP    float64 `json:"gross_value_egp"`
	ReturnsValueEGP  float64 `json:"returns_value_egp"` // positive display amount
	ReturnsQty       float64 `json:"returns_qty"`       // positive display qty
	NetValueEGP      float64 `json:"net_value_egp"`     // gross − returns (signed sum)
	ReturnPctOfGross float64 `json:"return_pct_of_gross"`
}

// SellInReturnsBranchRow is one branch across dynamic months.
type SellInReturnsBranchRow struct {
	BranchKey  string                       `json:"branch_key"`
	BranchName string                       `json:"branch_name"`
	Chain      string                       `json:"retailer_chain,omitempty"`
	ByMonth    map[string]SellInReturnsCell `json:"by_month"` // key = "1".."12"
	Total      SellInReturnsCell            `json:"total"`
}

// SellInReturnsMonthPoint is the monthly chart series (gross / returns / net).
type SellInReturnsMonthPoint struct {
	MonthNum         int     `json:"month_num"`
	MonthAR          string  `json:"month_ar"`
	MonthEN          string  `json:"month_en"`
	GrossValueEGP    float64 `json:"gross_value_egp"`
	ReturnsValueEGP  float64 `json:"returns_value_egp"`
	ReturnsQty       float64 `json:"returns_qty"`
	NetValueEGP      float64 `json:"net_value_egp"`
	ReturnPctOfGross float64 `json:"return_pct_of_gross"`
}

// SellInReturnsKPI is the top KPI strip.
type SellInReturnsKPI struct {
	ReturnsValueEGP  float64  `json:"returns_value_egp"`
	ReturnsQty       float64  `json:"returns_qty"`
	GrossValueEGP    float64  `json:"gross_value_egp"`
	NetValueEGP      float64  `json:"net_value_egp"`
	ReturnPctOfGross float64  `json:"return_pct_of_gross"`
	MomChangePct     *float64 `json:"mom_change_pct"` // nil when prior month unavailable
	MomDirection     string   `json:"mom_direction"`  // up | down | flat | n/a
	FocusMonth       int      `json:"focus_month"`    // month used for MoM (0 if none)
}

// SellInReturnsAdvisory warns when product×branch×month nets negative (kept, not hidden).
type SellInReturnsAdvisory struct {
	Year        int     `json:"year"`
	MonthNum    int     `json:"month_num"`
	BranchName  string  `json:"branch_name"`
	ProductCode string  `json:"product_code,omitempty"`
	ProductName string  `json:"product_name"`
	NetValueEGP float64 `json:"net_value_egp"`
	NetQty      float64 `json:"net_qty"`
	MessageAR   string  `json:"message_ar"`
}

// SellInReturnsTopProduct is one of the top returned products (Phase 2).
type SellInReturnsTopProduct struct {
	Rank             int     `json:"rank"`
	ProductCode      string  `json:"product_code,omitempty"`
	ProductName      string  `json:"product_name"`
	ProductGroup     string  `json:"product_group,omitempty"`
	ReturnsValueEGP  float64 `json:"returns_value_egp"`
	ReturnsQty       float64 `json:"returns_qty"`
	GrossValueEGP    float64 `json:"gross_value_egp"`
	NetValueEGP      float64 `json:"net_value_egp"`
	ReturnPctOfGross float64 `json:"return_pct_of_gross"`
	ShareOfReturns   float64 `json:"share_of_returns"` // % of period returns value
}

// SellInReturnsAlert flags when returns exceed a normal threshold (Phase 2).
// Separate from net-negative Advisories.
type SellInReturnsAlert struct {
	Severity  string  `json:"severity"` // warning | critical
	Code      string  `json:"code"`     // return_pct | mom_spike | branch_pct | product_pct
	MessageAR string  `json:"message_ar"`
	Value     float64 `json:"value"`
	Threshold float64 `json:"threshold"`
	Context   string  `json:"context,omitempty"` // branch / product / month label
}

// Default returns-rate thresholds (of gross). Match Phase-1 KPI card soft flags.
const (
	ReturnsWarnPctOfGross     = 5.0
	ReturnsCriticalPctOfGross = 10.0
	ReturnsMomSpikePct        = 25.0
	TopReturnedProductsLimit  = 10
)

// SellInReturnsFilterOptions lists distinct values for the UI filters (from year-scoped data).
type SellInReturnsFilterOptions struct {
	Years         []int    `json:"years"`
	Branches      []string `json:"branches"`
	Products      []string `json:"products"`
	ProductGroups []string `json:"product_groups"`
}

// SellInReturnsReport is GET /api/v1/analytics/sell-in-returns.
type SellInReturnsReport struct {
	Year                 int                          `json:"year"`
	Month                int                          `json:"month"`
	Months               []int                        `json:"months"` // dynamic months present after filters
	KPIs                 SellInReturnsKPI             `json:"kpis"`
	Monthly              []SellInReturnsMonthPoint    `json:"monthly"`
	Branches             []SellInReturnsBranchRow     `json:"branches"`
	ColumnTotals         map[string]SellInReturnsCell `json:"column_totals"`
	GrandTotal           SellInReturnsCell            `json:"grand_total"`
	FilterOptions        SellInReturnsFilterOptions   `json:"filter_options"`
	Advisories           []SellInReturnsAdvisory      `json:"advisories"`
	TopReturnedProducts  []SellInReturnsTopProduct    `json:"top_returned_products"`
	Alerts               []SellInReturnsAlert         `json:"alerts"`
}

var arabicMonthNamesReturns = []string{
	"", "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
	"يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
}
var englishMonthNamesReturns = []string{
	"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

// IsSellInReturn reports whether a Sell-In row is a return (negative TO/QTY or مرتجع type).
// Return rows are stored as-is; callers must not drop them.
func IsSellInReturn(r domain.SellInRecord) bool {
	if r.NetQtyCases < 0 || r.NetValueEGP < 0 {
		return true
	}
	tx := strings.TrimSpace(r.TransactionType)
	if strings.Contains(tx, "مرتجع") || strings.EqualFold(tx, "return") {
		return true
	}
	return false
}

func productGroupOf(r domain.SellInRecord) string {
	for _, c := range []string{r.ItemGroup, r.ProductFamily, r.SubCategory, r.CanonicalFamilyKey} {
		if s := strings.TrimSpace(c); s != "" {
			return s
		}
	}
	return ""
}

func branchKeyOf(r domain.SellInRecord) string {
	if id := strings.TrimSpace(r.CustomerBranchCode); id != "" {
		return id
	}
	return strings.TrimSpace(r.CustomerName)
}

// productKeyOf is the stable product identity for netting advisories.
// Prefer ItemCode, then Barcode; display names are never used as the key.
func productKeyOf(r domain.SellInRecord) string {
	if c := strings.TrimSpace(r.ItemCode); c != "" {
		return c
	}
	if b := strings.TrimSpace(r.Barcode); b != "" {
		return b
	}
	return strings.TrimSpace(r.ItemName)
}

func finalizeCell(c *SellInReturnsCell) {
	c.GrossValueEGP = round2(c.GrossValueEGP)
	c.ReturnsValueEGP = round2(c.ReturnsValueEGP)
	c.ReturnsQty = round2(c.ReturnsQty)
	c.NetValueEGP = round2(c.NetValueEGP)
	if c.GrossValueEGP > 0 {
		c.ReturnPctOfGross = round2((c.ReturnsValueEGP / c.GrossValueEGP) * 100)
	} else if c.ReturnsValueEGP > 0 {
		c.ReturnPctOfGross = 100
	}
}

func addToCell(c *SellInReturnsCell, r domain.SellInRecord) {
	if IsSellInReturn(r) {
		c.ReturnsValueEGP += math.Abs(r.NetValueEGP)
		c.ReturnsQty += math.Abs(r.NetQtyCases)
		c.NetValueEGP += r.NetValueEGP // typically negative
		return
	}
	if r.NetValueEGP > 0 {
		c.GrossValueEGP += r.NetValueEGP
	}
	c.NetValueEGP += r.NetValueEGP
}

func matchesReturnsFilter(r domain.SellInRecord, f SellInReturnsFilter, applyMonth bool) bool {
	if f.Year > 0 && r.Year != f.Year {
		return false
	}
	if applyMonth && f.Month > 0 && r.MonthNum != f.Month {
		return false
	}
	chain := strings.ToLower(strings.TrimSpace(f.Chain))
	if chain == "all" || chain == "الكل" {
		chain = ""
	}
	if chain != "" && !strings.EqualFold(strings.TrimSpace(r.RetailerChain), chain) {
		return false
	}
	if br := strings.TrimSpace(f.Branch); br != "" && br != "all" && br != "الكل" {
		bl := strings.ToLower(br)
		if !strings.Contains(strings.ToLower(r.CustomerName), bl) &&
			!strings.Contains(strings.ToLower(r.CustomerBranchCode), bl) {
			return false
		}
	}
	if p := strings.TrimSpace(f.Product); p != "" && p != "all" && p != "الكل" {
		if !domain.MatchesProductSearchQuery(p, r.ItemCode, r.Barcode, r.ItemName, r.ItemName, r.SubCategory, r.Brand) {
			return false
		}
	}
	if g := strings.TrimSpace(f.ProductGroup); g != "" && g != "all" && g != "الكل" {
		gl := strings.ToLower(g)
		pg := strings.ToLower(productGroupOf(r))
		if pg == "" || (!strings.EqualFold(pg, gl) && !strings.Contains(pg, gl)) {
			return false
		}
	}
	return true
}

// AggregateSellInReturns builds the Phase-1 returns report from in-memory Sell-In rows.
// Negatives are kept; monthly netting uses each row's Document Date month (Year/MonthNum).
func AggregateSellInReturns(records []domain.SellInRecord, f SellInReturnsFilter) SellInReturnsReport {
	yearSet := map[int]bool{}
	branchSet := map[string]bool{}
	productSet := map[string]bool{}
	groupSet := map[string]bool{}

	for _, r := range records {
		if r.Year > 0 {
			yearSet[r.Year] = true
		}
		if f.Year > 0 && r.Year != f.Year {
			continue
		}
		chain := strings.ToLower(strings.TrimSpace(f.Chain))
		if chain == "all" || chain == "الكل" {
			chain = ""
		}
		if chain != "" && !strings.EqualFold(strings.TrimSpace(r.RetailerChain), chain) {
			continue
		}
		if name := strings.TrimSpace(r.CustomerName); name != "" {
			branchSet[name] = true
		}
		if name := strings.TrimSpace(r.ItemName); name != "" {
			productSet[name] = true
		} else if code := strings.TrimSpace(r.ItemCode); code != "" {
			productSet[code] = true
		}
		if g := productGroupOf(r); g != "" {
			groupSet[g] = true
		}
	}

	years := sortedInts(yearSet)
	branchesOpt := sortedStrings(branchSet)
	productsOpt := sortedStrings(productSet)
	groupsOpt := sortedStrings(groupSet)

	// Dimensional filters (not month) for monthly chart + MoM continuity.
	dimFiltered := make([]domain.SellInRecord, 0, len(records))
	for _, r := range records {
		if matchesReturnsFilter(r, f, false) {
			dimFiltered = append(dimFiltered, r)
		}
	}

	monthSet := map[int]bool{}
	type bKey struct{ key, name, chain string }
	branchRows := map[string]*SellInReturnsBranchRow{}
	colTotals := map[int]*SellInReturnsCell{}
	var grand SellInReturnsCell
	monthlyCells := map[int]*SellInReturnsCell{}

	type netKey struct {
		month   int
		branch  string // CustomerBranchCode (stable)
		product string // ItemCode / Barcode (stable); never display name
	}
	type netSum struct {
		val, qty    float64
		branchName  string // display only
		productName string
		productCode string
	}
	netAgg := map[netKey]*netSum{}

	// Phase-2 top returned products: aggregate by stable product identity.
	type prodAgg struct {
		returnsVal, returnsQty, grossVal, netVal float64
		name, code, group                        string
	}
	productAgg := map[string]*prodAgg{}

	for _, r := range dimFiltered {
		if r.MonthNum < 1 || r.MonthNum > 12 {
			continue
		}
		monthSet[r.MonthNum] = true
		mk := r.MonthNum

		// Net advisories by stable branch+product identity so renamed ItemName
		// on a return does not split from the invoice (false net-negative).
		nk := netKey{month: mk, branch: branchKeyOf(r), product: productKeyOf(r)}
		na := netAgg[nk]
		if na == nil {
			na = &netSum{
				branchName:  strings.TrimSpace(r.CustomerName),
				productName: strings.TrimSpace(r.ItemName),
				productCode: strings.TrimSpace(r.ItemCode),
			}
			if na.branchName == "" {
				na.branchName = nk.branch
			}
			if na.productName == "" {
				na.productName = nk.product
			}
			if na.productCode == "" {
				na.productCode = strings.TrimSpace(r.Barcode)
			}
			netAgg[nk] = na
		}
		na.val += r.NetValueEGP
		na.qty += r.NetQtyCases
		// Prefer a non-empty display name if a later row has one.
		if name := strings.TrimSpace(r.CustomerName); name != "" {
			na.branchName = name
		}
		if name := strings.TrimSpace(r.ItemName); name != "" {
			na.productName = name
		}

		// Period-scoped product rollup (respect month filter for top-10 + product alerts).
		if f.Month <= 0 || r.MonthNum == f.Month {
			pk := productKeyOf(r)
			pa := productAgg[pk]
			if pa == nil {
				pa = &prodAgg{
					name:  strings.TrimSpace(r.ItemName),
					code:  strings.TrimSpace(r.ItemCode),
					group: productGroupOf(r),
				}
				if pa.name == "" {
					pa.name = pk
				}
				if pa.code == "" {
					pa.code = strings.TrimSpace(r.Barcode)
				}
				productAgg[pk] = pa
			}
			if name := strings.TrimSpace(r.ItemName); name != "" {
				pa.name = name
			}
			if g := productGroupOf(r); g != "" {
				pa.group = g
			}
			if IsSellInReturn(r) {
				pa.returnsVal += math.Abs(r.NetValueEGP)
				pa.returnsQty += math.Abs(r.NetQtyCases)
				pa.netVal += r.NetValueEGP
			} else {
				if r.NetValueEGP > 0 {
					pa.grossVal += r.NetValueEGP
				}
				pa.netVal += r.NetValueEGP
			}
		}

		bk := branchKeyOf(r)
		br := branchRows[bk]
		if br == nil {
			br = &SellInReturnsBranchRow{
				BranchKey:  bk,
				BranchName: strings.TrimSpace(r.CustomerName),
				Chain:      strings.TrimSpace(r.RetailerChain),
				ByMonth:    map[string]SellInReturnsCell{},
			}
			if br.BranchName == "" {
				br.BranchName = bk
			}
			branchRows[bk] = br
		}
		cell := br.ByMonth[fmt.Sprintf("%d", mk)]
		addToCell(&cell, r)
		br.ByMonth[fmt.Sprintf("%d", mk)] = cell

		if colTotals[mk] == nil {
			colTotals[mk] = &SellInReturnsCell{}
		}
		addToCell(colTotals[mk], r)

		if monthlyCells[mk] == nil {
			monthlyCells[mk] = &SellInReturnsCell{}
		}
		addToCell(monthlyCells[mk], r)
	}

	// Period-scoped KPIs / matrix visibility when a month filter is set:
	// rebuild branch totals & grand from selected month(s) only.
	visibleMonths := sortedInts(monthSet)
	if f.Month > 0 {
		visibleMonths = []int{}
		if monthSet[f.Month] {
			visibleMonths = []int{f.Month}
		} else if f.Month >= 1 && f.Month <= 12 {
			visibleMonths = []int{f.Month}
		}
	}

	outBranches := make([]SellInReturnsBranchRow, 0, len(branchRows))
	for _, br := range branchRows {
		var total SellInReturnsCell
		filteredMonths := map[string]SellInReturnsCell{}
		for _, m := range visibleMonths {
			key := fmt.Sprintf("%d", m)
			cell, ok := br.ByMonth[key]
			if !ok {
				continue
			}
			finalizeCell(&cell)
			filteredMonths[key] = cell
			total.GrossValueEGP += cell.GrossValueEGP
			total.ReturnsValueEGP += cell.ReturnsValueEGP
			total.ReturnsQty += cell.ReturnsQty
			total.NetValueEGP += cell.NetValueEGP
		}
		if f.Month > 0 && len(filteredMonths) == 0 {
			continue
		}
		finalizeCell(&total)
		br.ByMonth = filteredMonths
		br.Total = total
		outBranches = append(outBranches, *br)
		grand.GrossValueEGP += total.GrossValueEGP
		grand.ReturnsValueEGP += total.ReturnsValueEGP
		grand.ReturnsQty += total.ReturnsQty
		grand.NetValueEGP += total.NetValueEGP
	}
	sort.Slice(outBranches, func(i, j int) bool {
		if outBranches[i].Total.ReturnsValueEGP != outBranches[j].Total.ReturnsValueEGP {
			return outBranches[i].Total.ReturnsValueEGP > outBranches[j].Total.ReturnsValueEGP
		}
		return outBranches[i].BranchName < outBranches[j].BranchName
	})
	finalizeCell(&grand)

	colOut := map[string]SellInReturnsCell{}
	for _, m := range visibleMonths {
		if c := colTotals[m]; c != nil {
			cp := *c
			finalizeCell(&cp)
			colOut[fmt.Sprintf("%d", m)] = cp
		} else {
			colOut[fmt.Sprintf("%d", m)] = SellInReturnsCell{}
		}
	}

	// Monthly chart: always full year under dimensional filters (so MoM/chart stay coherent).
	chartMonths := sortedInts(monthSet)
	monthly := make([]SellInReturnsMonthPoint, 0, len(chartMonths))
	for _, m := range chartMonths {
		c := SellInReturnsCell{}
		if monthlyCells[m] != nil {
			c = *monthlyCells[m]
		}
		finalizeCell(&c)
		monthly = append(monthly, SellInReturnsMonthPoint{
			MonthNum:         m,
			MonthAR:          arabicMonthNamesReturns[m],
			MonthEN:          englishMonthNamesReturns[m],
			GrossValueEGP:    c.GrossValueEGP,
			ReturnsValueEGP:  c.ReturnsValueEGP,
			ReturnsQty:       c.ReturnsQty,
			NetValueEGP:      c.NetValueEGP,
			ReturnPctOfGross: c.ReturnPctOfGross,
		})
	}

	kpis := SellInReturnsKPI{
		ReturnsValueEGP:  grand.ReturnsValueEGP,
		ReturnsQty:       grand.ReturnsQty,
		GrossValueEGP:    grand.GrossValueEGP,
		NetValueEGP:      grand.NetValueEGP,
		ReturnPctOfGross: grand.ReturnPctOfGross,
		MomDirection:     "n/a",
	}

	focus := f.Month
	if focus <= 0 {
		if len(chartMonths) > 0 {
			focus = chartMonths[len(chartMonths)-1]
		}
	}
	kpis.FocusMonth = focus
	if focus > 0 {
		var cur, prev float64
		var hasCur, hasPrev bool
		for _, p := range monthly {
			if p.MonthNum == focus {
				cur, hasCur = p.ReturnsValueEGP, true
			}
			if p.MonthNum == focus-1 {
				prev, hasPrev = p.ReturnsValueEGP, true
			}
		}
		if hasCur && hasPrev {
			var pct float64
			if prev == 0 {
				if cur == 0 {
					pct = 0
				} else {
					pct = 100
				}
			} else {
				pct = round2(((cur - prev) / prev) * 100)
			}
			kpis.MomChangePct = &pct
			switch {
			case pct > 0.05:
				kpis.MomDirection = "up"
			case pct < -0.05:
				kpis.MomDirection = "down"
			default:
				kpis.MomDirection = "flat"
			}
		}
	}

	advisories := make([]SellInReturnsAdvisory, 0)
	for k, v := range netAgg {
		if f.Month > 0 && k.month != f.Month {
			continue
		}
		if v.val >= -0.005 {
			continue
		}
		advisories = append(advisories, SellInReturnsAdvisory{
			Year:        f.Year,
			MonthNum:    k.month,
			BranchName:  v.branchName,
			ProductCode: v.productCode,
			ProductName: v.productName,
			NetValueEGP: round2(v.val),
			NetQty:      round2(v.qty),
			MessageAR: fmt.Sprintf(
				"صافي التوريد سالب للصنف «%s» في فرع «%s» خلال %s (%.2f ج.م) — الصفوف محفوظة ولم تُخفَ.",
				v.productName, v.branchName, arabicMonthNamesReturns[k.month], v.val,
			),
		})
	}
	sort.Slice(advisories, func(i, j int) bool {
		if advisories[i].NetValueEGP != advisories[j].NetValueEGP {
			return advisories[i].NetValueEGP < advisories[j].NetValueEGP
		}
		return advisories[i].ProductName < advisories[j].ProductName
	})

	// Phase-2: top returned products (by returns value).
	topProducts := make([]SellInReturnsTopProduct, 0, len(productAgg))
	for _, pa := range productAgg {
		if pa.returnsVal <= 0.005 {
			continue
		}
		pct := 0.0
		if pa.grossVal > 0 {
			pct = round2((pa.returnsVal / pa.grossVal) * 100)
		} else if pa.returnsVal > 0 {
			pct = 100
		}
		share := 0.0
		if grand.ReturnsValueEGP > 0 {
			share = round2((pa.returnsVal / grand.ReturnsValueEGP) * 100)
		}
		topProducts = append(topProducts, SellInReturnsTopProduct{
			ProductCode:      pa.code,
			ProductName:      pa.name,
			ProductGroup:     pa.group,
			ReturnsValueEGP:  round2(pa.returnsVal),
			ReturnsQty:       round2(pa.returnsQty),
			GrossValueEGP:    round2(pa.grossVal),
			NetValueEGP:      round2(pa.netVal),
			ReturnPctOfGross: pct,
			ShareOfReturns:   share,
		})
	}
	sort.Slice(topProducts, func(i, j int) bool {
		if topProducts[i].ReturnsValueEGP != topProducts[j].ReturnsValueEGP {
			return topProducts[i].ReturnsValueEGP > topProducts[j].ReturnsValueEGP
		}
		return topProducts[i].ProductName < topProducts[j].ProductName
	})
	if len(topProducts) > TopReturnedProductsLimit {
		topProducts = topProducts[:TopReturnedProductsLimit]
	}
	for i := range topProducts {
		topProducts[i].Rank = i + 1
	}

	// Phase-2: threshold alerts when returns exceed normal levels.
	alerts := buildReturnsAlerts(kpis, outBranches, topProducts)

	monthsOut := visibleMonths
	if len(monthsOut) == 0 && f.Month <= 0 {
		monthsOut = chartMonths
	}

	return SellInReturnsReport{
		Year:         f.Year,
		Month:        f.Month,
		Months:       monthsOut,
		KPIs:         kpis,
		Monthly:      monthly,
		Branches:     outBranches,
		ColumnTotals: colOut,
		GrandTotal:   grand,
		FilterOptions: SellInReturnsFilterOptions{
			Years:         years,
			Branches:      branchesOpt,
			Products:      productsOpt,
			ProductGroups: groupsOpt,
		},
		Advisories:          advisories,
		TopReturnedProducts: topProducts,
		Alerts:              alerts,
	}
}

// buildReturnsAlerts emits warning/critical alerts when overall, MoM, branch, or
// product return rates exceed the default "normal" thresholds.
func buildReturnsAlerts(
	kpis SellInReturnsKPI,
	branches []SellInReturnsBranchRow,
	top []SellInReturnsTopProduct,
) []SellInReturnsAlert {
	alerts := make([]SellInReturnsAlert, 0)

	if kpis.GrossValueEGP > 0 || kpis.ReturnsValueEGP > 0 {
		pct := kpis.ReturnPctOfGross
		switch {
		case pct >= ReturnsCriticalPctOfGross:
			alerts = append(alerts, SellInReturnsAlert{
				Severity:  "critical",
				Code:      "return_pct",
				MessageAR: fmt.Sprintf("نسبة المرتجع من الإجمالي %.1f%% تجاوزت الحد الحرج (%.0f%%).", pct, ReturnsCriticalPctOfGross),
				Value:     pct,
				Threshold: ReturnsCriticalPctOfGross,
			})
		case pct >= ReturnsWarnPctOfGross:
			alerts = append(alerts, SellInReturnsAlert{
				Severity:  "warning",
				Code:      "return_pct",
				MessageAR: fmt.Sprintf("نسبة المرتجع من الإجمالي %.1f%% أعلى من المعتاد (حد التحذير %.0f%%).", pct, ReturnsWarnPctOfGross),
				Value:     pct,
				Threshold: ReturnsWarnPctOfGross,
			})
		}
	}

	if kpis.MomChangePct != nil && kpis.MomDirection == "up" && *kpis.MomChangePct >= ReturnsMomSpikePct {
		alerts = append(alerts, SellInReturnsAlert{
			Severity:  "warning",
			Code:      "mom_spike",
			MessageAR: fmt.Sprintf("ارتفاع المرتجعات شهرياً بنسبة %.1f%% (حد التنبيه %.0f%%).", *kpis.MomChangePct, ReturnsMomSpikePct),
			Value:     *kpis.MomChangePct,
			Threshold: ReturnsMomSpikePct,
			Context:   arabicMonthNamesReturns[kpis.FocusMonth],
		})
	}

	for _, b := range branches {
		pct := b.Total.ReturnPctOfGross
		if pct < ReturnsCriticalPctOfGross || b.Total.ReturnsValueEGP <= 0 {
			continue
		}
		alerts = append(alerts, SellInReturnsAlert{
			Severity:  "critical",
			Code:      "branch_pct",
			MessageAR: fmt.Sprintf("فرع «%s»: نسبة المرتجع %.1f%% تجاوزت الحد الحرج.", b.BranchName, pct),
			Value:     pct,
			Threshold: ReturnsCriticalPctOfGross,
			Context:   b.BranchName,
		})
	}

	for _, p := range top {
		if p.ReturnPctOfGross < ReturnsCriticalPctOfGross || p.ReturnsValueEGP <= 0 {
			continue
		}
		// Skip products with no gross (return-only) for rate alerts — already covered by advisories.
		if p.GrossValueEGP <= 0 {
			continue
		}
		alerts = append(alerts, SellInReturnsAlert{
			Severity:  "warning",
			Code:      "product_pct",
			MessageAR: fmt.Sprintf("الصنف «%s»: نسبة مرتجع %.1f%% أعلى من المعتاد.", p.ProductName, p.ReturnPctOfGross),
			Value:     p.ReturnPctOfGross,
			Threshold: ReturnsCriticalPctOfGross,
			Context:   p.ProductName,
		})
	}

	sort.Slice(alerts, func(i, j int) bool {
		sev := map[string]int{"critical": 0, "warning": 1}
		if sev[alerts[i].Severity] != sev[alerts[j].Severity] {
			return sev[alerts[i].Severity] < sev[alerts[j].Severity]
		}
		if alerts[i].Value != alerts[j].Value {
			return alerts[i].Value > alerts[j].Value
		}
		return alerts[i].Code < alerts[j].Code
	})
	// Cap noise: keep the strongest handful for the page banner.
	if len(alerts) > 12 {
		alerts = alerts[:12]
	}
	return alerts
}

func sortedInts(m map[int]bool) []int {
	out := make([]int, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Ints(out)
	return out
}

func sortedStrings(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

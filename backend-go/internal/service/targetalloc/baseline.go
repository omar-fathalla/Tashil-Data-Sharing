// Package targetalloc distributes a Sell-Out target over branches and SKUs in proportion to a
// historical baseline. It is pure (no I/O): BigQuery (or the in-memory store) supplies grouped rows.
package targetalloc

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Row is one Sell-Out aggregate at (branch, SKU, category, SKU name) grain, summed over the
// baseline window and the target's actual window. Revenue is net revenue (net_revenue).
type Row struct {
	StoreKey       string
	StoreID        string
	StoreName      string
	SKUKey         string
	SKUName        string
	Category       string
	UnitsPerCarton int64
	BaseRev        float64
	BaseUnits      int64
	ActRev         float64
	ActUnits       int64
	ActRows        int64
}

// MonthCoverage tells how many Sell-Out rows exist for one calendar month ("YYYY-MM") in the target's chain.
type MonthCoverage struct {
	Month string
	Rows  int64
}

// Window is an inclusive date range ("YYYY-MM-DD").
type Window struct {
	Start string
	End   string
}

// Valid reports whether both ends are set.
func (w Window) Valid() bool { return w.Start != "" && w.End != "" }

// Baseline kinds.
const (
	KindPriorYearMonth = "prior_year_month"
	KindPriorYear      = "prior_year"
	KindTrailing12M    = "trailing_12m"
	KindNone           = "none"
)

// Baseline is the resolved historical window.
type Baseline struct {
	Kind          string
	Year          int
	Window        Window
	MonthsCovered int
	Partial       bool
	FallbackUsed  bool
	months        []string
	asked         int
}

var arabicMonths = []string{
	"", "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
	"يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
}

// MonthNameAr returns the Arabic name of month 1..12.
func MonthNameAr(m int) string {
	if m < 1 || m > 12 {
		return ""
	}
	return arabicMonths[m]
}

func monthStart(y, m int) string { return fmt.Sprintf("%04d-%02d-01", y, m) }

func monthEnd(y, m int) string {
	last := time.Date(y, time.Month(m)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	return fmt.Sprintf("%04d-%02d-%02d", y, m, last)
}

func parseYM(s string) (int, int, bool) {
	if len(s) < 7 || s[4] != '-' {
		return 0, 0, false
	}
	y, err1 := strconv.Atoi(s[:4])
	m, err2 := strconv.Atoi(s[5:7])
	if err1 != nil || err2 != nil || y < 1900 || m < 1 || m > 12 {
		return 0, 0, false
	}
	return y, m, true
}

// ActualWindow is the period the target is measured on: the month for monthly targets, else the year.
func ActualWindow(year, month int) Window {
	if month >= 1 && month <= 12 {
		return Window{Start: monthStart(year, month), End: monthEnd(year, month)}
	}
	return Window{Start: monthStart(year, 1), End: monthEnd(year, 12)}
}

// ResolveBaseline picks the historical window for a target of (year, month; 0 = full year):
//  1. monthly target: the same month of the prior year, if it has data;
//  2. otherwise the whole prior year (year-1), if it has any data (partial years are flagged);
//  3. otherwise the latest 12 months that exist in the data (fallback, flagged).
//
// coverage lists months that have rows for the target's chain.
func ResolveBaseline(year, month int, coverage []MonthCoverage) Baseline {
	var all []string
	byYear := map[int][]int{}
	for _, c := range coverage {
		y, m, ok := parseYM(c.Month)
		if !ok || c.Rows <= 0 {
			continue
		}
		all = append(all, c.Month[:7])
		byYear[y] = append(byYear[y], m)
	}
	sort.Strings(all)
	all = dedupe(all)
	prior := year - 1

	if month >= 1 && month <= 12 {
		for _, m := range byYear[prior] {
			if m == month {
				return Baseline{
					Kind: KindPriorYearMonth, Year: prior,
					Window:        Window{Start: monthStart(prior, month), End: monthEnd(prior, month)},
					MonthsCovered: 1, months: []string{fmt.Sprintf("%04d-%02d", prior, month)}, asked: month,
				}
			}
		}
	}
	if ms := byYear[prior]; len(ms) > 0 {
		sort.Ints(ms)
		ms = dedupeInts(ms)
		months := make([]string, len(ms))
		for i, m := range ms {
			months[i] = fmt.Sprintf("%04d-%02d", prior, m)
		}
		return Baseline{
			Kind: KindPriorYear, Year: prior,
			Window:        Window{Start: monthStart(prior, 1), End: monthEnd(prior, 12)},
			MonthsCovered: len(ms), Partial: len(ms) < 12,
			FallbackUsed: month >= 1 && month <= 12, months: months, asked: month,
		}
	}
	if len(all) == 0 {
		return Baseline{Kind: KindNone}
	}
	ly, lm, _ := parseYM(all[len(all)-1])
	sy, sm := ly, lm-11
	for sm < 1 {
		sm += 12
		sy--
	}
	start := monthStart(sy, sm)
	end := monthEnd(ly, lm)
	var months []string
	for _, ym := range all {
		if ym+"-01" >= start && ym+"-01" <= end {
			months = append(months, ym)
		}
	}
	return Baseline{
		Kind: KindTrailing12M, Year: 0, Window: Window{Start: start, End: end},
		MonthsCovered: len(months), Partial: len(months) < 12, FallbackUsed: true, months: months, asked: month,
	}
}

func dedupe(in []string) []string {
	out := in[:0]
	for i, s := range in {
		if i == 0 || s != in[i-1] {
			out = append(out, s)
		}
	}
	return out
}

func dedupeInts(in []int) []int {
	out := in[:0]
	for i, s := range in {
		if i == 0 || s != in[i-1] {
			out = append(out, s)
		}
	}
	return out
}

func rangeLabelAr(months []string) string {
	if len(months) == 0 {
		return ""
	}
	fy, fm, _ := parseYM(months[0])
	ly, lm, _ := parseYM(months[len(months)-1])
	if fy == ly {
		if fm == lm {
			return fmt.Sprintf("%s %d", MonthNameAr(fm), fy)
		}
		return fmt.Sprintf("%s – %s %d", MonthNameAr(fm), MonthNameAr(lm), fy)
	}
	return fmt.Sprintf("%s %d – %s %d", MonthNameAr(fm), fy, MonthNameAr(lm), ly)
}

// CaptionAr explains the allocation method and baseline period in Arabic.
func (b Baseline) CaptionAr() string {
	const method = "التوزيع حسب حصة كل فرع وصنف من "
	switch b.Kind {
	case KindPriorYearMonth:
		return fmt.Sprintf("%sمبيعات %s %d.", method, MonthNameAr(b.asked), b.Year)
	case KindPriorYear:
		var sb strings.Builder
		if b.FallbackUsed {
			fmt.Fprintf(&sb, "لا توجد مبيعات في %s %d؛ ", MonthNameAr(b.asked), b.Year)
		}
		fmt.Fprintf(&sb, "%sمبيعات %d", method, b.Year)
		if b.Partial {
			fmt.Fprintf(&sb, " (%d %s فقط: %s)", b.MonthsCovered, monthsWord(b.MonthsCovered), rangeLabelAr(b.months))
		}
		sb.WriteString(".")
		return sb.String()
	case KindTrailing12M:
		n := b.MonthsCovered
		span := "آخر 12 شهرًا متاحة"
		if n < 12 {
			span = fmt.Sprintf("آخر %d %s متاحة", n, monthsWord(n))
		}
		return fmt.Sprintf("لا توجد مبيعات في العام السابق؛ %s%s (%s).", method, span, rangeLabelAr(b.months))
	default:
		return "لا توجد مبيعات سابقة لتوزيع المستهدف."
	}
}

func monthsWord(n int) string {
	if n >= 3 && n <= 10 {
		return "أشهر"
	}
	return "شهرًا"
}

package gemini

import (
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// SellInParseReport describes how a Sell-In file was read.
type SellInParseReport struct {
	Layout     string         `json:"layout"`
	HeaderRow  int            `json:"header_row"` // 1-based
	Columns    map[string]int `json:"columns,omitempty"`
	MonthCheck string         `json:"month_check,omitempty"`
	ReturnRows int            `json:"return_rows,omitempty"`
}

// SellInLayoutError: required headers were not found, so nothing is read by position.
type SellInLayoutError struct {
	Filename string
	Missing  []string
}

func (e *SellInLayoutError) Error() string {
	return fmt.Sprintf("شكل الملف %s اتغير: الأعمدة المطلوبة دي مش موجودة: %s. الأعمدة بتتقري بأسمائها مش بمكانها، فصحح عناوين الأعمدة وارفع الملف تاني.",
		e.Filename, strings.Join(e.Missing, "، "))
}

// SellInChainRequiredError: a GP SOP export was uploaded without a chain ("", "all", "الكل"). The file
// has no chain column, so it is rejected instead of defaulting to fathalla.
type SellInChainRequiredError struct {
	Filename string
}

func (e *SellInChainRequiredError) Error() string {
	return fmt.Sprintf("الملف %s مفيهوش عمود للسلسلة، فلازم تختار السلسلة اللي الملف ده تبعها (مش «الكل») وترفعه تاني. مفيش حاجة اتحفظت.", e.Filename)
}

// SellInPeriodError: some rows have no readable month or year. The file is rejected as a whole.
type SellInPeriodError struct {
	Filename     string
	BadMonthRows int
	MonthSamples []string
	NoYearRows   int
	ConflictRows int
	FirstRows    []int
}

func (e *SellInPeriodError) Error() string {
	var parts []string
	if e.BadMonthRows > 0 {
		parts = append(parts, fmt.Sprintf("%d صف الشهر فيه مش مفهوم (زي: %s)", e.BadMonthRows, strings.Join(e.MonthSamples, "، ")))
	}
	if e.NoYearRows > 0 {
		parts = append(parts, fmt.Sprintf("%d صف من غير سنة، ومفيش سنة واضحة في التاريخ أو اسم الملف", e.NoYearRows))
	}
	if e.ConflictRows > 0 {
		parts = append(parts, fmt.Sprintf("%d صف رقم الشهر فيه مختلف عن اسم الشهر", e.ConflictRows))
	}
	rows := make([]string, 0, len(e.FirstRows))
	for _, r := range e.FirstRows {
		rows = append(rows, fmt.Sprint(r))
	}
	return fmt.Sprintf("الملف %s اترفض ومفيش حاجة اتحفظت: %s. أول صفوف فيها المشكلة: %s. اكتب الشهر (رقم 1–12 أو اسمه) والسنة في كل صف وارفع الملف تاني.",
		e.Filename, strings.Join(parts, "؛ "), strings.Join(rows, "، "))
}

type sellInPeriodResolver struct {
	fileYear int
	pending  string // failure reason for the current row
	sample   string
	perr     SellInPeriodError
	samples  map[string]bool
}

func newSellInPeriodResolver(fileYear int) *sellInPeriodResolver {
	return &sellInPeriodResolver{fileYear: fileYear, samples: map[string]bool{}}
}

func (p *sellInPeriodResolver) startRow() { p.pending, p.sample = "", "" }

// resolve reads (year, month) from a row. Precedence: explicit month number / name / date, explicit
// year, then a year carried by the date, then a year written in the filename. Never a default.
func (p *sellInPeriodResolver) resolve(row int, yearRaw, monthNumRaw, monthNameRaw, dateRaw string) (int, int, bool) {
	month, tokYear := 0, 0
	var fromNum, fromName int
	if strings.TrimSpace(monthNumRaw) != "" {
		if m, y, ok := ParseMonthToken(monthNumRaw); ok {
			fromNum, tokYear = m, y
		} else {
			p.pending, p.sample = "month", monthNumRaw
			return 0, 0, false
		}
	}
	if strings.TrimSpace(monthNameRaw) != "" {
		if m, y, ok := ParseMonthToken(monthNameRaw); ok {
			fromName = m
			if tokYear == 0 {
				tokYear = y
			}
		} else if fromNum == 0 {
			p.pending, p.sample = "month", monthNameRaw
			return 0, 0, false
		}
	}
	if fromNum > 0 && fromName > 0 && fromNum != fromName {
		p.pending = "conflict"
		return 0, 0, false
	}
	month = fromNum
	if month == 0 {
		month = fromName
	}
	if strings.TrimSpace(dateRaw) != "" {
		if y, m, ok := ParseDateToken(dateRaw); ok {
			if month == 0 {
				month = m
			}
			if tokYear == 0 {
				tokYear = y
			}
		}
	}
	if month == 0 {
		p.pending, p.sample = "month", strings.TrimSpace(monthNameRaw+monthNumRaw+dateRaw)
		if p.sample == "" {
			p.sample = "(فاضي)"
		}
		return 0, 0, false
	}
	year := 0
	if strings.TrimSpace(yearRaw) != "" {
		y, ok := ParseYearToken(yearRaw)
		if !ok {
			p.pending = "year"
			return 0, 0, false
		}
		year = y
	}
	if year == 0 {
		year = tokYear
	}
	if year == 0 {
		year = p.fileYear
	}
	if year == 0 {
		p.pending = "year"
		return 0, 0, false
	}
	return year, month, true
}

// accept records the current row's failure (if any) and reports whether the row is usable.
func (p *sellInPeriodResolver) accept(row int) bool {
	if p.pending == "" {
		return true
	}
	switch p.pending {
	case "month":
		p.perr.BadMonthRows++
		if s := strings.TrimSpace(p.sample); s != "" && !p.samples[s] && len(p.perr.MonthSamples) < 5 {
			p.samples[s] = true
			p.perr.MonthSamples = append(p.perr.MonthSamples, s)
		}
	case "year":
		p.perr.NoYearRows++
	case "conflict":
		p.perr.ConflictRows++
	}
	if len(p.perr.FirstRows) < 5 {
		p.perr.FirstRows = append(p.perr.FirstRows, row)
	}
	p.pending = ""
	return false
}

func (p *sellInPeriodResolver) err(filename string) error {
	if p.perr.BadMonthRows+p.perr.NoYearRows+p.perr.ConflictRows == 0 {
		return nil
	}
	e := p.perr
	e.Filename = filename
	return &e
}

func normalizeHeaderLabel(h string) string {
	h = strings.ToLower(strings.TrimSpace(normalizeArabicDigitsToASCII(h)))
	h = strings.NewReplacer("أ", "ا", "إ", "ا", "آ", "ا", "ة", "ه", "ى", "ي", "_", " ").Replace(h)
	h = strings.TrimRight(h, ".:")
	return strings.Join(strings.Fields(h), " ")
}

type headerSpec struct {
	key      string
	required bool
	labels   []string
}

func mapHeaders(header []string, specs []headerSpec) (map[string]int, []string) {
	idx := map[string]int{}
	norm := make([]string, len(header))
	for i, h := range header {
		norm[i] = normalizeHeaderLabel(h)
	}
	used := map[int]bool{}
	var missing []string
	for _, sp := range specs {
		idx[sp.key] = -1
		for _, l := range sp.labels {
			nl := normalizeHeaderLabel(l)
			for i, h := range norm {
				if !used[i] && h == nl {
					idx[sp.key] = i
					used[i] = true
					break
				}
			}
			if idx[sp.key] >= 0 {
				break
			}
		}
		if idx[sp.key] < 0 && sp.required {
			missing = append(missing, sp.labels[0])
		}
	}
	return idx, missing
}

// Raw "plan 10 aswak" layout, located by header names (was fixed positions 0..28).
var rawPlanHeaderSpecs = []headerSpec{
	{"month", true, []string{"month", "الشهر", "شهر"}},
	{"net_q", true, []string{"net Q", "net qty", "صافي الكميه"}},
	{"net_v", true, []string{"net V", "net value", "صافي القيمه"}},
	{"customer", true, []string{"customer", "العميل", "اسم العميل"}},
	{"item_name", true, []string{"item 1", "item name", "اسم الصنف"}},
	{"year", false, []string{"Year", "السنه"}},
	{"region", false, []string{"branch", "region"}},
	{"sector", false, []string{"sector", "القطاع"}},
	{"sub_sector", false, []string{"sub- sector", "sub-sector", "sub sector"}},
	{"division", false, []string{"7", "division"}},
	{"parent_account_code", false, []string{"6", "parent account code"}},
	{"parent_customer", false, []string{"5", "parent customer"}},
	{"item_group", false, []string{"item 2", "item group"}},
	{"sub_category", false, []string{"item 5", "sub category"}},
	{"product_family", false, []string{"item 3", "product family"}},
	{"brand", false, []string{"item 4", "brand"}},
	{"period_week", false, []string{"\\", "week", "period"}},
	{"ton", false, []string{"Ton", "tons"}},
	{"city", false, []string{"city", "المحافظه"}},
	{"branch_code", false, []string{"exp city", "branch code"}},
	{"sales_rep", false, []string{"10", "sales rep"}},
	{"promotion", false, []string{"Promotion"}},
	{"officer", false, []string{"officer"}},
	{"officer_mgr", false, []string{"officer mgr"}},
	{"turnover", false, []string{"t.o", "to", "turnover"}},
	{"q_exp", false, []string{"Q EXP", "q exp"}},
	{"v_exp", false, []string{"V EXP", "v exp"}},
}

func buildRawPlanHeaderMap(header []string) (map[string]int, []string) {
	return mapHeaders(header, rawPlanHeaderSpecs)
}

// GP / Dynamics "SOP" invoice export (in25.xlsx / in26.xlsx).
var gpSOPHeaderSpecs = []headerSpec{
	{"date", true, []string{"Document Date", "doc date", "invoice date", "تاريخ المستند", "تاريخ الفاتوره"}},
	{"item_code", true, []string{"Item Number", "item code", "كود الصنف"}},
	{"customer", true, []string{"Customer Name", "اسم العميل"}},
	// Served Sell-In has always used the invoice line (QTY, Extended Price). Net Q / TO are read
	// for the report only so existing totals do not move; switching is an open decision.
	{"qty", true, []string{"QTY", "quantity", "الكميه"}},
	{"value", true, []string{"Extended Price", "ext price", "قيمه الفاتوره"}},
	{"net_q", false, []string{"Net Q", "net qty", "صافي الكميه"}},
	{"net_to", false, []string{"TO", "t.o", "net value", "صافي القيمه"}},
	{"item_name", false, []string{"Item Description", "item name", "اسم الصنف"}},
	{"uom", false, []string{"U Of M", "uom"}},
	{"units_per_carton", false, []string{"U of M2", "units per carton"}},
	{"customer_number", false, []string{"Customer Number", "رقم العميل"}},
	{"customer_class", false, []string{"Customer Class"}},
	{"branch", false, []string{"Branch", "الفرع"}},
	{"statement", false, []string{"Statement Name"}},
	{"salesman", false, []string{"SalesManNo", "salesman"}},
	{"sop_type", false, []string{"SOP Type"}},
	{"month", false, []string{"month", "الشهر"}},
	{"week", false, []string{"week", "الاسبوع"}},
}

func findGPSOPHeaderRow(rows [][]string) int {
	for i := 0; i < len(rows) && i < 15; i++ {
		joined := normalizeHeaderLabel(strings.Join(rows[i], " | "))
		if strings.Contains(joined, "sop number") && strings.Contains(joined, "customer name") {
			return i
		}
	}
	return -1
}

func parseGPSOPExport(tenantID, filename string, rows [][]string, hdr int, chain string, report *SellInParseReport) ([]domain.SellInRecord, error) {
	cols, missing := mapHeaders(rows[hdr], gpSOPHeaderSpecs)
	if len(missing) > 0 {
		return nil, &SellInLayoutError{Filename: filename, Missing: missing}
	}
	report.HeaderRow = hdr + 1
	report.Columns = cols
	fileYear, _ := YearFromFilename(filename)
	periods := newSellInPeriodResolver(fileYear)
	now := time.Now().UTC()
	out := make([]domain.SellInRecord, 0, len(rows)-hdr-1)
	monthMismatch := 0
	seen := map[string]int{}
	for i := hdr + 1; i < len(rows); i++ {
		r := rows[i]
		if len(r) == 0 || strings.TrimSpace(getCol(r, cols["item_code"])) == "" && strings.TrimSpace(getCol(r, cols["value"])) == "" {
			continue
		}
		periods.startRow()
		// The invoice date is authoritative; the "month" column is a lookup that is often #N/A.
		y, m, _ := periods.resolve(i+1, "", "", "", getCol(r, cols["date"]))
		if !periods.accept(i + 1) {
			continue
		}
		if mc, _, ok := ParseMonthToken(getCol(r, cols["month"])); ok && mc != m {
			monthMismatch++
		}
		qty := math.Round(parseFloatDefault(getCol(r, cols["qty"]), 0)) // served Sell-In has always stored whole units per line
		val := parseFloatDefault(getCol(r, cols["value"]), 0)
		cust := strings.TrimSpace(getCol(r, cols["customer"]))
		st := BuildBranchStoreMetadata(chain, cust)
		tx := "مسحوبات بيع (Sale)"
		if qty < 0 || val < 0 {
			tx = "مرتجع (Return)"
		}
		if strings.EqualFold(strings.TrimSpace(getCol(r, cols["sop_type"])), "return") {
			report.ReturnRows++
		}
		key := st.ID + "|" + strings.TrimSpace(getCol(r, cols["item_code"])) + "|" + strings.TrimSpace(getCol(r, cols["date"]))
		if j, ok := seen[key]; ok {
			out[j].NetQtyCases += qty
			out[j].NetValueEGP = math.Round((out[j].NetValueEGP+val)*100) / 100
			out[j].TurnoverEGP = out[j].NetValueEGP
			out[j].ExpectedQtyCases = out[j].NetQtyCases
			out[j].ExpectedValueEGP = out[j].NetValueEGP
			out[j].WeightTons = math.Round(math.Abs(out[j].NetQtyCases)*0.012*10000) / 10000
			continue
		}
		seen[key] = len(out)
		rec := domain.SellInRecord{
			RecordID:           fmt.Sprintf("sellin_%s_%d", tenantID, i),
			TenantID:           tenantID,
			RetailerChain:      chain,
			Year:               y,
			MonthNum:           m,
			MonthEN:            monthNumToEN(m),
			MonthAR:            ArabicMonthName(m),
			PeriodWeek:         "Full Month",
			RegionCode:         "ALX", // as served since in25/in26 were first loaded; the Branch column is an open decision
			Governorate:        st.Governorate,
			Sector:             "MT",
			CustomerName:       gpSOPCustomerName(cust, st.BranchName),
			CustomerBranchCode: st.ID,
			ItemGroup:          strings.TrimSpace(getCol(r, cols["item_code"])),
			ItemName:           strings.TrimSpace(getCol(r, cols["item_name"])),
			PromotionType:      "عادي",
			SalesRep:           "فريق مبيعات السلاسل",
			NetQtyCases:        qty,
			NetValueEGP:        val,
			TurnoverEGP:        val,
			WeightTons:         math.Round(math.Abs(qty)*0.012*10000) / 10000,
			ExpectedQtyCases:   qty,
			ExpectedValueEGP:   val,
			TransactionType:    tx,
			IngestedAt:         now,
		}
		out = append(out, rec)
	}
	if err := periods.err(filename); err != nil {
		return nil, err
	}
	if monthMismatch > 0 {
		report.MonthCheck = fmt.Sprintf("%d صف عمود الشهر فيه مختلف عن تاريخ الفاتورة؛ اتاخد تاريخ الفاتورة", monthMismatch)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no valid sell-in records found in %s", filename)
	}
	return out, nil
}

// MonthNumToEN returns "Jan".."Dec" (exported for the ingestion package).
func MonthNumToEN(m int) string { return monthNumToEN(m) }

// gpSOPCustomerName is the customer as written in the file (same spelling the other layouts store),
// not the store label «فرع <chain> - …», so one customer has one name across layouts. Names that were
// already approved under the old label map back to it via customers/seed_aliases.json (item 7).
func gpSOPCustomerName(raw, branchLabel string) string {
	if strings.TrimSpace(raw) == "" {
		return branchLabel
	}
	return strings.TrimSpace(raw)
}

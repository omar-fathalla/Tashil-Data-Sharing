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
	// QtyUOMFallbackRows is the number of piece-UOM lines with no U of M2,
	// so Product Master UnitsPerCarton will be used at enrich time (if present).
	QtyUOMFallbackRows int `json:"qty_uom_fallback_rows,omitempty"`
	// NoBranchRows is the number of rows whose branch could not be read (no branch code / branch name
	// column value, no «<customer> - <branch>» store). They are shown as «غير محدد الفرع».
	NoBranchRows int `json:"no_branch_rows,omitempty"`
}

// SellInNoBranchPlaceholder is the label older raw-plan parses stored as the customer branch code when
// the row's branch column was empty. It names no branch.
const SellInNoBranchPlaceholder = "مجمع الإقليم (Regional)"

// IsSellInNoBranchPlaceholder reports whether a stored customer branch code is the legacy no-branch label.
func IsSellInNoBranchPlaceholder(code string) bool {
	c := normalizeHeaderLabel(code)
	return c == normalizeHeaderLabel(SellInNoBranchPlaceholder) || c == normalizeHeaderLabel("مجمع الإقليم")
}

// rawPlanBranchCode reads a raw ERP plan row's branch: the branch code column, else the store id of the
// branch name column, else the store of a «<customer> - <branch>» customer cell. Only labels the branch
// dictionary knows become store ids (no fuzzy guess); "" when the row names no branch.
func rawPlanBranchCode(chain, code, name, customer string) string {
	if c := strings.TrimSpace(code); c != "" && !IsSellInNoBranchPlaceholder(c) {
		return c
	}
	if n := collapseSpace(name); n != "" && !IsSellInNoBranchPlaceholder(n) {
		if st := BuildBranchStoreMetadata(chain, n); isKnownStoreID(st.ID) {
			return st.ID
		}
		return n
	}
	if _, branch := ParseChainBranchCell(customer); branch != "" && branch != collapseSpace(customer) {
		if st := BuildBranchStoreMetadata(chain, branch); isKnownStoreID(st.ID) {
			return st.ID
		}
	}
	return ""
}

func isKnownStoreID(id string) bool {
	return id != "" && !strings.Contains(id, "_auto_") && !strings.HasSuffix(id, "_unallocated")
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

// sellInYearSource records where resolve got the calendar year so cycle nudges only apply
// when the year came from Document Date (not "Jan-25" / filename / explicit year column).
type sellInYearSource int

const (
	sellInYearNone sellInYearSource = iota
	sellInYearExplicit
	sellInYearMonthToken
	sellInYearDate
	sellInYearFilename
)

type sellInPeriodResolver struct {
	fileYear   int
	pending    string // failure reason for the current row
	sample     string
	yearSource sellInYearSource
	perr       SellInPeriodError
	samples    map[string]bool
}

func newSellInPeriodResolver(fileYear int) *sellInPeriodResolver {
	return &sellInPeriodResolver{fileYear: fileYear, samples: map[string]bool{}}
}

func (p *sellInPeriodResolver) startRow() {
	p.pending, p.sample, p.yearSource = "", "", sellInYearNone
}

// resolve reads (year, month) from a row. Precedence: explicit month number / name / date, explicit
// year, then a year carried by the month token, then Document Date, then a year written in the
// filename. Never a default. yearSource is set for the successful path.
func (p *sellInPeriodResolver) resolve(row int, yearRaw, monthNumRaw, monthNameRaw, dateRaw string) (int, int, bool) {
	month, monthTokYear, dateYear := 0, 0, 0
	var fromNum, fromName int
	if strings.TrimSpace(monthNumRaw) != "" {
		if m, y, ok := ParseMonthToken(monthNumRaw); ok {
			fromNum, monthTokYear = m, y
		} else {
			p.pending, p.sample = "month", monthNumRaw
			return 0, 0, false
		}
	}
	if strings.TrimSpace(monthNameRaw) != "" {
		if m, y, ok := ParseMonthToken(monthNameRaw); ok {
			fromName = m
			if monthTokYear == 0 {
				monthTokYear = y
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
			dateYear = y
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
		p.yearSource = sellInYearExplicit
	}
	if year == 0 && monthTokYear > 0 {
		year = monthTokYear
		p.yearSource = sellInYearMonthToken
	}
	if year == 0 && dateYear > 0 {
		year = dateYear
		p.yearSource = sellInYearDate
	}
	if year == 0 && p.fileYear > 0 {
		year = p.fileYear
		p.yearSource = sellInYearFilename
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
	h = strings.ToLower(strings.TrimSpace(normalizeArabicDigitsToASCII(normalizeInvisibleSpaces(h))))
	h = strings.NewReplacer("أ", "ا", "إ", "ا", "آ", "ا", "ة", "ه", "ى", "ي", "_", " ", ".", " ").Replace(h)
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
		// Soft match for value/qty aliases (Dynamics renames: "ExtendedPrice", "Ext. Price (EGP)",
		// "XTNDPRCE"). Exact match stays first. Short aliases like "TO"/"to" are exact-or-compact
		// only — never substring — so a "Total" column cannot steal the value role.
		if idx[sp.key] < 0 && (sp.key == "value" || sp.key == "qty") {
			for _, l := range sp.labels {
				nl := normalizeHeaderLabel(l)
				if nl == "" {
					continue
				}
				compactNL := strings.ReplaceAll(nl, " ", "")
				for i, h := range norm {
					if used[i] || h == "" {
						continue
					}
					compactH := strings.ReplaceAll(h, " ", "")
					match := h == nl || compactH == compactNL
					if !match && len(nl) >= 4 && (strings.Contains(h, nl) || strings.Contains(compactH, compactNL)) {
						match = true
					}
					if match {
						idx[sp.key] = i
						used[i] = true
						break
					}
				}
				if idx[sp.key] >= 0 {
					break
				}
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
	{"branch_code", false, []string{"exp city", "branch code", "customer branch code", "ship to code", "ship-to code", "store code", "كود الفرع", "كود فرع العميل"}},
	{"branch_name", false, []string{"customer branch", "customer branch name", "branch name", "ship to", "ship to name", "ship-to", "ship-to name", "store", "store name", "اسم الفرع", "فرع العميل"}},
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
// in26 has no "Extended Price"; sales amount is the TO (turnover) column. Extended Price
// aliases are tried first so older exports keep their previous totals; TO is a synonym
// applied during mapping, and the required-column check runs after that mapping.
var gpSOPHeaderSpecs = []headerSpec{
	{"date", true, []string{"Document Date", "doc date", "invoice date", "تاريخ المستند", "تاريخ الفاتوره"}},
	{"item_code", true, []string{"Item Number", "item code", "كود الصنف"}},
	{"customer", true, []string{"Customer Name", "اسم العميل"}},
	{"qty", true, []string{"QTY", "quantity", "الكميه"}},
	{"value", true, []string{
		"Extended Price", "ext price", "ext. price", "extendedprice", "xtndprce",
		"extended price egp", "line extended price", "قيمه الفاتوره", "القيمه الممتده", "قيمة ممتدة",
		// in26 synonym — after Extended Price so classic exports still prefer Extended Price.
		"TO", "t.o", "turnover",
	}},
	{"net_q", false, []string{"Net Q", "net qty", "صافي الكميه"}},
	{"net_to", false, []string{"net value", "صافي القيمه"}},
	{"item_name", false, []string{"Item Description", "item name", "اسم الصنف"}},
	{"uom", false, []string{"U Of M", "uom"}},
	{"units_per_carton", false, []string{"U of M2", "units per carton"}},
	{"customer_number", false, []string{"Customer Number", "رقم العميل"}},
	{"customer_class", false, []string{"Customer Class"}},
	// Branch in in26 is a region code (ALX/BHR/…), NOT the store branch — store is Customer Name.
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

// adjustCycleYear fixes year-boundary sales cycles only when the year came from Document Date:
// a Jan cycle that starts in late December belongs to the next calendar year; a Dec cycle that
// spills into early January belongs to the previous year. Years from month tokens (e.g. "Jan-25"),
// an explicit year column, or the filename are left unchanged.
func adjustCycleYear(resolvedYear, docMonth, cycleMonth int, yearFromDocDate bool) int {
	if !yearFromDocDate || resolvedYear <= 0 || cycleMonth < 1 || cycleMonth > 12 {
		return resolvedYear
	}
	if cycleMonth == 1 && docMonth == 12 {
		return resolvedYear + 1
	}
	if cycleMonth == 12 && docMonth == 1 {
		return resolvedYear - 1
	}
	return resolvedYear
}

func parseGPSOPExport(tenantID, filename string, rows [][]string, hdr int, chain string, report *SellInParseReport) ([]domain.SellInRecord, error) {
	// Map synonyms first (Extended Price, then TO, …); required-column check runs after mapping.
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
	monthFromColUsed := 0
	monthMismatch := 0
	monthUnparseable := 0
	hasMonthCol := cols["month"] >= 0
	// Store branch lives in Customer Name (full-column scan). The "Branch" column is region codes.
	storeCol := cols["customer"]
	dataRows := rows[hdr+1:]
	applySectionHeaderStoreFill(dataRows, storeCol, cols["item_code"], cols["qty"], cols["value"])
	for i := hdr + 1; i < len(rows); i++ {
		r := rows[i]
		if len(r) == 0 || strings.TrimSpace(getCol(r, cols["item_code"])) == "" && strings.TrimSpace(getCol(r, cols["value"])) == "" {
			continue
		}
		periods.startRow()
		dateRaw := getCol(r, cols["date"])
		// Company sales-month cycle lives in the month column (JAN/Feb/…, Arabic names). Prefer it
		// over Document Date. Unparseable / #N/A / empty month cells fall back to Document Date.
		// When the file has no month column at all, Document Date alone drives period_month.
		monthRaw := ""
		usedMonthCol := false
		if hasMonthCol {
			cell := getCol(r, cols["month"])
			trimmed := strings.TrimSpace(cell)
			if _, _, ok := ParseMonthToken(cell); ok {
				monthRaw = cell
				usedMonthCol = true
			} else if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
				// Empty / #N/A fall back silently; other garbage is noted in MonthCheck.
				monthUnparseable++
			}
		}
		y, m, _ := periods.resolve(i+1, "", "", monthRaw, dateRaw)
		if !periods.accept(i + 1) {
			continue
		}
		if usedMonthCol {
			monthFromColUsed++
			if _, dm, ok := ParseDateToken(dateRaw); ok {
				y = adjustCycleYear(y, dm, m, periods.yearSource == sellInYearDate)
				if dm != m {
					monthMismatch++
				}
			}
		}
		rawQty := math.Round(parseFloatDefault(getCol(r, cols["qty"]), 0))
		uom := ""
		if idx, ok := cols["uom"]; ok {
			uom = getCol(r, idx)
		}
		uom2 := 0.0
		if idx, ok := cols["units_per_carton"]; ok {
			uom2 = parseFloatDefault(getCol(r, idx), 0)
		}
		qty, upcFromFile, usedFallback := ConvertSOPQtyToCases(rawQty, uom2, 0, uom)
		if usedFallback || (isPieceUOM(uom) && uom2 < 1) {
			report.QtyUOMFallbackRows++
		}
		val := parseFloatDefault(getCol(r, cols["value"]), 0) // Extended Price or TO; keep sign (returns negative)
		// Collapse whitespace around the chain/branch dash (… -  فلمنج) but keep the upload chain
		// authoritative — never re-infer retailer from the customer label (zahran/gomla GP SOP).
		cust := collapseSpace(getCol(r, cols["customer"]))
		_, branchLabel := ParseChainBranchCell(cust)
		if branchLabel == "" {
			branchLabel = cust
		}
		// Geo / known-slug from the branch side (دمنهور - الاستاد ≠ دمنهور); identity from the
		// full Customer Name so "مواد عناية" accounts stay distinct (56 names in in26).
		geo := BuildBranchStoreMetadata(chain, branchLabel)
		ident := BuildBranchStoreMetadata(chain, cust)
		st := geo
		st.ID = ident.ID
		region := strings.ToUpper(strings.TrimSpace(getCol(r, cols["branch"])))
		if region == "" {
			region = "ALX"
		}
		tx := "مسحوبات بيع (Sale)"
		if qty < 0 || val < 0 {
			tx = "مرتجع (Return)"
		}
		if strings.EqualFold(strings.TrimSpace(getCol(r, cols["sop_type"])), "return") {
			report.ReturnRows++
			tx = "مرتجع (Return)"
		}
		// GP SOP week column is not period_week status (W1/W2 would flip مغلق → قيد الإغلاق).
		// Always Full Month for this layout; week stays unused by status logic.
		// One Sell-In record per source row — never collapse lines (in26 acceptance: 40927 rows).
		rec := domain.SellInRecord{
			RecordID:             fmt.Sprintf("sellin_%s_%d", tenantID, i),
			TenantID:             tenantID,
			RetailerChain:        chain,
			Year:                 y,
			MonthNum:             m,
			MonthEN:              monthNumToEN(m),
			MonthAR:              ArabicMonthName(m),
			PeriodWeek:           "Full Month",
			RegionCode:           region,
			Governorate:          st.Governorate,
			Sector:               "MT",
			CustomerName:         gpSOPCustomerName(cust, st.BranchName),
			CustomerBranchCode:   st.ID,
			ItemGroup:            strings.TrimSpace(getCol(r, cols["item_code"])),
			ItemName:             strings.TrimSpace(getCol(r, cols["item_name"])),
			PromotionType:        "عادي",
			SalesRep:             "فريق مبيعات السلاسل",
			UnitsPerCarton:       upcFromFile,
			NetQtyCases:          qty,
			NetValueEGP:          val,
			TurnoverEGP:          val,
			WeightTons:           math.Round(math.Abs(rawQty)*0.012*10000) / 10000, // weight follows the file QTY column
			ExpectedQtyCases:     qty,
			ExpectedValueEGP:     val,
			TransactionType:      tx,
			IngestedAt:           now,
			SOPQtyConverted:      !(isPieceUOM(uom) && uom2 < 1),
			SOPNeedsPackFallback: isPieceUOM(uom) && uom2 < 1,
		}
		out = append(out, rec)
	}
	if err := periods.err(filename); err != nil {
		return nil, err
	}
	var monthNotes []string
	if monthFromColUsed > 0 && monthMismatch > 0 {
		monthNotes = append(monthNotes, fmt.Sprintf("%d صف عمود الشهر فيه مختلف عن تاريخ الفاتورة؛ اتاخد عمود الشهر (دورة مبيعات الشركة)", monthMismatch))
	}
	if monthUnparseable > 0 {
		monthNotes = append(monthNotes, fmt.Sprintf("%d صف عمود الشهر فيه مش مفهوم (مش فاضي/#N/A)؛ اتاخد تاريخ الفاتورة", monthUnparseable))
	}
	if len(monthNotes) > 0 {
		report.MonthCheck = strings.Join(monthNotes, "؛ ")
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

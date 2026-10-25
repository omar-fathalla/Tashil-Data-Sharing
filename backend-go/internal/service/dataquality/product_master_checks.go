package dataquality

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Thresholds used by the Product Master checks.
const (
	ExpectedVATRate        = 0.14
	vatTolerance           = 0.0005 // absolute, on the rate (0.14 ± 0.05pp)
	vatRatioTolerance      = 0.005  // relative, on incl/excl price ratio
	MaxInvoiceDiscountRate = 0.50   // invoice discount must be within [0%, 50%]
	cartonAbsTolerance     = 0.05   // EGP
	cartonRelTolerance     = 0.005  // 0.5%
)

// TypeLabels are the Arabic names shown in the UI.
var TypeLabels = map[string]string{
	domain.DQTypeDuplicateBarcode:      "باركود مكرر لأكثر من صنف",
	domain.DQTypeMissingCode:           "كود الصنف ناقص",
	domain.DQTypeMissingBarcode:        "الباركود ناقص",
	domain.DQTypeInvalidPrice:          "سعر ناقص أو صفر أو سالب",
	domain.DQTypeCartonPriceMismatch:   "سعر الكرتونة ≠ سعر القطعة × عدد القطع",
	domain.DQTypeVATNot14:              "الضريبة ليست 14%",
	domain.DQTypeInvoiceDiscountRange:  "خصم الفاتورة خارج النطاق",
	domain.DQTypeMissingPackType:       "نوع العبوة ناقص",
	domain.DQTypeMissingUnitsPerCarton: "عدد القطع بالكرتونة ناقص أو غير صحيح",
	domain.DQTypeNACell:                "خلية خطأ (#N/A)",
	domain.DQTypeMalformedBarcode:      "باركود غير صالح",
}

// CheckResult is the outcome of checking one file.
type CheckResult struct {
	Sheet        string
	TotalRows    int
	CriticalRows int
	Issues       []domain.DataQualityIssue
}

func issueID(source, typ string, parts ...string) string {
	h := sha1.Sum([]byte(source + "|" + typ + "|" + strings.Join(parts, "|")))
	return hex.EncodeToString(h[:8])
}

func isNA(s string) bool {
	u := strings.ToUpper(strings.TrimSpace(s))
	return u == "#N/A" || u == "N/A" || u == "#NA" || strings.HasPrefix(u, "#N/A")
}

func parseNum(s string) (float64, bool) {
	s = strings.TrimSpace(strings.ReplaceAll(s, ",", ""))
	s = strings.TrimSuffix(s, "%")
	if s == "" || isNA(s) {
		return 0, false
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, false
	}
	return f, true
}

func colLetter(i int) string {
	s := ""
	for i++; i > 0; i = (i - 1) / 26 {
		s = string(rune('A'+(i-1)%26)) + s
	}
	return s
}

func fmtNum(f float64) string { return strconv.FormatFloat(math.Round(f*1000)/1000, 'f', -1, 64) }

// ValidGTIN reports whether a barcode is all digits, 8/12/13/14 long, with a valid GS1 check digit.
func ValidGTIN(b string) bool {
	switch len(b) {
	case 8, 12, 13, 14:
	default:
		return false
	}
	sum := 0
	for i := len(b) - 2; i >= 0; i-- {
		ch := b[i]
		if ch < '0' || ch > '9' {
			return false
		}
		d := int(ch - '0')
		if (len(b)-2-i)%2 == 0 {
			d *= 3
		}
		sum += d
	}
	last := b[len(b)-1]
	if last < '0' || last > '9' {
		return false
	}
	return (10-sum%10)%10 == int(last-'0')
}

// editedItems returns current master items whose checked fields differ from what the file
// itself parses to, i.e. SKUs edited in the app after the upload.
func editedItems(filename string, raw []byte, current []domain.ProductMasterItem) map[string]domain.ProductMasterItem {
	if len(current) == 0 {
		return nil
	}
	base, err := gemini.ParseProductMasterWorkbook("", filename, raw)
	if err != nil || base == nil {
		return nil
	}
	orig := map[string]domain.ProductMasterItem{}
	for _, it := range base.Items {
		orig[domain.NormalizeItemCode(it.ItemCode)] = it
	}
	out := map[string]domain.ProductMasterItem{}
	for _, it := range current {
		k := domain.NormalizeItemCode(it.ItemCode)
		o, ok := orig[k]
		if !ok {
			continue
		}
		if o.Barcode != it.Barcode || o.OfficialName != it.OfficialName || o.PackagingType != it.PackagingType ||
			o.UnitsPerCarton != it.UnitsPerCarton || o.VATRate != it.VATRate || o.InvoiceDiscountPct != it.InvoiceDiscountPct ||
			o.UnitPriceExclVAT != it.UnitPriceExclVAT || o.UnitPriceInclVAT != it.UnitPriceInclVAT ||
			o.CartonPriceExclVAT != it.CartonPriceExclVAT || o.CartonPriceInclVAT != it.CartonPriceInclVAT {
			out[k] = it
		}
	}
	return out
}

func applyEdit(r sheetRow, cm map[string]int, it domain.ProductMasterItem) sheetRow {
	cells := append([]string(nil), r.Cells...)
	errs := map[int]bool{}
	for k, v := range r.Err {
		errs[k] = v
	}
	set := func(key, v string) {
		i, ok := cm[key]
		if !ok || i < 0 {
			return
		}
		for len(cells) <= i {
			cells = append(cells, "")
		}
		cells[i] = v
		delete(errs, i)
	}
	f := func(x float64) string { return strconv.FormatFloat(x, 'f', -1, 64) }
	set("barcode", it.Barcode)
	set("official_name", it.OfficialName)
	set("packaging_type", it.PackagingType)
	set("units_per_carton", strconv.Itoa(it.UnitsPerCarton))
	set("vat_rate", f(it.VATRate))
	set("invoice_discount_pct", f(it.InvoiceDiscountPct))
	set("unit_price_excl_vat", f(it.UnitPriceExclVAT))
	set("unit_price_incl_vat", f(it.UnitPriceInclVAT))
	set("carton_price_excl_vat", f(it.CartonPriceExclVAT))
	set("carton_price_incl_vat", f(it.CartonPriceInclVAT))
	return sheetRow{Num: r.Num, Cells: cells, Err: errs}
}

// CheckProductMaster runs every Product Master check on the raw uploaded workbook.
// current (optional) is the live master; SKUs edited in the app after the upload are checked
// with their edited values, so fixing a value in the app closes its issue.
func CheckProductMaster(filename string, raw []byte, current ...domain.ProductMasterItem) (*CheckResult, error) {
	edits := editedItems(filename, raw, current)
	sheetName, rows, err := readFirstSheet(raw)
	if err != nil {
		return nil, err
	}
	hdrIdx := -1
	for i := 0; i < len(rows) && i < 12; i++ {
		j := strings.ToLower(strings.Join(rows[i].Cells, " | "))
		if (strings.Contains(j, "كود الصنف") || strings.Contains(j, "item_code")) &&
			(strings.Contains(j, "اسم الصنف") || strings.Contains(j, "official_name") || strings.Contains(j, "باركود") || strings.Contains(j, "barcode")) {
			hdrIdx = i
			break
		}
	}
	if hdrIdx < 0 {
		return nil, fmt.Errorf("could not locate Product Master header row containing 'كود الصنف'")
	}
	header := rows[hdrIdx].Cells
	cm := gemini.MapProductMasterHeaderColumns(header)
	col := func(r sheetRow, key string) (string, bool) {
		i, ok := cm[key]
		if !ok || i < 0 {
			return "", false
		}
		if i >= len(r.Cells) {
			return "", true
		}
		return strings.TrimSpace(r.Cells[i]), true
	}
	hname := func(key string) string {
		if i := cm[key]; i >= 0 && i < len(header) {
			return strings.TrimSpace(strings.ReplaceAll(header[i], "\n", " "))
		}
		return key
	}

	res := &CheckResult{Sheet: sheetName}
	src := domain.DQSourceProductMaster
	type rowInfo struct {
		num                 int
		code, barcode, name string
	}
	var infos []rowInfo
	criticalRows := map[int]bool{}
	add := func(ri rowInfo, typ, sev, column, found, expected string, idParts ...string) {
		if sev == domain.DQSeverityCritical {
			criticalRows[ri.num] = true
		}
		key := append([]string{ri.code, ri.barcode, column}, idParts...)
		if ri.code == "" && ri.barcode == "" {
			key = append(key, ri.name, strconv.Itoa(ri.num))
		}
		res.Issues = append(res.Issues, domain.DataQualityIssue{
			ID: issueID(src, typ, key...), Source: src, Type: typ, TypeLabel: TypeLabels[typ], Severity: sev,
			Sheet: sheetName, Row: ri.num, Column: column, ItemCode: ri.code, Barcode: ri.barcode, SKUName: ri.name,
			FoundValue: found, ExpectedValue: expected, SourceFile: filename,
		})
	}

	for _, r := range rows[hdrIdx+1:] {
		code, _ := col(r, "item_code")
		if it, ok := edits[domain.NormalizeItemCode(code)]; ok {
			r = applyEdit(r, cm, it)
		}
		rawBarcode, _ := col(r, "barcode")
		name, _ := col(r, "official_name")
		if strings.Contains(code, "كود الصنف") || strings.EqualFold(code, "item_code") {
			continue // repeated header
		}
		nonEmpty := 0
		for _, c := range r.Cells {
			if strings.TrimSpace(c) != "" {
				nonEmpty++
			}
		}
		if (code == "" && name == "" && rawBarcode == "") || nonEmpty < 3 {
			continue // blank / note / total line, not an SKU row
		}
		ri := rowInfo{num: r.Num, code: domain.NormalizeItemCode(code), name: name}
		if !isNA(rawBarcode) {
			ri.barcode = strings.TrimSpace(rawBarcode)
		}
		if isNA(ri.code) {
			ri.code = ""
		}
		infos = append(infos, ri)
		res.TotalRows++

		// #N/A and other Excel error cells.
		for ci, c := range r.Cells {
			if r.Err[ci] || isNA(c) {
				// A data column with #N/A is critical; an unlabeled helper/lookup column is a warning.
				h := fmt.Sprintf("عمود %s (بدون عنوان)", colLetter(ci))
				sev := domain.DQSeverityWarning
				if ci < len(header) && strings.TrimSpace(header[ci]) != "" {
					h = fmt.Sprintf("%s (عمود %s)", strings.TrimSpace(strings.ReplaceAll(header[ci], "\n", " ")), colLetter(ci))
					sev = domain.DQSeverityCritical
				}
				add(ri, domain.DQTypeNACell, sev, h, strings.TrimSpace(c), "قيمة فعلية")
			}
		}
		if ri.code == "" {
			add(ri, domain.DQTypeMissingCode, domain.DQSeverityCritical, hname("item_code"), code, "كود الصنف (مثال FGDG-0004-0001)")
		}
		if ri.barcode == "" {
			add(ri, domain.DQTypeMissingBarcode, domain.DQSeverityCritical, hname("barcode"), rawBarcode, "باركود EAN-13")
		} else if !ValidGTIN(ri.barcode) {
			add(ri, domain.DQTypeMalformedBarcode, domain.DQSeverityWarning, hname("barcode"), ri.barcode, "8/12/13/14 رقم برقم تحقق GS1 صحيح")
		}

		// Prices.
		prices := map[string]float64{}
		for _, k := range []string{"unit_price_excl_vat", "unit_price_incl_vat", "carton_price_excl_vat", "carton_price_incl_vat"} {
			v, present := col(r, k)
			if !present {
				continue
			}
			ci := cm[k]
			if r.Err[ci] || isNA(v) {
				continue // already reported as an error cell
			}
			f, ok := parseNum(v)
			if !ok || f <= 0 {
				add(ri, domain.DQTypeInvalidPrice, domain.DQSeverityCritical, hname(k), v, "سعر موجب")
				continue
			}
			prices[k] = f
		}

		// Units per carton.
		upc := 0
		if v, present := col(r, "units_per_carton"); present && !r.Err[cm["units_per_carton"]] && !isNA(v) {
			f, ok := parseNum(v)
			if !ok || f <= 0 || f != math.Trunc(f) {
				add(ri, domain.DQTypeMissingUnitsPerCarton, domain.DQSeverityCritical, hname("units_per_carton"), v, "عدد صحيح موجب")
			} else {
				upc = int(f)
			}
		}
		if v, present := col(r, "packaging_type"); present && v == "" {
			add(ri, domain.DQTypeMissingPackType, domain.DQSeverityWarning, hname("packaging_type"), "", "زجاجة / جركن / عبوة / مجموعة ...")
		}

		// Carton = unit × units per carton.
		if upc > 0 {
			for _, pair := range [][2]string{{"unit_price_incl_vat", "carton_price_incl_vat"}, {"unit_price_excl_vat", "carton_price_excl_vat"}} {
				u, okU := prices[pair[0]]
				c, okC := prices[pair[1]]
				if !okU || !okC {
					continue
				}
				exp := u * float64(upc)
				if math.Abs(c-exp) > math.Max(cartonAbsTolerance, cartonRelTolerance*exp) {
					add(ri, domain.DQTypeCartonPriceMismatch, domain.DQSeverityWarning, hname(pair[1]), fmtNum(c),
						fmt.Sprintf("%s (= %s × %d)", fmtNum(exp), fmtNum(u), upc))
				}
			}
		}

		// VAT: the VAT column when present, otherwise the incl/excl price ratio.
		if v, present := col(r, "vat_rate"); present && v != "" && !isNA(v) && !r.Err[cm["vat_rate"]] {
			if f, ok := parseNum(v); ok {
				if f > 1 {
					f /= 100
				}
				if math.Abs(f-ExpectedVATRate) > vatTolerance {
					add(ri, domain.DQTypeVATNot14, domain.DQSeverityWarning, hname("vat_rate"), v, "14%")
				}
			} else {
				add(ri, domain.DQTypeVATNot14, domain.DQSeverityWarning, hname("vat_rate"), v, "14%")
			}
		} else if ex, ok1 := prices["unit_price_excl_vat"]; ok1 {
			if in, ok2 := prices["unit_price_incl_vat"]; ok2 {
				ratio := in / ex
				if math.Abs(ratio-(1+ExpectedVATRate)) > vatRatioTolerance*(1+ExpectedVATRate) {
					add(ri, domain.DQTypeVATNot14, domain.DQSeverityWarning, hname("unit_price_incl_vat"),
						fmt.Sprintf("%s%% (%s / %s)", fmtNum((ratio-1)*100), fmtNum(in), fmtNum(ex)), "14%")
				}
			}
		}

		// Invoice discount.
		if v, present := col(r, "invoice_discount_pct"); present && v != "" && !isNA(v) && !r.Err[cm["invoice_discount_pct"]] {
			f, ok := parseNum(v)
			if ok && f > 1 && f <= 100 {
				f /= 100
			}
			if !ok || f < 0 || f > MaxInvoiceDiscountRate {
				add(ri, domain.DQTypeInvoiceDiscountRange, domain.DQSeverityWarning, hname("invoice_discount_pct"), v,
					fmt.Sprintf("من 0%% إلى %s%%", fmtNum(MaxInvoiceDiscountRate*100)))
			}
		}
	}

	// Duplicate barcode across different SKU codes.
	byBarcode := map[string][]rowInfo{}
	for _, ri := range infos {
		if ri.barcode != "" {
			byBarcode[ri.barcode] = append(byBarcode[ri.barcode], ri)
		}
	}
	for bc, group := range byBarcode {
		codes := map[string]bool{}
		regular := 0
		for _, ri := range group {
			codes[ri.code] = true
		}
		if len(codes) < 2 {
			continue
		}
		list := make([]string, 0, len(codes))
		for c := range codes {
			list = append(list, c)
			if !strings.HasPrefix(c, "PR") {
				regular++
			}
		}
		sort.Strings(list)
		// Two regular SKUs on one barcode is critical; a promo pack reusing a barcode is a warning.
		sev := domain.DQSeverityWarning
		if regular >= 2 {
			sev = domain.DQSeverityCritical
		}
		for _, ri := range group {
			others := make([]string, 0, len(list)-1)
			for _, c := range list {
				if c != ri.code {
					others = append(others, c)
				}
			}
			add(ri, domain.DQTypeDuplicateBarcode, sev, hname("barcode"),
				fmt.Sprintf("%s مستخدم أيضًا في: %s", bc, strings.Join(others, "، ")), "باركود فريد لكل صنف")
		}
	}
	res.CriticalRows = len(criticalRows)
	sort.SliceStable(res.Issues, func(i, j int) bool {
		if res.Issues[i].Row != res.Issues[j].Row {
			return res.Issues[i].Row < res.Issues[j].Row
		}
		return res.Issues[i].Type < res.Issues[j].Type
	})
	return res, nil
}

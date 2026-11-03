package gemini

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// IsSellInPlanWorkbook inspects raw XLSX or CSV bytes to determine if the file is a Supplier Sell-In & Forecasting Plan.
func IsSellInPlanWorkbook(rawContent []byte) bool {
	if len(rawContent) == 0 {
		return false
	}
	var header []string
	if isZipArchive(rawContent) {
		rows, err := extractFirstSheetRows(rawContent, 5)
		if err != nil || len(rows) == 0 {
			return false
		}
		header = rows[0]
	} else {
		rows := parseSellInCSVRows(rawContent, 5)
		if len(rows) == 0 {
			return false
		}
		header = rows[0]
	}

	joined := strings.ToLower(strings.Join(header, " | "))
	// Guided template & Clean format markers
	if strings.Contains(joined, "net_qty_cases") ||
		strings.Contains(joined, "sell_in_cases") ||
		strings.Contains(joined, "sell_in_value") ||
		strings.Contains(joined, "expected_value_egp") ||
		strings.Contains(joined, "expected_cases") ||
		strings.Contains(joined, "صافي الكمية الفعلية بالكرتونة") ||
		strings.Contains(joined, "كمية التوريد بالكرتونة") ||
		strings.Contains(joined, "قيمة التوريد بالجنيه") {
		return true
	}
	// Raw plan 10 aswak format markers
	if strings.Contains(joined, "net q") && strings.Contains(joined, "net v") &&
		(strings.Contains(joined, "item 1") || strings.Contains(joined, "q exp") || strings.Contains(joined, "officer")) {
		return true
	}
	return false
}

func parseSellInCSVRows(rawContent []byte, maxRows int) [][]string {
	// Strip UTF-8 BOM if present
	cleaned := bytes.TrimPrefix(rawContent, []byte{0xEF, 0xBB, 0xBF})
	reader := csv.NewReader(bytes.NewReader(cleaned))
	reader.FieldsPerRecord = -1
	reader.LazyQuotes = true

	var rows [][]string
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			break
		}
		rows = append(rows, row)
		if maxRows > 0 && len(rows) >= maxRows {
			break
		}
	}
	return rows
}

func normalizeSellInChainCode(rawChain, fallbackChain string) string {
	c := strings.ToLower(strings.TrimSpace(rawChain))
	if c == "" || c == "all" || c == "الكل" || c == "جميع السلاسل" {
		fb := strings.ToLower(strings.TrimSpace(fallbackChain))
		if fb != "" && fb != "all" && fb != "الكل" {
			return fb
		}
		return "fathalla"
	}
	if strings.Contains(c, "فتح الله") || strings.Contains(c, "fathalla") {
		return "fathalla"
	}
	if strings.Contains(c, "بيت الجمل") || strings.Contains(c, "beet") {
		return "beet-elgomla"
	}
	if strings.Contains(c, "جملة ماركت") || strings.Contains(c, "جمله ماركت") || c == "gomla" || strings.Contains(c, "gomla market") {
		return "gomla"
	}
	if strings.Contains(c, "الوكال") || strings.Contains(c, "وكال") || strings.Contains(c, "wakala") || c == "chain-1080314" {
		return "chain-1080314"
	}
	if strings.Contains(c, "كارفور") || strings.Contains(c, "carrefour") {
		return "carrefour"
	}
	if strings.Contains(c, "سبينيس") || strings.Contains(c, "spinneys") {
		return "spinneys"
	}
	if strings.Contains(c, "كازيون") || strings.Contains(c, "kazyon") {
		return "kazyon"
	}
	return c
}

// ParseSellInPlanWorkbook parses any Supplier Sell-In & Forecasting workbook (.xlsx or .csv),
// supporting the Guided Demo Template, the 30-column clean format, and the raw ERP format.
func ParseSellInPlanWorkbook(tenantID, filename string, rawContent []byte, targetChains ...string) ([]domain.SellInRecord, error) {
	recs, _, err := ParseSellInPlanWorkbookWithReport(tenantID, filename, rawContent, targetChains...)
	return recs, err
}

// ParseSellInPlanWorkbookWithReport is ParseSellInPlanWorkbook plus a normalization report.
// Months and years are never defaulted: a row whose period cannot be read deterministically makes
// the whole file fail with an Arabic error (see SellInPeriodError).
func ParseSellInPlanWorkbookWithReport(tenantID, filename string, rawContent []byte, targetChains ...string) ([]domain.SellInRecord, *SellInParseReport, error) {
	report := &SellInParseReport{}
	recs, err := parseSellInPlanWorkbook(tenantID, filename, rawContent, report, targetChains...)
	return recs, report, err
}

func parseSellInPlanWorkbook(tenantID, filename string, rawContent []byte, report *SellInParseReport, targetChains ...string) ([]domain.SellInRecord, error) {
	defaultChain := "fathalla"
	chainChosen := false
	if len(targetChains) > 0 && strings.TrimSpace(targetChains[0]) != "" {
		tc := strings.ToLower(strings.TrimSpace(targetChains[0]))
		if tc != "all" && tc != "الكل" && tc != "جميع السلاسل" {
			defaultChain = normalizeSellInChainCode(tc, "fathalla")
			chainChosen = true
		}
	}

	var rows [][]string
	if isZipArchive(rawContent) {
		zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
		if err != nil {
			return nil, fmt.Errorf("failed to open xlsx zip reader: %w", err)
		}

		var sharedStrings []string
		var sheet1File *zip.File

		for _, f := range zr.File {
			nameLower := strings.ToLower(f.Name)
			if nameLower == "xl/sharedstrings.xml" {
				rc, err := f.Open()
				if err == nil {
					data, readErr := io.ReadAll(rc)
					_ = rc.Close()
					if readErr == nil {
						var sst xlsxSST
						if xml.Unmarshal(data, &sst) == nil {
							for _, si := range sst.SI {
								if len(si.R) > 0 {
									var sb strings.Builder
									for _, r := range si.R {
										sb.WriteString(r.T)
									}
									sharedStrings = append(sharedStrings, sb.String())
								} else {
									sharedStrings = append(sharedStrings, si.T)
								}
							}
						}
					}
				}
			} else if nameLower == "xl/worksheets/sheet1.xml" {
				sheet1File = f
			}
		}

		if sheet1File == nil {
			for _, f := range zr.File {
				nameLower := strings.ToLower(f.Name)
				if strings.HasPrefix(nameLower, "xl/worksheets/sheet") && strings.HasSuffix(nameLower, ".xml") {
					sheet1File = f
					break
				}
			}
		}
		if sheet1File == nil {
			return nil, fmt.Errorf("no worksheet found in %s", filename)
		}

		var errSheet error
		rows, errSheet = readWorksheetXML(sheet1File, sharedStrings)
		if errSheet != nil || len(rows) < 2 {
			return nil, fmt.Errorf("failed to read rows from %s: %w", filename, errSheet)
		}
	} else {
		rows = parseSellInCSVRows(rawContent, 0)
		if len(rows) < 2 {
			return nil, fmt.Errorf("file %s has insufficient rows", filename)
		}
	}

	if hdr := findGPSOPHeaderRow(rows); hdr >= 0 {
		report.Layout = "gp_sop_export"
		if !chainChosen {
			// TOP RULE: a GP SOP export has no chain column, so the chain is never defaulted (a Zahran
			// or Gomla export must not become fathalla and pick up the Fathalla aliases).
			return nil, &SellInChainRequiredError{Filename: filename}
		}
		return parseGPSOPExport(tenantID, filename, rows, hdr, defaultChain, report)
	}

	headerRow := rows[0]
	headerJoined := strings.ToLower(strings.Join(headerRow, " | "))
	isClean30ColFormat := (strings.Contains(headerJoined, "net_qty_cases") ||
		strings.Contains(headerJoined, "صافي الكمية الفعلية بالكرتونة")) && len(headerRow) >= 28
	isGuidedTemplateFormat := strings.Contains(headerJoined, "sell_in_cases") ||
		strings.Contains(headerJoined, "كمية التوريد بالكرتونة") ||
		strings.Contains(headerJoined, "retail_chain") ||
		strings.Contains(headerJoined, "سلسلة التجزئة")

	// Build dynamic column index map for flexible/guided template formats
	colMap := buildSellInHeaderMap(headerRow)
	// A narrow raw plan (only Customer / Item 1 / Year / Month / net Q / net V) is still a raw
	// plan: detect it by its header names, not by width. Before this, a <25-column raw plan fell
	// through to the AI fallback, which rebuilt the date from Year+Month and then rejected every
	// row as "no clear month and year".
	_, rawMissing := buildRawPlanHeaderMap(headerRow)
	isNarrowRawPlan := len(rawMissing) == 0
	if !isClean30ColFormat && !isGuidedTemplateFormat && colMap["item_name"] < 0 && len(headerRow) < 25 && !isNarrowRawPlan {
		return nil, fmt.Errorf("file %s does not match standard single-sheet sell-in columns", filename)
	}

	fileYear, _ := YearFromFilename(filename)
	periods := newSellInPeriodResolver(fileYear)
	var rawPlanCols map[string]int
	if isClean30ColFormat {
		report.Layout = "clean_30_col"
	} else if isGuidedTemplateFormat || colMap["item_name"] >= 0 {
		report.Layout = "guided_template"
	} else {
		report.Layout = "raw_plan"
		var missing []string
		rawPlanCols, missing = buildRawPlanHeaderMap(headerRow)
		if len(missing) > 0 {
			return nil, &SellInLayoutError{Filename: filename, Missing: missing}
		}
	}

	now := time.Now().UTC()
	records := make([]domain.SellInRecord, 0, len(rows)-1)

	for i := 1; i < len(rows); i++ {
		r := rows[i]
		if len(r) == 0 {
			continue
		}
		// Skip instruction/guide row if present
		firstCell := strings.ToLower(strings.TrimSpace(getCol(r, 0)))
		rowJoined := strings.ToLower(strings.Join(r, " "))
		if strings.Contains(firstCell, "مثال") || strings.Contains(firstCell, "إرشاد") ||
			strings.Contains(firstCell, "guide") || strings.Contains(rowJoined, "سطر إرشادي") ||
			strings.Contains(rowJoined, "instruction_row") {
			continue
		}

		periods.startRow()
		var rec domain.SellInRecord
		rec.RecordID = fmt.Sprintf("sellin_%s_%d", tenantID, i)
		rec.TenantID = tenantID
		rec.RetailerChain = defaultChain
		rec.IngestedAt = now

		if isClean30ColFormat {
			if y, m, ok := periods.resolve(i+1, getCol(r, 0), getCol(r, 1), getCol(r, 2), ""); ok {
				rec.Year, rec.MonthNum = y, m
			}
			rec.MonthEN = monthNumToEN(rec.MonthNum)
			rec.MonthAR = ArabicMonthName(rec.MonthNum)
			rec.PeriodWeek = strings.TrimSpace(getCol(r, 4))
			rec.RegionCode = strings.TrimSpace(getCol(r, 5))
			rec.Governorate = strings.TrimSpace(getCol(r, 6))
			rec.Sector = strings.TrimSpace(getCol(r, 7))
			rec.SubSector = strings.TrimSpace(getCol(r, 8))
			rec.Division = strings.TrimSpace(getCol(r, 9))
			rec.ParentAccountCode = strings.TrimSpace(getCol(r, 10))
			rec.ParentCustomer = strings.TrimSpace(getCol(r, 11))
			rec.CustomerName = strings.TrimSpace(getCol(r, 12))
			rec.CustomerBranchCode = strings.TrimSpace(getCol(r, 13))
			rec.Brand = strings.TrimSpace(getCol(r, 14))
			rec.ProductFamily = strings.TrimSpace(getCol(r, 15))
			rec.SubCategory = strings.TrimSpace(getCol(r, 16))
			rec.ItemGroup = strings.TrimSpace(getCol(r, 17))
			rec.ItemName = strings.TrimSpace(getCol(r, 18))
			rec.PromotionType = strings.TrimSpace(getCol(r, 19))
			rec.SalesManager = strings.TrimSpace(getCol(r, 20))
			rec.KAOfficer = strings.TrimSpace(getCol(r, 21))
			rec.SalesRep = strings.TrimSpace(getCol(r, 22))
			rec.NetQtyCases = parseFloatDefault(getCol(r, 23), 0)
			rec.NetValueEGP = parseFloatDefault(getCol(r, 24), 0)
			rec.TurnoverEGP = parseFloatDefault(getCol(r, 25), rec.NetValueEGP)
			rec.WeightTons = parseFloatDefault(getCol(r, 26), 0)
			rec.ExpectedQtyCases = parseFloatDefault(getCol(r, 27), rec.NetQtyCases)
			rec.ExpectedValueEGP = parseFloatDefault(getCol(r, 28), rec.NetValueEGP)
			rec.TransactionType = strings.TrimSpace(getCol(r, 29))
		} else if isGuidedTemplateFormat || colMap["item_name"] >= 0 {
			if y, m, ok := periods.resolve(i+1, getColByMap(r, colMap, "year"), getColByMap(r, colMap, "month_num"), getColByMap(r, colMap, "month_name"), ""); ok {
				rec.Year, rec.MonthNum = y, m
			}
			rec.MonthEN = monthNumToEN(rec.MonthNum)
			rec.MonthAR = ArabicMonthName(rec.MonthNum)

			rec.PeriodWeek = strings.TrimSpace(getColByMap(r, colMap, "period_week"))
			if rec.PeriodWeek == "" {
				rec.PeriodWeek = "Full Month"
			}
			rawChain := strings.TrimSpace(getColByMap(r, colMap, "retail_chain"))
			rec.RetailerChain = normalizeSellInChainCode(rawChain, defaultChain)

			rec.RegionCode = strings.TrimSpace(getColByMap(r, colMap, "region_code"))
			if rec.RegionCode == "" {
				rec.RegionCode = "ALX"
			}
			rec.Governorate = strings.TrimSpace(getColByMap(r, colMap, "governorate"))
			if rec.Governorate == "" {
				rec.Governorate = inferGovernorateFromRegion(rec.RegionCode)
			}
			rec.CustomerName = strings.TrimSpace(getColByMap(r, colMap, "branch_name"))
			rec.CustomerBranchCode = strings.TrimSpace(getColByMap(r, colMap, "customer_branch_code"))
			if rec.CustomerBranchCode == "" {
				rec.CustomerBranchCode = rec.CustomerName
			}
			rec.Sector = strings.TrimSpace(getColByMap(r, colMap, "sector"))
			if rec.Sector == "" {
				rec.Sector = "عام"
			}
			rec.SubSector = strings.TrimSpace(getColByMap(r, colMap, "sub_sector"))
			rec.Brand = strings.TrimSpace(getColByMap(r, colMap, "brand"))
			rec.SubCategory = strings.TrimSpace(getColByMap(r, colMap, "sub_category"))
			rec.ProductFamily = strings.TrimSpace(getColByMap(r, colMap, "product_family"))
			rec.ItemGroup = strings.TrimSpace(getColByMap(r, colMap, "barcode"))
			rec.ItemName = strings.TrimSpace(getColByMap(r, colMap, "item_name"))
			rec.PromotionType = strings.TrimSpace(getColByMap(r, colMap, "promo_type"))
			if rec.PromotionType == "" {
				rec.PromotionType = "عادي"
			}
			rec.SalesManager = strings.TrimSpace(getColByMap(r, colMap, "sales_manager"))
			rec.KAOfficer = strings.TrimSpace(getColByMap(r, colMap, "ka_officer"))
			rec.SalesRep = strings.TrimSpace(getColByMap(r, colMap, "sales_rep"))
			if rec.SalesRep == "" {
				rec.SalesRep = "فريق المبيعات الميداني"
			}
			rec.NetQtyCases = parseFloatDefault(getColByMap(r, colMap, "sell_in_cases"), 0)
			rec.NetValueEGP = parseFloatDefault(getColByMap(r, colMap, "sell_in_value"), 0)
			rec.TurnoverEGP = rec.NetValueEGP
			rec.WeightTons = parseFloatDefault(getColByMap(r, colMap, "weight_tons"), 0)
			if rec.WeightTons == 0 && rec.NetQtyCases != 0 {
				rec.WeightTons = math.Round(math.Abs(rec.NetQtyCases)*0.012*10000) / 10000
			}
			expCases := parseFloatDefault(getColByMap(r, colMap, "expected_cases"), 0)
			expVal := parseFloatDefault(getColByMap(r, colMap, "expected_value"), 0)
			if expCases == 0 {
				if strings.Contains(strings.ToUpper(rec.PeriodWeek), "W") {
					expCases = math.Round(rec.NetQtyCases*1.85*100) / 100
				} else {
					expCases = rec.NetQtyCases
				}
			}
			if expVal == 0 {
				if strings.Contains(strings.ToUpper(rec.PeriodWeek), "W") {
					expVal = math.Round(rec.NetValueEGP*1.85*100) / 100
				} else {
					expVal = rec.NetValueEGP
				}
			}
			rec.ExpectedQtyCases = expCases
			rec.ExpectedValueEGP = expVal

			rec.TransactionType = strings.TrimSpace(getColByMap(r, colMap, "transaction_type"))
			if rec.TransactionType == "" {
				if rec.NetQtyCases < 0 || rec.NetValueEGP < 0 || strings.Contains(rec.PromotionType, "مرتجع") {
					rec.TransactionType = "مرتجع (Return)"
				} else if rec.NetQtyCases == 0 && rec.NetValueEGP == 0 {
					rec.TransactionType = "صفري (Zero)"
				} else {
					rec.TransactionType = "مسحوبات بيع (Sale)"
				}
			}
		} else {
			// Raw plan 10 aswak.xlsx format
			rec.RegionCode = strings.TrimSpace(getCol(r, rawPlanCols["region"]))
			rec.Sector = strings.TrimSpace(getCol(r, rawPlanCols["sector"]))
			rec.SubSector = strings.TrimSpace(getCol(r, rawPlanCols["sub_sector"]))
			rec.Division = strings.TrimSpace(getCol(r, rawPlanCols["division"]))
			rec.ParentAccountCode = strings.TrimSpace(getCol(r, rawPlanCols["parent_account_code"]))
			rec.ParentCustomer = strings.TrimSpace(getCol(r, rawPlanCols["parent_customer"]))
			rec.ItemName = strings.TrimSpace(getCol(r, rawPlanCols["item_name"]))
			rec.ItemGroup = strings.TrimSpace(getCol(r, rawPlanCols["item_group"]))
			rec.SubCategory = strings.TrimSpace(getCol(r, rawPlanCols["sub_category"]))
			rec.ProductFamily = strings.TrimSpace(getCol(r, rawPlanCols["product_family"]))
			rec.Brand = strings.TrimSpace(getCol(r, rawPlanCols["brand"]))
			rec.PeriodWeek = strings.TrimSpace(getCol(r, rawPlanCols["period_week"]))
			if rec.PeriodWeek == "" {
				rec.PeriodWeek = "Full Month"
			}
			if y, m, ok := periods.resolve(i+1, getCol(r, rawPlanCols["year"]), "", getCol(r, rawPlanCols["month"]), ""); ok {
				rec.Year, rec.MonthNum = y, m
			}
			rec.MonthEN = monthNumToEN(rec.MonthNum)
			rec.MonthAR = ArabicMonthName(rec.MonthNum)
			rec.NetQtyCases = parseFloatDefault(getCol(r, rawPlanCols["net_q"]), 0)
			rec.NetValueEGP = parseFloatDefault(getCol(r, rawPlanCols["net_v"]), 0)
			rec.WeightTons = parseFloatDefault(getCol(r, rawPlanCols["ton"]), 0)
			rec.Governorate = strings.TrimSpace(getCol(r, rawPlanCols["city"]))
			if rec.Governorate == "" {
				rec.Governorate = inferGovernorateFromRegion(rec.RegionCode)
			}
			rec.CustomerName = strings.TrimSpace(getCol(r, rawPlanCols["customer"]))
			rec.CustomerBranchCode = strings.TrimSpace(getCol(r, rawPlanCols["branch_code"]))
			if rec.CustomerBranchCode == "" {
				rec.CustomerBranchCode = "مجمع الإقليم (Regional)"
			}
			rec.SalesRep = strings.TrimSpace(getCol(r, rawPlanCols["sales_rep"]))
			if rec.SalesRep == "" {
				rec.SalesRep = "توزيع مركزي (Central KA)"
			}
			rec.PromotionType = strings.TrimSpace(getCol(r, rawPlanCols["promotion"]))
			if rec.PromotionType == "" {
				rec.PromotionType = "عادي"
			}
			rec.KAOfficer = strings.TrimSpace(getCol(r, rawPlanCols["officer"]))
			rec.SalesManager = strings.TrimSpace(getCol(r, rawPlanCols["officer_mgr"]))
			rec.TurnoverEGP = parseFloatDefault(getCol(r, rawPlanCols["turnover"]), rec.NetValueEGP)
			expQ := parseFloatDefault(getCol(r, rawPlanCols["q_exp"]), 0)
			expV := parseFloatDefault(getCol(r, rawPlanCols["v_exp"]), 0)
			if expQ == 0 && rec.PeriodWeek == "Full Month" {
				expQ = rec.NetQtyCases
			}
			if expV == 0 && rec.PeriodWeek == "Full Month" {
				expV = rec.NetValueEGP
			}
			rec.ExpectedQtyCases = expQ
			rec.ExpectedValueEGP = expV
			if rec.WeightTons == 0 && rec.NetQtyCases != 0 {
				rec.WeightTons = math.Round(rec.NetQtyCases*0.012*10000) / 10000
			}
			if rec.NetQtyCases < 0 || rec.NetValueEGP < 0 {
				rec.TransactionType = "مرتجع (Return)"
			} else if rec.NetQtyCases == 0 && rec.NetValueEGP == 0 {
				rec.TransactionType = "صفري (Zero)"
			} else {
				rec.TransactionType = "مسحوبات بيع (Sale)"
			}
		}
		if rec.Brand == "" || rec.Brand == "عام" || strings.EqualFold(rec.Brand, "other") || strings.EqualFold(rec.Brand, "general") || rec.Brand == "منتجات الشركة" {
			rec.Brand = domain.InferBrandFromItemName(rec.ItemName, rec.SubCategory)
		}

		if rec.ItemName == "" && rec.Brand == "" && rec.NetValueEGP == 0 {
			continue
		}
		if !periods.accept(i + 1) {
			continue
		}
		rec.MonthAR = ArabicMonthName(rec.MonthNum)
		rec.MonthEN = monthNumToEN(rec.MonthNum)
		records = append(records, rec)
	}

	if err := periods.err(filename); err != nil {
		return nil, err
	}
	if len(records) == 0 {
		return nil, fmt.Errorf("no valid sell-in records found in %s", filename)
	}
	return records, nil
}

func buildSellInHeaderMap(headers []string) map[string]int {
	m := map[string]int{
		"year":                 -1,
		"month_num":            -1,
		"month_name":           -1,
		"period_week":          -1,
		"retail_chain":         -1,
		"region_code":          -1,
		"governorate":          -1,
		"branch_name":          -1,
		"customer_branch_code": -1,
		"sector":               -1,
		"sub_sector":           -1,
		"brand":                -1,
		"sub_category":         -1,
		"product_family":       -1,
		"barcode":              -1,
		"item_name":            -1,
		"promo_type":           -1,
		"transaction_type":     -1,
		"sales_manager":        -1,
		"ka_officer":           -1,
		"sales_rep":            -1,
		"sell_in_cases":        -1,
		"sell_in_value":        -1,
		"weight_tons":          -1,
		"expected_cases":       -1,
		"expected_value":       -1,
	}
	for idx, raw := range headers {
		h := strings.ToLower(strings.TrimSpace(raw))
		switch {
		case strings.Contains(h, "expected_cases") || strings.Contains(h, "expected_qty") || strings.Contains(h, "الكمية المتوقعة") || strings.Contains(h, "exp qty") || strings.Contains(h, "q exp"):
			m["expected_cases"] = idx
		case strings.Contains(h, "expected_value") || strings.Contains(h, "القيمة المتوقعة") || strings.Contains(h, "exp egp") || strings.Contains(h, "v exp"):
			m["expected_value"] = idx
		case strings.Contains(h, "year") || strings.Contains(h, "السنة") || strings.Contains(h, "سنة"):
			m["year"] = idx
		case strings.Contains(h, "month_num") || strings.Contains(h, "رقم الشهر"):
			m["month_num"] = idx
		case strings.Contains(h, "month_name") || strings.Contains(h, "month_en") || strings.Contains(h, "اسم الشهر") || h == "الشهر" || h == "شهر" || h == "month":
			m["month_name"] = idx
		case strings.Contains(h, "period") || strings.Contains(h, "فترة التوريد") || strings.Contains(h, "حالة الفترة"):
			m["period_week"] = idx
		case strings.Contains(h, "retail_chain") || strings.Contains(h, "retailer_chain") || strings.Contains(h, "سلسلة التجزئة") || h == "السلسلة" || h == "chain":
			m["retail_chain"] = idx
		case strings.Contains(h, "region_code") || strings.Contains(h, "كود الإقليم") || h == "الإقليم":
			m["region_code"] = idx
		case strings.Contains(h, "governorate") || strings.Contains(h, "المحافظة"):
			m["governorate"] = idx
		case strings.Contains(h, "sub_category") || strings.Contains(h, "الفئة الفرعية") || h == "الفئة":
			m["sub_category"] = idx
		case strings.Contains(h, "product_family") || strings.Contains(h, "عائلة المنتج"):
			m["product_family"] = idx
		case strings.Contains(h, "customer_branch_code") || strings.Contains(h, "كود الفرع") || strings.Contains(h, "كود فرع العميل"):
			m["customer_branch_code"] = idx
		case strings.Contains(h, "sales_manager") || strings.Contains(h, "مدير المبيعات") || strings.Contains(h, "مدير القطاع"):
			m["sales_manager"] = idx
		case strings.Contains(h, "sub_sector") || strings.Contains(h, "القطاع الفرعي") || strings.Contains(h, "قطاع فرعي"):
			m["sub_sector"] = idx
		case strings.Contains(h, "sector") || strings.Contains(h, "القطاع"):
			m["sector"] = idx
		case strings.Contains(h, "ka_officer") || strings.Contains(h, "مسؤول كبار العملاء"):
			m["ka_officer"] = idx
		case strings.Contains(h, "branch") || strings.Contains(h, "customer_name") || strings.Contains(h, "اسم الفرع") || strings.Contains(h, "الفرع") || strings.Contains(h, "العميل"):
			m["branch_name"] = idx
		case strings.Contains(h, "brand") || strings.Contains(h, "العلامة التجارية") || h == "العلامة":
			m["brand"] = idx
		case strings.Contains(h, "barcode") || strings.Contains(h, "باركود") || strings.Contains(h, "كود الصنف") || strings.Contains(h, "مجموعة الصنف"):
			m["barcode"] = idx
		case strings.Contains(h, "item_name") || strings.Contains(h, "sku_name") || strings.Contains(h, "اسم الصنف") || h == "الصنف" || strings.Contains(h, "المنتج"):
			m["item_name"] = idx
		case strings.Contains(h, "transaction_type") || strings.Contains(h, "نوع الحركة"):
			m["transaction_type"] = idx
		case strings.Contains(h, "promo") || strings.Contains(h, "نوع العرض"):
			m["promo_type"] = idx
		case strings.Contains(h, "sales_rep") || strings.Contains(h, "مندوب المبيعات") || h == "المندوب":
			m["sales_rep"] = idx
		case strings.Contains(h, "sell_in_cases") || strings.Contains(h, "net_qty_cases") || strings.Contains(h, "كمية التوريد") || strings.Contains(h, "الكمية بالكرتون") || strings.Contains(h, "cases") || strings.Contains(h, "كرتون") || strings.Contains(h, "الكمية") || h == "qty" || h == "quantity":
			m["sell_in_cases"] = idx
		case strings.Contains(h, "sell_in_value") || strings.Contains(h, "net_value_egp") || strings.Contains(h, "قيمة التوريد") || strings.Contains(h, "صافي التوريد") || strings.Contains(h, "صافي القيمة") || strings.Contains(h, "القيمة") || strings.Contains(h, "value") || strings.Contains(h, "revenue"):
			m["sell_in_value"] = idx
		case strings.Contains(h, "weight_tons") || strings.Contains(h, "الوزن بالطن") || strings.Contains(h, "الوزن") || strings.Contains(h, "tons"):
			m["weight_tons"] = idx
		}
	}
	return m
}

func getColByMap(row []string, colMap map[string]int, key string) string {
	idx, ok := colMap[key]
	if !ok || idx < 0 || idx >= len(row) {
		return ""
	}
	return row[idx]
}

func monthNumToEN(m int) string {
	months := []string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
	if m >= 1 && m <= 12 {
		return months[m-1]
	}
	return "Jan"
}

func extractFirstSheetRows(rawContent []byte, maxRows int) ([][]string, error) {
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return nil, err
	}
	var sharedStrings []string
	var sheetFile *zip.File
	for _, f := range zr.File {
		nl := strings.ToLower(f.Name)
		if nl == "xl/sharedstrings.xml" {
			rc, err := f.Open()
			if err == nil {
				data, _ := io.ReadAll(rc)
				_ = rc.Close()
				sharedStrings = readSharedStringsFast(data)
			}
		} else if nl == "xl/worksheets/sheet1.xml" {
			sheetFile = f
		}
	}
	if sheetFile == nil {
		return nil, fmt.Errorf("no sheet1.xml found")
	}
	if maxRows > 0 && maxRows <= 50 {
		return readWorksheetSampleRows(sheetFile, sharedStrings, maxRows)
	}
	rows, err := readWorksheetXML(sheetFile, sharedStrings)
	if err != nil {
		return nil, err
	}
	if maxRows > 0 && len(rows) > maxRows {
		return rows[:maxRows], nil
	}
	return rows, nil
}

// ExtractXLSXOrCSVRows extracts tabular rows from an XLSX workbook or CSV byte slice using standard library zip/xml/csv parsers.
func ExtractXLSXOrCSVRows(rawContent []byte) ([][]string, error) {
	if len(rawContent) == 0 {
		return nil, fmt.Errorf("empty file")
	}
	if isZipArchive(rawContent) {
		return extractFirstSheetRows(rawContent, 0)
	}
	return parseSellInCSVRows(rawContent, 0), nil
}

func getCol(row []string, idx int) string {
	if idx >= 0 && idx < len(row) {
		return row[idx]
	}
	return ""
}

func parseIntDefault(s string, def int) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return def
	}
	if v, err := strconv.Atoi(s); err == nil {
		return v
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		return int(math.Round(f))
	}
	return def
}

func parseFloatDefault(s string, def float64) float64 {
	s = strings.TrimSpace(strings.ReplaceAll(s, ",", ""))
	if s == "" {
		return def
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil && !math.IsNaN(f) && !math.IsInf(f, 0) {
		return f
	}
	return def
}

func normalizeMonthEN(m string) (int, string) {
	switch strings.ToLower(strings.TrimSpace(m)) {
	case "jan", "1", "01", "يناير":
		return 1, "يناير"
	case "feb", "2", "02", "فبراير":
		return 2, "فبراير"
	case "mar", "3", "03", "مارس":
		return 3, "مارس"
	case "apr", "4", "04", "أبريل", "ابريل":
		return 4, "أبريل"
	case "may", "5", "05", "مايو":
		return 5, "مايو"
	case "jun", "6", "06", "يونيو":
		return 6, "يونيو"
	case "jul", "7", "07", "يوليو":
		return 7, "يوليو"
	case "aug", "8", "08", "أغسطس", "اغسطس":
		return 8, "أغسطس"
	case "sep", "9", "09", "سبتمبر":
		return 9, "سبتمبر"
	case "oct", "10", "أكتوبر", "اكتوبر":
		return 10, "أكتوبر"
	case "nov", "11", "نوفمبر":
		return 11, "نوفمبر"
	case "dec", "12", "ديسمبر":
		return 12, "ديسمبر"
	default:
		if m, _, ok := ParseMonthToken(m); ok {
			return m, ArabicMonthName(m)
		}
		return 0, ""
	}
}

func inferGovernorateFromRegion(region string) string {
	switch strings.ToUpper(strings.TrimSpace(region)) {
	case "ALX":
		return "الاسكندرية"
	case "CIR":
		return "القاهرة"
	case "TNT":
		return "الغربية"
	case "BHR":
		return "البحيرة"
	case "MNS":
		return "المنصورة (الدقهلية)"
	default:
		return "الاسكندرية"
	}
}

// InferBrandFromItemName uses AI-grade heuristic brand extraction across Arabic & English FMCG and retail goods.
// It recognizes established brands and dynamically extracts novel brand tokens for any company.
func InferBrandFromItemName(itemName, subCategory string) string {
	s := strings.ToLower(itemName + " " + subCategory)
	switch {
	case strings.Contains(s, "ماكسيل") || strings.Contains(s, "maxel"):
		return "ماكسيل (Maxell)"
	case strings.Contains(s, "ديفا") || strings.Contains(s, "diva"):
		return "ديفا (Diva)"
	case strings.Contains(s, "فلفيتا") || strings.Contains(s, "فلڤيتا") || strings.Contains(s, "velveta"):
		return "فلڤيتا (Velveta)"
	case strings.Contains(s, "فيبا") || strings.Contains(s, "feba"):
		return "فيبا (Feba)"
	case strings.Contains(s, "دوف") || strings.Contains(s, "dove"):
		return "دوف (Dove)"
	case strings.Contains(s, "جلاسي") || strings.Contains(s, "جلاسى") || strings.Contains(s, "glassy"):
		return "جلاسي (Glassy)"
	case strings.Contains(s, "سبيد") || strings.Contains(s, "speed"):
		return "سبيد (Speed)"
	case strings.Contains(s, "رابيدو") || strings.Contains(s, "rapido"):
		return "رابيدو (Rapido)"
	case strings.Contains(s, "كلوريل") || strings.Contains(s, "clorel"):
		return "كلوريل (Clorel)"
	case strings.Contains(s, "جنرال") || strings.Contains(s, "general"):
		return "جنرال (General)"
	case strings.Contains(s, "أريال") || strings.Contains(s, "اريال") || strings.Contains(s, "ariel"):
		return "أريال (Ariel)"
	case strings.Contains(s, "برسيل") || strings.Contains(s, "persil"):
		return "برسيل (Persil)"
	case strings.Contains(s, "كلوركس") || strings.Contains(s, "clorox"):
		return "كلوركس (Clorox)"
	case strings.Contains(s, "ديتول") || strings.Contains(s, "dettol"):
		return "ديتول (Dettol)"
	case strings.Contains(s, "فاين") || strings.Contains(s, "fine"):
		return "فاين (Fine)"
	case strings.Contains(s, "زينة") || strings.Contains(s, "zeina"):
		return "زينة (Zeina)"
	case strings.Contains(s, "بامبرز") || strings.Contains(s, "pampers"):
		return "بامبرز (Pampers)"
	case strings.Contains(s, "مولفيكس") || strings.Contains(s, "molfix"):
		return "مولفيكس (Molfix)"
	case strings.Contains(s, "جهينة") || strings.Contains(s, "juhayna"):
		return "جهينة (Juhayna)"
	case strings.Contains(s, "المراعي") || strings.Contains(s, "almarai"):
		return "المراعي (Almarai)"
	case strings.Contains(s, "ليبتون") || strings.Contains(s, "lipton"):
		return "ليبتون (Lipton)"
	case strings.Contains(s, "نسكافيه") || strings.Contains(s, "nescafe"):
		return "نسكافيه (Nescafe)"
	case strings.Contains(s, "بيبسي") || strings.Contains(s, "pepsi"):
		return "بيبسي (Pepsi)"
	case strings.Contains(s, "كوكاكولا") || strings.Contains(s, "coca"):
		return "كوكاكولا (Coca-Cola)"
	default:
		// Extract leading brand token dynamically for any new company
		clean := strings.TrimSpace(itemName)
		if clean == "" {
			if subCategory != "" {
				return subCategory
			}
			return "أصناف عامة"
		}
		parts := strings.Fields(clean)
		if len(parts) > 0 {
			first := parts[0]
			if len([]rune(first)) >= 2 {
				if len(parts) > 1 && (parts[1] == "ماجيك" || parts[1] == "جولد" || parts[1] == "بلس" || strings.EqualFold(parts[1], "Magic") || strings.EqualFold(parts[1], "Gold") || strings.EqualFold(parts[1], "Plus")) {
					return first + " " + parts[1]
				}
				return first
			}
		}
		return "أصناف عامة"
	}
}


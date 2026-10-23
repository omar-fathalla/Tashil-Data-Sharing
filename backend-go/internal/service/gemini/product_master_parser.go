package gemini

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// IsProductMasterWorkbook inspects raw XLSX or CSV bytes to determine if the file is an Adeco / FMCG Product Master & Price List (كارتة الأصناف والأسعار).
func IsProductMasterWorkbook(rawContent []byte) bool {
	if len(rawContent) == 0 {
		return false
	}
	var rows [][]string
	if isZipArchive(rawContent) {
		var err error
		rows, err = extractFirstSheetRows(rawContent, 10)
		if err != nil || len(rows) == 0 {
			return false
		}
	} else {
		rows = parseSellInCSVRows(rawContent, 10)
		if len(rows) == 0 {
			return false
		}
	}

	for _, r := range rows {
		joined := strings.ToLower(strings.Join(r, " | "))
		hasItemCode := strings.Contains(joined, "كود الصنف") || strings.Contains(joined, "item_code") || strings.Contains(joined, "item code")
		hasCartonUnits := strings.Contains(joined, "عدد الوحدات بالكرتونة") || strings.Contains(joined, "وحدات بالكرتونة") || strings.Contains(joined, "units_per_carton")
		hasPrice := strings.Contains(joined, "سعر العبوه") || strings.Contains(joined, "سعر العبوة") ||
			strings.Contains(joined, "سعر القطعه") || strings.Contains(joined, "سعر القطعة") ||
			strings.Contains(joined, "سعر الكرتونة") || strings.Contains(joined, "unit_price_excl_vat") ||
			strings.Contains(joined, "net_unit_invoice_cost")
		if hasItemCode && (hasCartonUnits || hasPrice) {
			return true
		}
	}
	return false
}

// ParseProductMasterWorkbook parses an uploaded Product Master & Price List workbook (.xlsx or .csv) into a structured ProductMasterSummaryResponse.
func ParseProductMasterWorkbook(tenantID, filename string, rawContent []byte) (*domain.ProductMasterSummaryResponse, error) {
	if len(rawContent) == 0 {
		return nil, fmt.Errorf("empty product master file")
	}

	sheetName := "تحديث 01-08-2026"
	var rows [][]string
	if isZipArchive(rawContent) {
		if detectedName := extractFirstSheetName(rawContent); detectedName != "" {
			sheetName = strings.TrimSpace(detectedName)
		}
		var err error
		rows, err = extractFirstSheetRows(rawContent, 0)
		if err != nil {
			return nil, fmt.Errorf("failed to read product master xlsx: %w", err)
		}
	} else {
		rows = parseSellInCSVRows(rawContent, 0)
	}

	if len(rows) == 0 {
		return nil, fmt.Errorf("product master file has no rows")
	}

	companyName := "شركة الاسكندرية للكيماويات و المنظفات ( ادكو )"
	defaultDiscountPct := 0.10
	defaultVATRate := 0.14

	headerRowIdx := -1
	for i := 0; i < len(rows) && i < 12; i++ {
		joined := strings.ToLower(strings.Join(rows[i], " | "))
		if (strings.Contains(joined, "كود الصنف") || strings.Contains(joined, "item_code")) &&
			(strings.Contains(joined, "اسم الصنف") || strings.Contains(joined, "official_name") || strings.Contains(joined, "باركود") || strings.Contains(joined, "barcode")) {
			headerRowIdx = i
			break
		}
		// Check pre-header metadata rows (Row 1 company name, Row 2 global discount)
		for idx, cell := range rows[i] {
			trimmed := strings.TrimSpace(cell)
			if strings.Contains(trimmed, "شركة") || strings.Contains(trimmed, "ادكو") || strings.Contains(strings.ToLower(trimmed), "adeco") {
				companyName = trimmed
			}
			if strings.Contains(trimmed, "نسبة خصم الفاتورة") && idx+1 < len(rows[i]) {
				if d := parseFloatDefault(rows[i][idx+1], -1); d >= 0 && d <= 1.0 {
					defaultDiscountPct = d
				}
			}
		}
	}

	if headerRowIdx < 0 {
		return nil, fmt.Errorf("could not locate Product Master header row containing 'كود الصنف'")
	}

	colMap := mapProductMasterColumns(rows[headerRowIdx])
	nowStr := time.Now().Format("2006-01-02")

	var items []domain.ProductMasterItem
	seenCodes := make(map[string]int) // ItemCode -> index in items

	for rIdx := headerRowIdx + 1; rIdx < len(rows); rIdx++ {
		row := rows[rIdx]
		rawCode := strings.TrimSpace(getColByMap(row, colMap, "item_code"))
		rawName := strings.TrimSpace(getColByMap(row, colMap, "official_name"))
		if rawCode == "" || rawName == "" {
			continue
		}
		// Skip repeated header rows
		if strings.Contains(rawCode, "كود الصنف") || strings.EqualFold(rawCode, "item_code") {
			continue
		}

		itemCode := domain.NormalizeItemCode(rawCode)
		prefix := domain.ExtractItemCodePrefix(itemCode)
		barcode := domain.CleanBarcode(getColByMap(row, colMap, "barcode"))

		serialNo := parseIntDefault(getColByMap(row, colMap, "serial_no"), len(items)+1)
		invDisc := parseFloatDefault(getColByMap(row, colMap, "invoice_discount_pct"), defaultDiscountPct)
		if invDisc > 1.0 && invDisc <= 100.0 {
			invDisc = invDisc / 100.0
		}

		rawType := strings.TrimSpace(getColByMap(row, colMap, "item_type"))
		itemType := "عادي"
		if strings.Contains(rawType, "عرض") || strings.EqualFold(rawType, "promo") || strings.HasPrefix(prefix, "PR") {
			itemType = "عرض"
		}

		vatRate := parseFloatDefault(getColByMap(row, colMap, "vat_rate"), defaultVATRate)
		if vatRate > 1.0 && vatRate <= 100.0 {
			vatRate = vatRate / 100.0
		}
		if vatRate <= 0 {
			vatRate = defaultVATRate
		}

		packaging := strings.TrimSpace(getColByMap(row, colMap, "packaging_type"))
		if packaging == "" {
			packaging = "عبوة"
		}

		unitsPerCarton := parseIntDefault(getColByMap(row, colMap, "units_per_carton"), 12)
		if unitsPerCarton <= 0 {
			unitsPerCarton = 1
		}

		unitExcl := parseFloatDefault(getColByMap(row, colMap, "unit_price_excl_vat"), 0)
		unitIncl := parseFloatDefault(getColByMap(row, colMap, "unit_price_incl_vat"), 0)
		if unitIncl <= 0 && unitExcl > 0 {
			unitIncl = unitExcl * (1.0 + vatRate)
		} else if unitExcl <= 0 && unitIncl > 0 {
			unitExcl = unitIncl / (1.0 + vatRate)
		}

		cartonExcl := parseFloatDefault(getColByMap(row, colMap, "carton_price_excl_vat"), 0)
		if cartonExcl <= 0 && unitExcl > 0 {
			cartonExcl = unitExcl * float64(unitsPerCarton)
		}

		cartonIncl := parseFloatDefault(getColByMap(row, colMap, "carton_price_incl_vat"), 0)
		if cartonIncl <= 0 && unitIncl > 0 {
			cartonIncl = unitIncl * float64(unitsPerCarton)
		}

		extraDisc := parseFloatDefault(getColByMap(row, colMap, "extra_discount_pct"), 0)
		if extraDisc > 1.0 && extraDisc <= 100.0 {
			extraDisc = extraDisc / 100.0
		}

		netUnitCost := parseFloatDefault(getColByMap(row, colMap, "net_unit_invoice_cost"), 0)
		if netUnitCost <= 0 && unitIncl > 0 {
			netUnitCost = unitIncl * (1.0 - invDisc) * (1.0 - extraDisc)
		}

		netCartonCost := parseFloatDefault(getColByMap(row, colMap, "net_carton_invoice_cost"), 0)
		if netCartonCost <= 0 && netUnitCost > 0 {
			netCartonCost = netUnitCost * float64(unitsPerCarton)
		}

		category := strings.TrimSpace(getColByMap(row, colMap, "category"))
		if category == "" {
			category = domain.InferCategoryFromItemCodeAndName(prefix, rawName)
		} else {
			category = domain.NormalizeProductCategory(category)
		}

		brand := strings.TrimSpace(getColByMap(row, colMap, "brand"))
		if brand == "" {
			brand = domain.InferBrandFromItemName(rawName, category)
		}

		item := domain.ProductMasterItem{
			SerialNo:             serialNo,
			TenantID:             tenantID,
			ItemCode:             itemCode,
			ItemCodePrefix:       prefix,
			ERPPrefix:            prefix,
			DepartmentAr:         domain.InferDepartmentArFromPrefix(prefix),
			Barcode:              barcode,
			OfficialName:         rawName,
			Brand:                brand,
			Category:             category,
			ItemType:             itemType,
			PackagingType:        packaging,
			UnitsPerCarton:       unitsPerCarton,
			VATRate:              math.Round(vatRate*10000) / 10000,
			UnitPriceExclVAT:     math.Round(unitExcl*1000) / 1000,
			UnitPriceInclVAT:     math.Round(unitIncl*1000) / 1000,
			CartonPriceExclVAT:   math.Round(cartonExcl*100) / 100,
			CartonPriceInclVAT:   math.Round(cartonIncl*100) / 100,
			InvoiceDiscountPct:   math.Round(invDisc*10000) / 10000,
			ExtraDiscountPct:     math.Round(extraDisc*10000) / 10000,
			NetUnitInvoiceCost:   math.Round(netUnitCost*1000) / 1000,
			NetCartonInvoiceCost: math.Round(netCartonCost*100) / 100,
			SourceFilename:       filename,
			SheetName:            sheetName,
			UpdatedAt:            nowStr,
		}

		if existingIdx, exists := seenCodes[itemCode]; exists {
			items[existingIdx] = item
		} else {
			seenCodes[itemCode] = len(items)
			items = append(items, item)
		}
	}

	if len(items) == 0 {
		return nil, fmt.Errorf("product master file contained zero valid SKU rows")
	}

	return BuildProductMasterSummary(tenantID, companyName, sheetName, filename, defaultDiscountPct, defaultVATRate, items), nil
}

// BuildProductMasterSummary computes primary barcode flags, unique filter sets, and summary metrics for a slice of ProductMasterItem.
func BuildProductMasterSummary(
	tenantID, companyName, sheetDateLabel, sourceFilename string,
	defaultDiscountPct, defaultVATRate float64,
	items []domain.ProductMasterItem,
) *domain.ProductMasterSummaryResponse {
	// Mark IsPrimaryForBarcode for each barcode group
	barcodeGroups := make(map[string][]int)
	for i := range items {
		items[i].IsPrimaryForBarcode = false
		if items[i].ItemCodePrefix == "" {
			items[i].ItemCodePrefix = domain.ExtractItemCodePrefix(items[i].ItemCode)
		}
		if items[i].ERPPrefix == "" {
			items[i].ERPPrefix = items[i].ItemCodePrefix
		}
		if items[i].DepartmentAr == "" {
			items[i].DepartmentAr = domain.InferDepartmentArFromPrefix(items[i].ItemCodePrefix)
		}
		bc := strings.TrimSpace(items[i].Barcode)
		if bc != "" {
			barcodeGroups[bc] = append(barcodeGroups[bc], i)
		}
	}
	for _, indices := range barcodeGroups {
		chosen := indices[0]
		for _, idx := range indices {
			it := items[idx]
			if it.ItemType == "عادي" && !strings.HasPrefix(strings.TrimSpace(it.OfficialName), "*") {
				chosen = idx
				break
			}
		}
		items[chosen].IsPrimaryForBarcode = true
	}

	regularCount := 0
	promoCount := 0
	totalUnitsPerCarton := 0
	prefixSet := make(map[string]bool)
	brandSet := make(map[string]bool)
	packSet := make(map[string]bool)

	for _, it := range items {
		if it.ItemType == "عرض" {
			promoCount++
		} else {
			regularCount++
		}
		totalUnitsPerCarton += it.UnitsPerCarton
		if it.ItemCodePrefix != "" {
			prefixSet[it.ItemCodePrefix] = true
		}
		if it.Brand != "" {
			brandSet[it.Brand] = true
		}
		if it.PackagingType != "" {
			packSet[it.PackagingType] = true
		}
	}

	avgUnits := 0.0
	if len(items) > 0 {
		avgUnits = math.Round((float64(totalUnitsPerCarton)/float64(len(items)))*10) / 10
	}

	prefixes := make([]string, 0, len(prefixSet))
	for k := range prefixSet {
		prefixes = append(prefixes, k)
	}
	sort.Strings(prefixes)

	brands := make([]string, 0, len(brandSet))
	for k := range brandSet {
		brands = append(brands, k)
	}
	sort.Strings(brands)

	packs := make([]string, 0, len(packSet))
	for k := range packSet {
		packs = append(packs, k)
	}
	sort.Strings(packs)

	if companyName == "" {
		companyName = "شركة الاسكندرية للكيماويات و المنظفات ( ادكو )"
	}
	if sheetDateLabel == "" {
		sheetDateLabel = "تحديث 01-08-2026"
	}

	return &domain.ProductMasterSummaryResponse{
		TenantID:            tenantID,
		CompanyName:         companyName,
		SheetDateLabel:      sheetDateLabel,
		SourceFilename:      sourceFilename,
		DefaultDiscountPct:  defaultDiscountPct,
		DefaultVATRate:      defaultVATRate,
		TotalSKUs:           len(items),
		RegularSKUsCount:    regularCount,
		PromoSKUsCount:      promoCount,
		UniqueBarcodesCount: len(barcodeGroups),
		AvgUnitsPerCarton:   avgUnits,
		AvailablePrefixes:   prefixes,
		AvailableBrands:     brands,
		AvailablePackaging:  packs,
		Items:               items,
	}
}

func mapProductMasterColumns(headers []string) map[string]int {
	m := map[string]int{
		"serial_no":               0,
		"item_code":               1,
		"barcode":                 2,
		"official_name":           3,
		"invoice_discount_pct":    4,
		"item_type":               6,
		"vat_rate":                7,
		"packaging_type":          8,
		"units_per_carton":        9,
		"unit_price_excl_vat":     10,
		"unit_price_incl_vat":     13,
		"carton_price_excl_vat":   14,
		"carton_price_incl_vat":   15,
		"extra_discount_pct":      16,
		"net_unit_invoice_cost":   17,
		"net_carton_invoice_cost": 18,
		"brand":                   -1,
		"category":                -1,
	}

	for idx, raw := range headers {
		h := strings.ToLower(strings.TrimSpace(strings.ReplaceAll(raw, "\n", " ")))
		switch {
		case h == "م" || h == "serial_no" || h == "serial":
			m["serial_no"] = idx
		case strings.Contains(h, "كود الصنف") || h == "item_code" || h == "item code":
			m["item_code"] = idx
		case strings.Contains(h, "الباركود") || strings.Contains(h, "باركود") || h == "barcode":
			m["barcode"] = idx
		case strings.Contains(h, "اسم الصنف") || h == "official_name" || h == "sku_name" || h == "item_name":
			m["official_name"] = idx
		case strings.Contains(h, "نسبة خصم الفاتورة") || h == "invoice_discount_pct":
			m["invoice_discount_pct"] = idx
		case strings.Contains(h, "عادي / عرض") || strings.Contains(h, "عادي/عرض") || h == "item_type":
			m["item_type"] = idx
		case strings.Contains(h, "الضريبة") && strings.Contains(h, "نسبة") || h == "vat_rate":
			m["vat_rate"] = idx
		case strings.Contains(h, "نوع العبوة") || strings.Contains(h, "نوع العبوه") || h == "packaging_type":
			m["packaging_type"] = idx
		case strings.Contains(h, "عدد الوحدات بالكرتونة") || strings.Contains(h, "وحدات بالكرتونة") || h == "units_per_carton":
			m["units_per_carton"] = idx
		case (strings.Contains(h, "سعر العبوه") || strings.Contains(h, "سعر العبوة")) && strings.Contains(h, "غير شامل") || h == "unit_price_excl_vat":
			m["unit_price_excl_vat"] = idx
		case (strings.Contains(h, "سعر العبوه") || strings.Contains(h, "سعر العبوة")) && strings.Contains(h, "شامل") && !strings.Contains(h, "غير") || h == "unit_price_incl_vat":
			m["unit_price_incl_vat"] = idx
		case strings.Contains(h, "سعر الكرتونة") && strings.Contains(h, "غير شامل") || h == "carton_price_excl_vat":
			m["carton_price_excl_vat"] = idx
		case strings.Contains(h, "سعر الكرتونة") && strings.Contains(h, "شامل") && !strings.Contains(h, "غير") || h == "carton_price_incl_vat":
			m["carton_price_incl_vat"] = idx
		case strings.Contains(h, "الخصم الاضافية") || strings.Contains(h, "الخصم الإضافية") || h == "extra_discount_pct":
			m["extra_discount_pct"] = idx
		case (strings.Contains(h, "سعر القطعه") || strings.Contains(h, "سعر القطعة")) && strings.Contains(h, "بعد خصم") || h == "net_unit_invoice_cost":
			m["net_unit_invoice_cost"] = idx
		case strings.Contains(h, "سعر الكرتونة") && strings.Contains(h, "بعد خصم") || h == "net_carton_invoice_cost":
			m["net_carton_invoice_cost"] = idx
		case h == "brand" || h == "العلامة التجارية":
			m["brand"] = idx
		case h == "category" || h == "الفئة":
			m["category"] = idx
		}
	}
	return m
}

func extractFirstSheetName(rawContent []byte) string {
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return ""
	}
	for _, f := range zr.File {
		if strings.EqualFold(f.Name, "xl/workbook.xml") {
			rc, err := f.Open()
			if err != nil {
				return ""
			}
			data, _ := io.ReadAll(rc)
			_ = rc.Close()
			var wb xlsxWorkbookXML
			if err := xml.Unmarshal(data, &wb); err == nil && len(wb.Sheets) > 0 {
				return wb.Sheets[0].Name
			}
		}
	}
	return ""
}

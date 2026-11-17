package bigquery

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// ProductMasterFilter allows filtering the Product Master & Price List catalog by prefix, brand, item type, packaging, pull status, price change, and search query.
type ProductMasterFilter struct {
	Prefix        string
	Brand         string
	ItemType      string // "all", "عادي", "عرض"
	PackagingType string
	PullStatus    string // "all", "active", "unpulled"
	PriceChange   string // "all", "changed", "up", "down", "new"
	SearchQuery   string
}

func getProductMasterStorageDir() string {
	if envDir := os.Getenv("TASHIL_PRODUCT_MASTER_DIR"); envDir != "" {
		return envDir
	}
	candidates := []string{
		"data/product_master",
		"../data/product_master",
		"../../data/product_master",
		"../../../data/product_master",
	}
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && info.IsDir() {
			return c
		}
	}
	return "data/product_master"
}

func cloneCleanBaselineSummary(summary *domain.ProductMasterSummaryResponse) *domain.ProductMasterSummaryResponse {
	if summary == nil {
		return nil
	}
	cleanItems := make([]domain.ProductMasterItem, len(summary.Items))
	copy(cleanItems, summary.Items)
	for i := range cleanItems {
		cleanItems[i].PrevUnitPriceExclVAT = 0
		cleanItems[i].PrevUnitPriceInclVAT = 0
		cleanItems[i].PrevCartonPriceInclVAT = 0
		cleanItems[i].PrevNetUnitInvoiceCost = 0
		cleanItems[i].PrevNetCartonInvoiceCost = 0
		cleanItems[i].PriceChangeDirection = "same"
		cleanItems[i].PriceChangeDiffEGP = 0
		cleanItems[i].PriceChangePct = 0
	}
	srcFile := summary.SourceFilename
	if srcFile == "" {
		srcFile = "adeco_product_master_2026_08_01.xlsx"
	}
	res := gemini.BuildProductMasterSummary(
		summary.TenantID,
		summary.CompanyName,
		summary.SheetDateLabel,
		srcFile,
		summary.DefaultDiscountPct,
		summary.DefaultVATRate,
		cleanItems,
	)
	if len(summary.SupplementalPOSItems) > 0 {
		cleanSups := make([]domain.ProductMasterItem, len(summary.SupplementalPOSItems))
		copy(cleanSups, summary.SupplementalPOSItems)
		res.SupplementalPOSItems = cleanSups
	}
	return res
}

func (c *Client) loadPersistedProductMaster() {
	dir := getProductMasterStorageDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			continue
		}
		var summary domain.ProductMasterSummaryResponse
		if err := json.Unmarshal(raw, &summary); err != nil || len(summary.Items) == 0 {
			continue
		}
		hadSups := len(summary.SupplementalPOSItems) >= 10
		tenantKey := strings.TrimSuffix(entry.Name(), ".json")
		normTenant := normalizeTenantKey(tenantKey)
		c.mu.Lock()
		if c.baselineProductMaster == nil {
			c.baselineProductMaster = make(map[string]*domain.ProductMasterSummaryResponse)
		}
		c.indexProductMasterLocked(normTenant, &summary)
		c.baselineProductMaster[normTenant] = cloneCleanBaselineSummary(c.productMaster[normTenant])
		if normTenant == "tenant-adeco" && !hadSups {
			c.persistTenantProductMasterLocked(normTenant)
		}
		c.enrichAllTenantDataLocked(normTenant)
		c.mu.Unlock()
	}
}

func (c *Client) persistTenantProductMasterLocked(normTenant string) {
	if flag.Lookup("test.v") != nil && os.Getenv("TASHIL_PRODUCT_MASTER_DIR") == "" {
		return
	}
	summary := c.productMaster[normTenant]
	if summary == nil {
		return
	}
	dir := getProductMasterStorageDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	if data, err := json.MarshalIndent(summary, "", "  "); err == nil {
		_ = os.WriteFile(filepath.Join(dir, normTenant+".json"), data, 0o644)
	}
}

func normalizeArabicNameForLookup(s string) string {
	s = strings.ToLower(strings.TrimSpace(strings.TrimLeft(s, "* ")))
	r := strings.NewReplacer(
		"أ", "ا",
		"إ", "ا",
		"آ", "ا",
		"ى", "ي",
		"ة", "ه",
		"ڤ", "ف",
	)
	s = r.Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

// adecoSupplementalPOSItems returns the 10 Fathalla POS Adeco (622300...) barcode crosswalk items
// so that 100% of all 214 Fathalla POS Adeco barcodes resolve to official ProductMasterItem definitions
// without mutating the 389-SKU baseline sheet summary count.
func adecoSupplementalPOSItems(byCode map[string]domain.ProductMasterItem) []domain.ProductMasterItem {
	aliasOrDefault := func(barcode, targetCode, fallbackCode, prefix, officialName, brand, category, itemType, packaging string, upc int, unitIncl float64) domain.ProductMasterItem {
		if existing, ok := byCode[targetCode]; ok && targetCode != "" {
			cp := existing
			cp.Barcode = barcode
			cp.IsPrimaryForBarcode = true
			return cp
		}
		vatRate := 0.14
		invDisc := 0.10
		unitExcl := math.Round((unitIncl/(1.0+vatRate))*1000) / 1000
		cartonExcl := math.Round(unitExcl*float64(upc)*100) / 100
		cartonIncl := math.Round(unitIncl*float64(upc)*100) / 100
		netUnit := math.Round(unitIncl*(1.0-invDisc)*1000) / 1000
		netCarton := math.Round(netUnit*float64(upc)*100) / 100
		return domain.ProductMasterItem{
			SerialNo:             900,
			TenantID:             "tenant-adeco",
			ItemCode:             fallbackCode,
			ItemCodePrefix:       prefix,
			ERPPrefix:            prefix,
			DepartmentAr:         domain.InferDepartmentArFromPrefix(prefix),
			Barcode:              barcode,
			OfficialName:         officialName,
			Brand:                brand,
			Category:             category,
			ItemType:             itemType,
			PackagingType:        packaging,
			UnitsPerCarton:       upc,
			VATRate:              vatRate,
			UnitPriceExclVAT:     unitExcl,
			UnitPriceInclVAT:     unitIncl,
			CartonPriceExclVAT:   cartonExcl,
			CartonPriceInclVAT:   cartonIncl,
			InvoiceDiscountPct:   invDisc,
			NetUnitInvoiceCost:   netUnit,
			NetCartonInvoiceCost: netCarton,
			IsPrimaryForBarcode:  true,
			SourceFilename:       "adeco_product_master_2026_08_01.xlsx",
			SheetName:            "تحديث 01-08-2026",
			UpdatedAt:            "2026-08-01",
		}
	}

	return []domain.ProductMasterItem{
		aliasOrDefault("6223000234266", "PRHC-1100-0001", "PRDW-1000-0010", "PRHC", "عرض شرنك ( 1 عبوة فيبا دش 1.1 كجم & 1 عبوة فيبا ملح 1.5 كجم ) - 6 مجموعة", "فيبا (Feba)", "مسحوق غسالات اطباق", "عرض", "مجموعة", 6, 392.502),
		aliasOrDefault("6223000234402", "PRHC-1100-0002", "PRDW-1000-0011", "PRHC", "عرض شنطة فيبا غسالات أطباق ( 1.1كجم دش & 1.5كجم ملح & 285 مل رينز ) 5 مجموعة", "فيبا (Feba)", "مسحوق غسالات اطباق", "عرض", "مجموعة", 5, 542.503),
		aliasOrDefault("6223004148064", "PRGC-0600-0001", "PRGC-0600-0010", "PRGC", "عرض شرنك جلاسى 600 مل ( 1عبوة رشاش & 1 عبوة اقتصادى ) - 12 مجموعة", "جلاسي (Glassy)", "ملمع زجاج وكريستال", "عرض", "مجموعة", 6, 75.183),
		aliasOrDefault("6223000236222", "PRGC-0475-0001", "PRGC-0500-0091", "PRGC", "عرض شرنك جلاسى 475 مل (1 عبوة سبراى &1 عبوة فليب توب ) - 5 مجوعة", "جلاسي (Glassy)", "ملمع زجاج وكريستال", "عرض", "مجموعة", 5, 53.329),
		aliasOrDefault("6223000234211", "", "FGHC-0500-0091", "FGHC", "كلوريل مطهر ومنظف للاسطح 500 مل رشاش", "كلوريل (Clorel)", "مطهر عام", "عادي", "عبوة", 12, 64.07),
		aliasOrDefault("6223004148521", "", "FGGC-0475-0010", "FGGC", "جلاسى ملمع زجاج اكوا مارين اسبراى 475مل", "جلاسي (Glassy)", "ملمع زجاج وكريستال", "عادي", "عبوة", 12, 32.00),
		aliasOrDefault("6223000237038", "", "FGGC-0475-0011", "FGGC", "جلاسى ملمع زجاج اكوا مارين فليب توب 475مل", "جلاسي (Glassy)", "ملمع زجاج وكريستال", "عادي", "زجاجة", 12, 20.07),
		aliasOrDefault("6223000236734", "", "FGLC-0750-0091", "FGLC", "فلفيتا جيل للحرير والصوف 750 مل", "فلڤيتا (Velveta)", "مساحيق جيل اتوماتيك", "عادي", "زجاجة", 12, 80.00),
		aliasOrDefault("6223004145667", "", "PRHC-0000-0091", "PRHC", "عرض الصيف (فيبا + فلفيتا جل يدوي + ماكسيل ارضيات)", "فيبا (Feba)", "صابون سائل اطباق", "عرض", "مجموعة", 6, 40.00),
		aliasOrDefault("6223000232231", "", "FGDG-0750-0091", "FGDG", "فيبا صابون سائل 750 مل", "فيبا (Feba)", "صابون سائل اطباق", "عادي", "زجاجة", 12, 45.00),
	}
}

func (c *Client) indexProductMasterLocked(normTenant string, summary *domain.ProductMasterSummaryResponse) {
	if c.productMaster == nil {
		c.productMaster = make(map[string]*domain.ProductMasterSummaryResponse)
	}
	if c.productMasterByCode == nil {
		c.productMasterByCode = make(map[string]map[string]domain.ProductMasterItem)
	}
	if c.productMasterByBarcode == nil {
		c.productMasterByBarcode = make(map[string]map[string]domain.ProductMasterItem)
	}
	if c.productMasterByBarcodeCandidates == nil {
		c.productMasterByBarcodeCandidates = make(map[string]map[string][]domain.ProductMasterItem)
	}
	if c.productMasterByName == nil {
		c.productMasterByName = make(map[string]map[string]domain.ProductMasterItem)
	}

	rebuilt := gemini.BuildProductMasterSummary(
		normTenant,
		summary.CompanyName,
		summary.SheetDateLabel,
		summary.SourceFilename,
		summary.DefaultDiscountPct,
		summary.DefaultVATRate,
		summary.Items,
	)
	if summary.DiffSummary != nil {
		diffCopy := *summary.DiffSummary
		diffCopy.TotalSKUsCompared = rebuilt.TotalSKUs
		diffCopy.PriceIncreasedCount = rebuilt.PriceIncreasedCount
		diffCopy.PriceDecreasedCount = rebuilt.PriceDecreasedCount
		diffCopy.PriceUnchangedCount = rebuilt.PriceUnchangedCount
		diffCopy.NewSKUsCount = rebuilt.NewSKUsCount
		rebuilt.DiffSummary = &diffCopy
	}

	byCode := make(map[string]domain.ProductMasterItem, len(rebuilt.Items)+10)
	byBarcode := make(map[string]domain.ProductMasterItem, len(rebuilt.Items)+10)
	byBarcodeCandidates := make(map[string][]domain.ProductMasterItem, len(rebuilt.Items)+10)
	byName := make(map[string]domain.ProductMasterItem, len(rebuilt.Items)+10)

	for _, it := range rebuilt.Items {
		code := domain.NormalizeItemCode(it.ItemCode)
		if code != "" {
			byCode[code] = it
		}
		bc := strings.TrimSpace(it.Barcode)
		if bc != "" {
			byBarcodeCandidates[bc] = append(byBarcodeCandidates[bc], it)
			if existing, exists := byBarcode[bc]; !exists || (!existing.IsPrimaryForBarcode && it.IsPrimaryForBarcode) {
				byBarcode[bc] = it
			}
		}
		normName := normalizeArabicNameForLookup(it.OfficialName)
		if normName != "" {
			if _, exists := byName[normName]; !exists || it.IsPrimaryForBarcode {
				byName[normName] = it
			}
		}
	}

	var supItems []domain.ProductMasterItem
	seenSupBarcode := make(map[string]bool)
	for _, sup := range summary.SupplementalPOSItems {
		bc := strings.TrimSpace(sup.Barcode)
		if bc != "" {
			seenSupBarcode[bc] = true
		}
		supItems = append(supItems, sup)
	}
	if normTenant == "tenant-adeco" {
		for _, defSup := range adecoSupplementalPOSItems(byCode) {
			bc := strings.TrimSpace(defSup.Barcode)
			if bc != "" && !seenSupBarcode[bc] {
				seenSupBarcode[bc] = true
				supItems = append(supItems, defSup)
			}
		}
	}
	rebuilt.SupplementalPOSItems = supItems
	c.productMaster[normTenant] = rebuilt

	for _, sup := range supItems {
		code := domain.NormalizeItemCode(sup.ItemCode)
		if code != "" {
			if _, exists := byCode[code]; !exists {
				byCode[code] = sup
			}
		}
		bc := strings.TrimSpace(sup.Barcode)
		if bc != "" {
			if _, exists := byBarcode[bc]; !exists {
				byBarcode[bc] = sup
			}
			if len(byBarcodeCandidates[bc]) == 0 {
				byBarcodeCandidates[bc] = append(byBarcodeCandidates[bc], sup)
			}
		}
		normName := normalizeArabicNameForLookup(sup.OfficialName)
		if normName != "" {
			if _, exists := byName[normName]; !exists {
				byName[normName] = sup
			}
		}
	}

	c.productMasterByCode[normTenant] = byCode
	c.productMasterByBarcode[normTenant] = byBarcode
	c.productMasterByBarcodeCandidates[normTenant] = byBarcodeCandidates
	c.productMasterByName[normTenant] = byName
}

// ComputeProductMasterDiff compares an incoming Product Master catalog against a baseline catalog and annotates each item with price delta indicators.
func ComputeProductMasterDiff(prev *domain.ProductMasterSummaryResponse, next *domain.ProductMasterSummaryResponse) *domain.ProductMasterDiffSummary {
	if next == nil {
		return nil
	}
	if prev == nil || len(prev.Items) == 0 {
		for i := range next.Items {
			if next.Items[i].PriceChangeDirection == "" {
				next.Items[i].PriceChangeDirection = "same"
			}
		}
		return next.DiffSummary
	}

	prevByCode := make(map[string]domain.ProductMasterItem, len(prev.Items))
	prevByBarcode := make(map[string]domain.ProductMasterItem, len(prev.Items))
	for _, it := range prev.Items {
		code := domain.NormalizeItemCode(it.ItemCode)
		if code != "" {
			prevByCode[code] = it
		}
		bc := domain.CleanBarcode(it.Barcode)
		if bc != "" {
			if _, exists := prevByBarcode[bc]; !exists || it.IsPrimaryForBarcode {
				prevByBarcode[bc] = it
			}
		}
	}

	nextCodes := make(map[string]bool, len(next.Items))
	for _, it := range next.Items {
		if code := domain.NormalizeItemCode(it.ItemCode); code != "" {
			nextCodes[code] = true
		}
	}

	upCount := 0
	downCount := 0
	sameCount := 0
	newCount := 0
	var upPctSum, downPctSum float64
	var changedItems []domain.ProductMasterDiffItem

	for i := range next.Items {
		it := &next.Items[i]
		code := domain.NormalizeItemCode(it.ItemCode)
		bc := domain.CleanBarcode(it.Barcode)

		oldItem, found := prevByCode[code]
		if !found && bc != "" {
			if cand, bcFound := prevByBarcode[bc]; bcFound {
				candCode := domain.NormalizeItemCode(cand.ItemCode)
				// Only match by barcode if the previous barcode owner is not separately present in next.Items
				if candCode == "" || !nextCodes[candCode] {
					oldItem = cand
					found = true
				}
			}
		}

		if !found {
			it.PrevUnitPriceExclVAT = 0
			it.PrevUnitPriceInclVAT = 0
			it.PrevCartonPriceInclVAT = 0
			it.PrevNetUnitInvoiceCost = 0
			it.PrevNetCartonInvoiceCost = 0
			it.PriceChangeDirection = "new"
			it.PriceChangeDiffEGP = 0
			it.PriceChangePct = 0
			newCount++
			changedItems = append(changedItems, domain.ProductMasterDiffItem{
				ItemCode:           it.ItemCode,
				OfficialName:       it.OfficialName,
				Brand:              it.Brand,
				OldUnitPriceIncl:   0,
				NewUnitPriceIncl:   it.UnitPriceInclVAT,
				OldCartonPriceIncl: 0,
				NewCartonPriceIncl: it.CartonPriceInclVAT,
				DiffEGP:            0,
				DiffPct:            0,
				Direction:          "new",
			})
			continue
		}

		oldPrice := oldItem.UnitPriceInclVAT
		newPrice := it.UnitPriceInclVAT
		if oldPrice <= 0 {
			oldPrice = oldItem.NetUnitInvoiceCost
			newPrice = it.NetUnitInvoiceCost
		}

		diffEGP := math.Round((newPrice-oldPrice)*100) / 100
		var diffPct float64
		if oldPrice > 0 {
			diffPct = math.Round(((newPrice-oldPrice)/oldPrice)*1000) / 10
		}

		if math.Abs(diffEGP) >= 0.01 {
			it.PrevUnitPriceExclVAT = oldItem.UnitPriceExclVAT
			it.PrevUnitPriceInclVAT = oldItem.UnitPriceInclVAT
			it.PrevCartonPriceInclVAT = oldItem.CartonPriceInclVAT
			it.PrevNetUnitInvoiceCost = oldItem.NetUnitInvoiceCost
			it.PrevNetCartonInvoiceCost = oldItem.NetCartonInvoiceCost
			it.PriceChangeDiffEGP = diffEGP
			it.PriceChangePct = diffPct
			if diffEGP > 0 {
				it.PriceChangeDirection = "up"
				upCount++
				upPctSum += diffPct
			} else {
				it.PriceChangeDirection = "down"
				downCount++
				downPctSum += math.Abs(diffPct)
			}
			changedItems = append(changedItems, domain.ProductMasterDiffItem{
				ItemCode:           it.ItemCode,
				OfficialName:       it.OfficialName,
				Brand:              it.Brand,
				OldUnitPriceIncl:   oldItem.UnitPriceInclVAT,
				NewUnitPriceIncl:   it.UnitPriceInclVAT,
				OldCartonPriceIncl: oldItem.CartonPriceInclVAT,
				NewCartonPriceIncl: it.CartonPriceInclVAT,
				DiffEGP:            diffEGP,
				DiffPct:            diffPct,
				Direction:          it.PriceChangeDirection,
			})
		} else {
			it.PrevUnitPriceExclVAT = 0
			it.PrevUnitPriceInclVAT = 0
			it.PrevCartonPriceInclVAT = 0
			it.PrevNetUnitInvoiceCost = 0
			it.PrevNetCartonInvoiceCost = 0
			it.PriceChangeDirection = "same"
			it.PriceChangeDiffEGP = 0
			it.PriceChangePct = 0
			sameCount++
		}
	}

	// If the exact same file with identical prices and SKU count was re-indexed, preserve prev's diff annotations
	if upCount == 0 && downCount == 0 && newCount == 0 && len(prev.Items) == len(next.Items) && strings.EqualFold(prev.SourceFilename, next.SourceFilename) && prev.DiffSummary != nil {
		for i := range next.Items {
			it := &next.Items[i]
			code := domain.NormalizeItemCode(it.ItemCode)
			if oldItem, ok := prevByCode[code]; ok {
				it.PrevUnitPriceExclVAT = oldItem.PrevUnitPriceExclVAT
				it.PrevUnitPriceInclVAT = oldItem.PrevUnitPriceInclVAT
				it.PrevCartonPriceInclVAT = oldItem.PrevCartonPriceInclVAT
				it.PrevNetUnitInvoiceCost = oldItem.PrevNetUnitInvoiceCost
				it.PrevNetCartonInvoiceCost = oldItem.PrevNetCartonInvoiceCost
				it.PriceChangeDirection = oldItem.PriceChangeDirection
				it.PriceChangeDiffEGP = oldItem.PriceChangeDiffEGP
				it.PriceChangePct = oldItem.PriceChangePct
			}
		}
		diffCopy := *prev.DiffSummary
		next.DiffSummary = &diffCopy
		next.PriceIncreasedCount = prev.PriceIncreasedCount
		next.PriceDecreasedCount = prev.PriceDecreasedCount
		next.PriceUnchangedCount = prev.PriceUnchangedCount
		next.NewSKUsCount = prev.NewSKUsCount
		return next.DiffSummary
	}

	sort.Slice(changedItems, func(i, j int) bool {
		return math.Abs(changedItems[i].DiffPct) > math.Abs(changedItems[j].DiffPct)
	})
	if len(changedItems) > 25 {
		changedItems = changedItems[:25]
	}

	avgUp := 0.0
	if upCount > 0 {
		avgUp = math.Round((upPctSum/float64(upCount))*10) / 10
	}
	avgDown := 0.0
	if downCount > 0 {
		avgDown = math.Round((downPctSum/float64(downCount))*10) / 10
	}

	diffSummary := &domain.ProductMasterDiffSummary{
		ComparedAgainstFile: prev.SourceFilename,
		NewFileName:         next.SourceFilename,
		ComparedAt:          time.Now().Format("2006-01-02 15:04"),
		TotalSKUsCompared:   len(next.Items),
		PriceIncreasedCount: upCount,
		PriceDecreasedCount: downCount,
		PriceUnchangedCount: sameCount,
		NewSKUsCount:        newCount,
		AvgPriceIncreasePct: avgUp,
		AvgPriceDecreasePct: avgDown,
		TopChangedItems:     changedItems,
	}
	next.DiffSummary = diffSummary
	next.PriceIncreasedCount = upCount
	next.PriceDecreasedCount = downCount
	next.PriceUnchangedCount = sameCount
	next.NewSKUsCount = newCount
	return diffSummary
}

// normalizeArabicFMCGTokens splits stuck numbers/letters, normalizes Arabic spelling & English transliterations,
// and standardizes weights/volumes (e.g. 650جم -> 650 جم, 1000 جم -> 1 كجم, بلاك -> اسود).
func normalizeArabicFMCGTokens(raw string) []string {
	s := strings.ToLower(strings.TrimSpace(strings.TrimLeft(raw, "* ")))
	if s == "" {
		return nil
	}
	replacer := strings.NewReplacer(
		"أ", "ا",
		"إ", "ا",
		"آ", "ا",
		"ى", "ي",
		"ة", "ه",
		"ؤ", "و",
		"ئ", "ي",
		"ڤ", "ف",
		"ـ", "",
		"(", " ",
		")", " ",
		"[", " ",
		"]", " ",
		"/", " ",
		"-", " ",
		"_", " ",
		"*", " ",
		"،", " ",
		",", " ",
	)
	s = replacer.Replace(s)

	// Separate digits from letters (e.g., "650جم" -> "650 جم", "4كجم" -> "4 كجم", "2لتر" -> "2 لتر")
	var separated strings.Builder
	runes := []rune(s)
	for i, r := range runes {
		if r == '+' {
			separated.WriteString(" + ")
			continue
		}
		isDig := unicode.IsDigit(r) || r == '.'
		if i > 0 {
			prev := runes[i-1]
			prevDig := unicode.IsDigit(prev) || prev == '.'
			if isDig != prevDig && prev != ' ' && r != ' ' {
				separated.WriteByte(' ')
			}
		}
		separated.WriteRune(r)
	}

	rawFields := strings.Fields(separated.String())
	if len(rawFields) == 0 {
		return nil
	}

	synonymMap := map[string]string{
		"ج":         "جم",
		"جرام":      "جم",
		"غ":         "جم",
		"ك":         "كجم",
		"كيلو":      "كجم",
		"مللي":      "مل",
		"ملل":       "مل",
		"ل":         "لتر",
		"بلاك":      "اسود",
		"وايت":      "ابيض",
		"بينك":      "وردي",
		"جرين":      "اخضر",
		"بلو":       "ازرق",
		"يلو":       "اصفر",
		"ريد":       "احمر",
		"اورانج":    "برتقالي",
		"موف":       "بنفسجي",
		"جولد":      "ذهبي",
		"سيلفر":     "فضي",
		"اتوماتيك":  "اوتوماتيك",
		"اتوماتك":   "اوتوماتيك",
		"اوتوماتك":  "اوتوماتيك",
		"هاف":       "نصف",
		"الاطباق":   "اطباق",
		"للاطباق":   "اطباق",
		"العبايات":  "عبايات",
		"للعبايات":  "عبايات",
		"الملابس":   "ملابس",
		"للملابس":   "ملابس",
		"المفروشات": "مفروشات",
		"للمفروشات": "مفروشات",
		"السجاد":    "سجاد",
		"للسجاد":    "سجاد",
		"التابلوه":  "تابلوه",
		"الكاوتش":   "كاوتش",
		"الزجاج":    "زجاج",
		"السيارات":  "سيارات",
		"الارضيات":  "ارضيات",
		"الايدي":    "ايدي",
		"باشا":      "الباشا",
		"توفير":     "التوفير",
		"ماجك":      "ماجيك",
		"فلفتا":     "فلفيتا",
		"فيلفيتا":   "فلفيتا",
		"كلوركس":    "كلوريل",
	}

	tokens := make([]string, 0, len(rawFields))
	for _, f := range rawFields {
		if mapped, ok := synonymMap[f]; ok {
			f = mapped
		}
		tokens = append(tokens, f)
	}
	return tokens
}

// extractCanonicalBrand returns the canonical Arabic brand token from a brand field or tokenized item name.
func extractCanonicalBrand(brandField string, tokens []string) string {
	knownBrands := []struct {
		key   string
		canon string
	}{
		{"فيبا", "فيبا"},
		{"feba", "فيبا"},
		{"ديفا", "ديفا"},
		{"diva", "ديفا"},
		{"فلفيتا", "فلفيتا"},
		{"velveta", "فلفيتا"},
		{"كلوريل", "كلوريل"},
		{"clorel", "كلوريل"},
		{"ماكسيل", "ماكسيل"},
		{"maxel", "ماكسيل"},
		{"رابيدو", "رابيدو"},
		{"rapido", "رابيدو"},
		{"جلاسي", "جلاسي"},
		{"glassy", "جلاسي"},
		{"سبيد", "سبيد"},
		{"speed", "سبيد"},
		{"جنرال", "جنرال"},
		{"general", "جنرال"},
		{"زيرو", "زيرو"},
		{"zero", "زيرو"},
		{"لويال", "لويال"},
		{"توب", "توب"},
		{"اكوا", "اكوا"},
		{"بيور", "بيور"},
		{"كليو", "كليو"},
	}

	bfNorm := normalizeArabicNameForLookup(brandField)
	for _, kb := range knownBrands {
		if strings.Contains(bfNorm, kb.key) {
			return kb.canon
		}
	}
	// Check tokens in order of appearance so bundle descriptions ("عرض ديفاتول + فيبا") resolve to their primary leading brand
	for _, tok := range tokens {
		for _, kb := range knownBrands {
			if strings.Contains(tok, kb.key) {
				return kb.canon
			}
		}
	}
	joined := strings.Join(tokens, " ")
	for _, kb := range knownBrands {
		if strings.Contains(joined, kb.key) {
			return kb.canon
		}
	}
	return ""
}

// extractNormalizedMeasures extracts normalized weight/volume signatures (in grams/ml or count) and raw numeric tokens.
func extractNormalizedMeasures(tokens []string) (measures []string, numbers []string) {
	isNum := func(t string) bool {
		if t == "" {
			return false
		}
		for _, r := range t {
			if !unicode.IsDigit(r) && r != '.' {
				return false
			}
		}
		return true
	}

	for i := 0; i < len(tokens); i++ {
		t := tokens[i]
		if !isNum(t) {
			continue
		}
		numbers = append(numbers, t)
		unit := ""
		if i+1 < len(tokens) {
			next := tokens[i+1]
			switch next {
			case "جم", "كجم", "مل", "لتر":
				unit = next
			}
		}
		switch unit {
		case "كجم":
			// Convert common kg to g string so "1 كجم" == "1000 جم", "4 كجم" == "4000 جم"
			switch t {
			case "1":
				measures = append(measures, "1000جم", "1كجم", "1000مل", "1لتر")
			case "2":
				measures = append(measures, "2000جم", "2كجم", "2000مل", "2لتر")
			case "2.5":
				measures = append(measures, "2500جم", "2.5كجم", "2500مل", "2.5لتر")
			case "3":
				measures = append(measures, "3000جم", "3كجم", "3000مل", "3لتر")
			case "4":
				measures = append(measures, "4000جم", "4كجم", "4000مل", "4لتر")
			case "5":
				measures = append(measures, "5000جم", "5كجم", "5000مل", "5لتر")
			case "6":
				measures = append(measures, "6000جم", "6كجم")
			case "8":
				measures = append(measures, "8000جم", "8كجم")
			case "10":
				measures = append(measures, "10000جم", "10كجم", "10000مل", "10لتر")
			default:
				measures = append(measures, t+"كجم")
			}
		case "لتر":
			switch t {
			case "1":
				measures = append(measures, "1000مل", "1لتر", "1000جم", "1كجم")
			case "1.5":
				measures = append(measures, "1500مل", "1.5لتر", "1500جم", "1.5كجم")
			case "2":
				measures = append(measures, "2000مل", "2لتر", "2000جم", "2كجم")
			case "2.5":
				measures = append(measures, "2500مل", "2.5لتر", "2500جم", "2.5كجم")
			case "3":
				measures = append(measures, "3000مل", "3لتر", "3000جم", "3كجم")
			case "4":
				measures = append(measures, "4000مل", "4لتر", "4000جم", "4كجم")
			case "5":
				measures = append(measures, "5000مل", "5لتر", "5000جم", "5كجم")
			case "10":
				measures = append(measures, "10000مل", "10لتر", "10000جم", "10كجم")
			case "20":
				measures = append(measures, "20000مل", "20لتر")
			default:
				measures = append(measures, t+"لتر")
			}
		case "جم":
			measures = append(measures, t+"جم", t+"مل")
			if t == "1000" {
				measures = append(measures, "1كجم", "1لتر")
			} else if t == "2000" {
				measures = append(measures, "2كجم", "2لتر")
			} else if t == "2500" {
				measures = append(measures, "2.5كجم", "2.5لتر")
			} else if t == "3000" {
				measures = append(measures, "3كجم", "3لتر")
			} else if t == "4000" {
				measures = append(measures, "4كجم", "4لتر")
			}
		case "مل":
			measures = append(measures, t+"مل", t+"جم")
			if t == "1000" {
				measures = append(measures, "1لتر", "1كجم")
			} else if t == "2000" {
				measures = append(measures, "2لتر", "2كجم")
			} else if t == "2500" {
				measures = append(measures, "2.5لتر", "2.5كجم")
			} else if t == "4000" {
				measures = append(measures, "4لتر", "4كجم")
			}
		default:
			measures = append(measures, t)
		}
	}
	return measures, numbers
}

func isPromoTokensOrHint(tokens []string, promoHint string) bool {
	if strings.Contains(promoHint, "عرض") || strings.EqualFold(promoHint, "promo") {
		return true
	}
	for _, t := range tokens {
		switch t {
		case "عرض", "هديه", "خصم", "باكدج", "مجان", "مجانا", "+", "شرنك", "شنطه":
			return true
		}
	}
	return false
}

// BuildCanonicalProductFamilyKey generates a deterministic family key that groups fragrance/scent variants
// of the same product family (same Brand, ERP Prefix, ItemType, Weight/Volume, Sub-Line, UnitsPerCarton, and CartonPrice)
// so that all 281 Sell-Out barcode variants map cleanly into the 153 Sell-In product families.
func BuildCanonicalProductFamilyKey(pm *domain.ProductMasterItem, rawName string) string {
	return CanonicalSellInFamilyKey(pm, rawName)
}

// CanonicalSellInFamilyKey generates a deterministic family key that groups fragrance/scent variants
// of the same product family (same Brand, ERP Prefix, ItemType, Weight/Volume, Sub-Line, UnitsPerCarton, and CartonPrice)
// so that all 281 Sell-Out barcode variants map cleanly into the 153 Sell-In product families.
func CanonicalSellInFamilyKey(pm *domain.ProductMasterItem, rawName string) string {
	if pm != nil && pm.ItemCode != "" {
		tokens := normalizeArabicFMCGTokens(pm.OfficialName)
		brand := extractCanonicalBrand(pm.Brand, tokens)
		measures, nums := extractNormalizedMeasures(tokens)
		primaryMeasure := ""
		if len(measures) > 0 {
			primaryMeasure = measures[0]
		} else if len(nums) > 0 {
			primaryMeasure = nums[0]
		}
		subLine := ""
		subKeywords := []string{"الباشا", "التوفير", "مركز", "عبايات", "الوان", "ابيض", "اسود", "اوتوماتيك", "يدوي", "جل", "مسحوق", "بكره", "رول", "اسفنجه", "تابلوه", "كاوتش", "فوم", "موتور", "زجاج", "تواليت", "ارضيات", "مفروشات", "جو"}
		var matchedSubs []string
		tokenSet := make(map[string]bool, len(tokens))
		for _, t := range tokens {
			tokenSet[t] = true
		}
		for _, kw := range subKeywords {
			if tokenSet[kw] {
				matchedSubs = append(matchedSubs, kw)
			}
		}
		if len(matchedSubs) > 0 {
			subLine = strings.Join(matchedSubs, "_")
		}
		itemType := pm.ItemType
		if itemType == "" {
			itemType = "عادي"
		}
		return fmt.Sprintf("PMFAM|%s|%s|%s|%s|%s|%d|%.2f",
			brand, pm.ItemCodePrefix, itemType, primaryMeasure, subLine, pm.UnitsPerCarton, pm.CartonPriceExclVAT)
	}
	tokens := normalizeArabicFMCGTokens(rawName)
	return "RAWFAM|" + strings.Join(tokens, "_")
}

// GetProductMasterItems returns the loaded ProductMasterItem slice for a tenant (empty if none loaded).
func (c *Client) GetProductMasterItems(tenantID string) []domain.ProductMasterItem {
	c.mu.RLock()
	defer c.mu.RUnlock()
	normTenant := normalizeTenantKey(tenantID)
	base := c.productMaster[normTenant]
	if base == nil || len(base.Items) == 0 {
		return nil
	}
	cp := make([]domain.ProductMasterItem, len(base.Items))
	copy(cp, base.Items)
	return cp
}

// LookupProductMaster resolves an item from the tenant's Product Master catalog by ItemCode, Barcode, or SKUName.
func (c *Client) LookupProductMaster(tenantID, itemCode, barcode, skuName string) (domain.ProductMasterItem, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.lookupProductMasterLocked(tenantID, itemCode, barcode, skuName)
}

func (c *Client) lookupProductMasterLocked(tenantID, itemCode, barcode, skuName string) (domain.ProductMasterItem, bool) {
	return c.lookupProductMasterFullLocked(tenantID, itemCode, barcode, skuName, "", 0, 0)
}

func (c *Client) lookupProductMasterWithPriceLocked(tenantID, itemCode, barcode, skuName, promoHint string, actualCasePriceExclVAT float64) (domain.ProductMasterItem, bool) {
	return c.lookupProductMasterFullLocked(tenantID, itemCode, barcode, skuName, promoHint, actualCasePriceExclVAT, 0)
}

func (c *Client) lookupProductMasterFullLocked(tenantID, itemCode, barcode, skuName, promoHint string, actualCasePriceExclVAT, actualUnitPriceInclVAT float64) (domain.ProductMasterItem, bool) {
	normTenant := normalizeTenantKey(tenantID)
	byCode := c.productMasterByCode[normTenant]
	byBarcode := c.productMasterByBarcode[normTenant]
	byBarcodeCands := c.productMasterByBarcodeCandidates[normTenant]
	byName := c.productMasterByName[normTenant]
	base := c.productMaster[normTenant]

	if code := domain.NormalizeItemCode(itemCode); code != "" && byCode != nil {
		if it, ok := byCode[code]; ok {
			return it, true
		}
	}
	if bc := domain.CleanBarcode(barcode); bc != "" {
		if byBarcodeCands != nil {
			if cands := byBarcodeCands[bc]; len(cands) > 1 {
				qTokens := normalizeArabicFMCGTokens(skuName)
				qIsPromo := isPromoTokensOrHint(qTokens, promoHint)
				qTokenSet := make(map[string]bool, len(qTokens))
				for _, t := range qTokens {
					qTokenSet[t] = true
				}
				bestCand := cands[0]
				bestCandScore := -1e9
				for _, cand := range cands {
					s := 0.0
					candPromo := cand.ItemType == "عرض" || strings.HasPrefix(cand.ItemCodePrefix, "PR")
					if candPromo == qIsPromo {
						s += 25.0
					} else {
						s -= 20.0
					}
					if actualCasePriceExclVAT > 10 && cand.CartonPriceExclVAT > 10 {
						disc := cand.InvoiceDiscountPct
						if disc > 1.0 {
							disc /= 100.0
						}
						expectedNet := cand.CartonPriceExclVAT * (1.0 - disc)
						relDiff := math.Min(
							math.Abs(actualCasePriceExclVAT-expectedNet)/expectedNet,
							math.Abs(actualCasePriceExclVAT-cand.CartonPriceExclVAT)/cand.CartonPriceExclVAT,
						)
						if relDiff <= 0.05 {
							s += 30.0
						} else if relDiff <= 0.15 {
							s += 15.0
						}
					}
					if actualUnitPriceInclVAT > 1 && cand.UnitPriceInclVAT > 1 {
						relDiffUnit := math.Abs(actualUnitPriceInclVAT-cand.UnitPriceInclVAT) / cand.UnitPriceInclVAT
						if relDiffUnit <= 0.15 {
							s += 25.0
						} else if relDiffUnit <= 0.30 {
							s += 12.0
						} else if relDiffUnit > 0.65 {
							s -= 20.0
						}
					}
					for _, ct := range normalizeArabicFMCGTokens(cand.OfficialName) {
						if qTokenSet[ct] {
							s += 4.0
						}
					}
					if cand.IsPrimaryForBarcode {
						s += 3.0
					}
					if s > bestCandScore {
						bestCandScore = s
						bestCand = cand
					}
				}
				return bestCand, true
			} else if len(cands) == 1 {
				return cands[0], true
			}
		}
		if byBarcode != nil {
			if it, ok := byBarcode[bc]; ok {
				return it, true
			}
		}
	}
	nameKey := normalizeArabicNameForLookup(skuName)
	if nameKey != "" && byName != nil {
		if it, ok := byName[nameKey]; ok {
			return it, true
		}
	}
	if base == nil || len(base.Items) == 0 || nameKey == "" {
		return domain.ProductMasterItem{}, false
	}

	qTokens := normalizeArabicFMCGTokens(skuName)
	if len(qTokens) == 0 {
		return domain.ProductMasterItem{}, false
	}
	qBrand := extractCanonicalBrand("", qTokens)
	qMeasures, qNums := extractNormalizedMeasures(qTokens)
	qIsPromo := isPromoTokensOrHint(qTokens, promoHint)

	qMeasureSet := make(map[string]bool, len(qMeasures))
	for _, m := range qMeasures {
		qMeasureSet[m] = true
	}
	qNumSet := make(map[string]bool, len(qNums))
	for _, n := range qNums {
		qNumSet[n] = true
	}

	stopWords := map[string]bool{
		"منظف": true, "غسيل": true, "عبوه": true, "عبوة": true, "جديد": true,
		"سائل": true, "شركه": true, "ادكو": true, "لتر": true, "جم": true,
		"كجم": true, "مل": true, "عادي": true, "عادى": true, "قطعه": true, "عدد": true,
	}
	qCoreTokens := make([]string, 0, len(qTokens))
	for _, t := range qTokens {
		if !stopWords[t] && !qNumSet[t] && t != qBrand {
			qCoreTokens = append(qCoreTokens, t)
		}
	}

	bestIdx := -1
	bestScore := -1e9

	for i := range base.Items {
		it := &base.Items[i]
		itTokens := normalizeArabicFMCGTokens(it.OfficialName)
		itBrand := extractCanonicalBrand(it.Brand, itTokens)

		score := 0.0
		// 1. Brand alignment
		if qBrand != "" {
			if itBrand == qBrand {
				score += 55.0
			} else if itBrand != "" {
				score -= 120.0
			} else {
				score -= 40.0
			}
		}

		// 2. Weight / Volume alignment (strict measure enforcement)
		itMeasures, itNums := extractNormalizedMeasures(itTokens)
		if len(qMeasures) > 0 || len(qNums) > 0 {
			measureMatched := false
			for _, m := range itMeasures {
				if qMeasureSet[m] {
					measureMatched = true
					break
				}
			}
			numMatched := false
			for _, n := range itNums {
				if qNumSet[n] {
					numMatched = true
					break
				}
			}
			if measureMatched {
				score += 55.0
			} else if numMatched && len(qMeasures) == 0 {
				score += 32.0
			} else if len(qMeasures) > 0 && len(itMeasures) > 0 {
				// Hard penalty for mismatched weight/volume (e.g. 2kg vs 1kg, or 4L vs 125ml)
				score -= 120.0
			} else if len(itMeasures) > 0 || len(itNums) > 0 {
				score -= 55.0
			}
		}

		// 3. Regular vs Promo alignment
		itIsPromo := it.ItemType == "عرض" || strings.HasPrefix(it.ItemCodePrefix, "PR")
		if qIsPromo == itIsPromo {
			score += 22.0
		} else if !qIsPromo && itIsPromo {
			score -= 55.0
		} else {
			score -= 28.0
		}

		// 4. Core product keywords overlap
		itTokenSet := make(map[string]bool, len(itTokens))
		for _, t := range itTokens {
			itTokenSet[t] = true
		}
		matchedCore := 0
		for _, qt := range qCoreTokens {
			if itTokenSet[qt] {
				matchedCore++
				switch qt {
				case "اطباق", "عبايات", "الباشا", "التوفير", "مركز", "اوتوماتيك", "يدوي", "مسحوق", "جل", "منعم", "معطر", "تابلوه", "كاوتش", "فوم", "زجاج", "تواليت", "ارضيات", "صابون", "ايدي", "مفروشات", "جو", "ابيض", "الوان", "اسود", "بكره", "رول", "اسفنجه":
					score += 18.0
				default:
					score += 10.0
				}
			} else {
				// Penalty for key product differentiators present in query but absent in item
				switch qt {
				case "عبايات", "الباشا", "التوفير", "اوتوماتيك", "يدوي", "تابلوه", "كاوتش", "فوم", "زجاج", "تواليت", "ارضيات", "صابون", "ايدي", "بكره", "رول":
					score -= 22.0
				}
			}
		}
		// Penalize if candidate is a specialized product or multi-item bundle not requested in query
		qTokenAllSet := make(map[string]bool, len(qTokens))
		for _, t := range qTokens {
			qTokenAllSet[t] = true
		}
		for _, special := range []string{"عبايات", "الباشا", "التوفير", "بكره", "رول", "اوتوماتيك", "تابلوه", "كاوتش", "فوم", "تواليت", "شرنك", "شنطه", "+"} {
			if itTokenSet[special] && !qTokenAllSet[special] {
				score -= 18.0
			}
		}

		// 5. Price-assisted disambiguation when actual carton price is available
		if actualCasePriceExclVAT > 10 && it.CartonPriceExclVAT > 10 {
			disc := it.InvoiceDiscountPct
			if disc > 1.0 {
				disc = disc / 100.0
			}
			extra := additionalDiscountPct // set to zero by Mohamed
			expectedNetExcl := it.CartonPriceExclVAT * (1.0 - disc) * (1.0 - extra)
			relDiffNet := math.Abs(actualCasePriceExclVAT-expectedNetExcl) / expectedNetExcl
			relDiffList := math.Abs(actualCasePriceExclVAT-it.CartonPriceExclVAT) / it.CartonPriceExclVAT
			minRelDiff := math.Min(relDiffNet, relDiffList)
			if minRelDiff <= 0.03 {
				score += 30.0
			} else if minRelDiff <= 0.10 {
				score += 22.0
			} else if minRelDiff <= 0.22 {
				score += 12.0
			} else if minRelDiff > 0.65 {
				score -= 20.0
			}
		}

		if it.IsPrimaryForBarcode {
			score += 3.0
		}

		if score > bestScore {
			bestScore = score
			bestIdx = i
		}
	}

	// Require a solid minimum confidence score (at least brand + weight or strong token match)
	if bestIdx >= 0 && bestScore >= 40.0 {
		return base.Items[bestIdx], true
	}

	// Fallback substring check ONLY when query has no conflicting weight/volume measures
	if len(qMeasures) == 0 {
		for k, it := range byName {
			if len(nameKey) >= 8 && (strings.Contains(nameKey, k) || strings.Contains(k, nameKey)) {
				return it, true
			}
		}
	}
	return domain.ProductMasterItem{}, false
}

func (c *Client) enrichSellOutFactLocked(r *domain.SellOutFact) {
	if r.RetailerRawSKUName == "" && r.SKUName != "" {
		r.RetailerRawSKUName = r.SKUName
	}
	lookupName := r.RetailerRawSKUName
	if lookupName == "" {
		lookupName = r.SKUName
	}
	normTenant := normalizeTenantKey(r.TenantID)
	lookupCode := r.ItemCode
	if bc := domain.CleanBarcode(r.Barcode); bc != "" {
		if cands := c.productMasterByBarcodeCandidates[normTenant][bc]; len(cands) > 1 {
			lookupCode = ""
		}
	}
	// A real retailer barcode that is not in our price list (e.g. Arma 6223006125803) is a foreign item:
	// never re-label it with an Adeco item found by fuzzy name matching.
	foreign := c.sellOutHasForeignBarcodeLocked(normTenant, r.Barcode) && !c.isProductMasterCodeLocked(normTenant, r.ItemCode)
	if pm, ok := c.lookupProductMasterFullLocked(r.TenantID, lookupCode, r.Barcode, lookupName, "", 0, r.UnitPrice); ok && !foreign {
		r.ItemCode = pm.ItemCode
		if pm.Barcode != "" {
			_, barStillValid := c.productMasterByBarcode[normTenant][strings.TrimSpace(r.Barcode)]
			if r.Barcode == "" || !strings.HasPrefix(r.Barcode, "622") || !barStillValid {
				r.Barcode = pm.Barcode
			}
		}
		if pm.OfficialName != "" {
			r.SKUName = pm.OfficialName
		}
		if pm.UnitsPerCarton > 0 {
			r.UnitsPerCarton = pm.UnitsPerCarton
		}
		r.ItemType = pm.ItemType
		r.FactoryUnitCost = pm.NetUnitInvoiceCost
		r.CartonPriceInclVAT = pm.CartonPriceInclVAT
		r.NetCartonInvoiceCost = pm.NetCartonInvoiceCost
		r.InvoiceDiscountPct = pm.InvoiceDiscountPct
		// A category already on the row (the sheet «المجموعة») stays. Product Master
		// fills only a blank cell, or the unclassified placeholder.
		if r.Category == "" || r.Category == "غير مصنف" {
			r.Category = pm.Category
		}
		if pm.UnitPriceInclVAT > 0 {
			r.RecommendedPrice = math.Round(pm.UnitPriceInclVAT*1000) / 1000
		}
	}
	if r.UnitsPerCarton > 0 && r.QuantitySold > 0 {
		r.CartonsSold = math.Round((float64(r.QuantitySold)/float64(r.UnitsPerCarton))*100) / 100
	}
	if r.FactoryUnitCost > 0 && r.QuantitySold > 0 {
		r.TotalFactoryCost = math.Round(float64(r.QuantitySold)*r.FactoryUnitCost*100) / 100
		r.RetailerGrossProfit = math.Round((r.NetRevenue-r.TotalFactoryCost)*100) / 100
		if r.NetRevenue > 0 {
			r.RetailerMarginPct = math.Round((r.RetailerGrossProfit/r.NetRevenue)*1000) / 10
		}
	}
	if r.RecommendedPrice > 0 && r.UnitPrice > 0 {
		r.PriceDeltaPct = math.Round(((r.UnitPrice-r.RecommendedPrice)/r.RecommendedPrice)*1000) / 10
	}
}

func (c *Client) enrichPricingItemLocked(item *domain.PricingComplianceItem) {
	tenantID := item.TenantID
	if tenantID == "" {
		tenantID = "tenant-adeco"
	}
	if item.RetailerRawSKUName == "" && item.SKUName != "" {
		item.RetailerRawSKUName = item.SKUName
	}
	lookupName := item.RetailerRawSKUName
	if lookupName == "" {
		lookupName = item.SKUName
	}
	normTenant := normalizeTenantKey(tenantID)
	lookupCode := item.ItemCode
	if bc := domain.CleanBarcode(item.Barcode); bc != "" {
		if cands := c.productMasterByBarcodeCandidates[normTenant][bc]; len(cands) > 1 {
			lookupCode = ""
		}
	}
	if pm, ok := c.lookupProductMasterFullLocked(tenantID, lookupCode, item.Barcode, lookupName, "", 0, item.ActualPrice); ok {
		item.ItemCode = pm.ItemCode
		if pm.Barcode != "" {
			_, barStillValid := c.productMasterByBarcode[normTenant][strings.TrimSpace(item.Barcode)]
			if item.Barcode == "" || !strings.HasPrefix(item.Barcode, "622") || !barStillValid {
				item.Barcode = pm.Barcode
			}
		}
		if pm.OfficialName != "" {
			item.SKUName = pm.OfficialName
		}
		item.UnitsPerCarton = pm.UnitsPerCarton
		item.ItemType = pm.ItemType
		item.FactoryUnitCost = pm.NetUnitInvoiceCost
		if pm.UnitPriceInclVAT > 0 {
			item.RecommendedPrice = math.Round(pm.UnitPriceInclVAT*1000) / 1000
			if item.ActualPrice > 0 {
				item.PriceDeltaPct = domain.CalculatePriceDeltaPct(item.ActualPrice, item.RecommendedPrice)
				item.ViolationType = domain.ClassifyPriceViolation(item.PriceDeltaPct)
			}
		}
		if item.ActualPrice > 0 && pm.NetUnitInvoiceCost > 0 {
			item.RetailerMarginPct = math.Round(((item.ActualPrice-pm.NetUnitInvoiceCost)/item.ActualPrice)*1000) / 10
		}
	}
}

func (c *Client) enrichSellInRecordLocked(r *domain.SellInRecord) {
	r.RetailerChain = resolveSellInChainFromCustomer(activeCustomerChainRules(), r.CustomerName, r.RetailerChain)
	actualCasePriceExcl := 0.0
	if math.Abs(r.NetQtyCases) > 0.001 && math.Abs(r.NetValueEGP) > 0.01 {
		actualCasePriceExcl = math.Round(math.Abs(r.NetValueEGP/r.NetQtyCases)*100) / 100
	}
	r.ActualCasePriceExclEGP = actualCasePriceExcl

	chainKey := normChainKey(r.RetailerChain)
	if chainKey == "" {
		chainKey = "fathalla"
	}
	prof, hasProf := c.chainDiscountProfile(normalizeTenantKey(r.TenantID), chainKey)

	pm, ok := c.lookupProductMasterWithPriceLocked(r.TenantID, r.ItemCode, r.Barcode, r.ItemName, r.PromotionType, actualCasePriceExcl)
	if ok {
		r.ItemCode = pm.ItemCode
		if pm.Barcode != "" {
			r.Barcode = pm.Barcode
		}
		if pm.UnitsPerCarton > 0 {
			r.UnitsPerCarton = pm.UnitsPerCarton
		}
		r.DepartmentAr = pm.DepartmentAr
		if r.DepartmentAr == "" {
			r.DepartmentAr = domain.InferDepartmentArFromPrefix(pm.ItemCodePrefix)
		}
		r.OfficialUnitExclVATEGP = pm.UnitPriceExclVAT
		r.OfficialUnitInclVATEGP = pm.UnitPriceInclVAT
		r.OfficialCartonExclVATEGP = pm.CartonPriceExclVAT
		r.OfficialCartonInclVATEGP = pm.CartonPriceInclVAT
		r.NetCartonInvoiceCostEGP = pm.NetCartonInvoiceCost
		r.CanonicalFamilyKey = CanonicalSellInFamilyKey(&pm, r.ItemName)
	} else {
		if r.UnitsPerCarton <= 0 {
			r.UnitsPerCarton = 12
		}
		r.PricingWaveStatus = "unmatched"
		r.CanonicalFamilyKey = CanonicalSellInFamilyKey(nil, r.ItemName)
	}
	// The chain's saved terms (else the flat 10% / 0% / 14% defaults) are the single source of truth
	// for VAT and discounts. An unmatched row without saved terms keeps 0% discounts (UI shows "—"):
	// it has no official price for a discount to apply to.
	terms := sellInChainTerms(prof, hasProf)
	r.VATRate = terms.VATRate
	r.InvoiceDiscountPct, r.ExtraDiscountPct = terms.InvoiceDiscountPct, terms.ExtraDiscountPct
	if !ok && !hasProf {
		r.InvoiceDiscountPct, r.ExtraDiscountPct = 0, 0
	}

	if r.SOPNeedsPackFallback && !r.SOPQtyConverted {
		// Official rule: piece lines with no U of M2 use Product Master pack size only.
		fb := 0.0
		if ok && pm.UnitsPerCarton > 0 {
			fb = float64(pm.UnitsPerCarton)
		}
		if fb >= 1 {
			r.NetQtyCases = math.Round(r.NetQtyCases/fb*10000) / 10000
			r.ExpectedQtyCases = math.Round(r.ExpectedQtyCases/fb*10000) / 10000
			r.UnitsPerCarton = int(math.Round(fb))
			r.SOPQtyConverted = true
			r.SOPUsedPackFallback = true
			r.SOPNeedsPackFallback = false
			if math.Abs(r.NetQtyCases) > 0.0001 && math.Abs(r.NetValueEGP) > 0.01 {
				actualCasePriceExcl = math.Round(math.Abs(r.NetValueEGP/r.NetQtyCases)*100) / 100
				r.ActualCasePriceExclEGP = actualCasePriceExcl
			}
		}
	}
	if r.UnitsPerCarton <= 0 {
		r.UnitsPerCarton = 12
	}
	if !r.SOPQtyConverted && ok && sellInQtyLooksLikePieces(r.NetQtyCases, r.NetValueEGP, r.OfficialUnitExclVATEGP, r.OfficialCartonExclVATEGP, r.UnitsPerCarton) {
		// Only for records that were not already converted from the file UOM (CRT or QTY/U of M2).
		// SOP official cases must not be divided again when the PM pack differs from U of M2.
		r.NetQtyCases = math.Round(r.NetQtyCases/float64(r.UnitsPerCarton)*10000) / 10000
		if math.Abs(r.NetQtyCases) > 0.0001 && math.Abs(r.NetValueEGP) > 0.01 {
			actualCasePriceExcl = math.Round(math.Abs(r.NetValueEGP/r.NetQtyCases)*100) / 100
			r.ActualCasePriceExclEGP = actualCasePriceExcl
		}
	}
	r.TotalUnitsSupplied = int(math.Round(r.NetQtyCases * float64(r.UnitsPerCarton)))
	r.GrossValueInclVATEGP = math.Round(r.NetValueEGP*(1.0+r.VATRate)*100) / 100
	r.VATAmountEGP = math.Round((r.GrossValueInclVATEGP-r.NetValueEGP)*100) / 100

	if r.OfficialCartonExclVATEGP > 0 && math.Abs(r.NetQtyCases) > 0.001 {
		r.OfficialListValueExclEGP = math.Round(r.NetQtyCases*r.OfficialCartonExclVATEGP*100) / 100
		// Negative when the row was invoiced above the list price; the waterfall shows it as an
		// execution difference instead of hiding it.
		r.DiscountGrantedEGP = math.Round((r.OfficialListValueExclEGP-r.NetValueEGP)*100) / 100
		if math.Abs(r.OfficialListValueExclEGP) > 0.01 {
			effDisc := ((r.OfficialListValueExclEGP - r.NetValueEGP) / r.OfficialListValueExclEGP) * 100.0
			if effDisc < -100 {
				effDisc = -100
			} else if effDisc > 100 {
				effDisc = 100
			}
			r.EffectiveDiscountPct = math.Round(effDisc*10) / 10
		}
		if actualCasePriceExcl > 0 {
			r.PriceVariancePct = math.Round(((actualCasePriceExcl-r.OfficialCartonExclVATEGP)/r.OfficialCartonExclVATEGP)*1000) / 10
			if r.MonthNum > 0 && r.MonthNum < 8 && r.PriceVariancePct < -12.0 {
				r.PricingWaveStatus = "historical_pre_aug"
			} else if r.PromotionType == "عرض" || r.PriceVariancePct < -12.0 {
				r.PricingWaveStatus = "promo_discounted"
			} else {
				r.PricingWaveStatus = "current_list"
			}
		} else {
			r.PricingWaveStatus = "current_list"
		}
	} else if ok {
		r.PricingWaveStatus = "current_list"
	}
}

func (c *Client) enrichAllTenantDataLocked(tenantID string) {
	for i := range c.records {
		if matchTenant(c.records[i].TenantID, tenantID) {
			c.enrichSellOutFactLocked(&c.records[i])
		}
	}
	for i := range c.pricingItems {
		t := c.pricingItems[i].TenantID
		if t == "" {
			t = "tenant-adeco"
		}
		if matchTenant(t, tenantID) {
			c.enrichPricingItemLocked(&c.pricingItems[i])
		}
	}
	normTenant := normalizeTenantKey(tenantID)
	if recs, ok := c.sellInRecords[normTenant]; ok {
		for i := range recs {
			c.enrichSellInRecordLocked(&recs[i])
		}
		c.sellInRecords[normTenant] = recs
	}
}

type skuChainPullAgg struct {
	units  int
	rev    float64
	chains map[string]bool
}

// resolvePullStatsCodeLocked maps a sell-out/sell-in row to a Product Master item code using
// only O(1) indexes (item code + barcode). It never runs the fuzzy Arabic name scan: that path
// is O(SKU×tokens) per row and made GET /product-master hang past the web client's timeout when
// tens of thousands of POS rows lacked an item code.
func (c *Client) resolvePullStatsCodeLocked(normTenant, itemCode, barcode string) string {
	if code := domain.NormalizeItemCode(itemCode); code != "" {
		return code
	}
	bc := domain.CleanBarcode(barcode)
	if bc == "" {
		return ""
	}
	if cands := c.productMasterByBarcodeCandidates[normTenant][bc]; len(cands) > 0 {
		best := cands[0]
		for _, cand := range cands[1:] {
			if cand.IsPrimaryForBarcode && !best.IsPrimaryForBarcode {
				best = cand
			}
		}
		return domain.NormalizeItemCode(best.ItemCode)
	}
	if by := c.productMasterByBarcode[normTenant]; by != nil {
		if it, ok := by[bc]; ok {
			return domain.NormalizeItemCode(it.ItemCode)
		}
	}
	return ""
}

func (c *Client) computeSKUChainPullStatsLocked(normTenant string) map[string]*skuChainPullAgg {
	statsByCode := make(map[string]*skuChainPullAgg)
	ensureAgg := func(code string) *skuChainPullAgg {
		agg, ok := statsByCode[code]
		if !ok {
			agg = &skuChainPullAgg{chains: make(map[string]bool)}
			statsByCode[code] = agg
		}
		return agg
	}

	for _, r := range c.records {
		if !matchTenant(r.TenantID, normTenant) || !isOwnRecord(r) {
			continue
		}
		code := c.resolvePullStatsCodeLocked(normTenant, r.ItemCode, r.Barcode)
		if code == "" {
			continue
		}
		agg := ensureAgg(code)
		agg.units += r.QuantitySold
		agg.rev += r.NetRevenue
		if ch := strings.ToLower(strings.TrimSpace(r.RetailerChain)); ch != "" {
			agg.chains[ch] = true
		}
	}

	for _, sr := range c.sellInRecords[normTenant] {
		if sr.NetQtyCases <= 0 && sr.NetValueEGP <= 0 {
			continue
		}
		code := c.resolvePullStatsCodeLocked(normTenant, sr.ItemCode, sr.Barcode)
		if code == "" {
			continue
		}
		agg := ensureAgg(code)
		if ch := strings.ToLower(strings.TrimSpace(sr.RetailerChain)); ch != "" {
			agg.chains[ch] = true
		}
	}

	return statsByCode
}

// GetProductMaster returns the filtered Product Master & Price List catalog and summary KPIs for a tenant.
func (c *Client) GetProductMaster(ctx context.Context, tenantID string, filter ProductMasterFilter) (*domain.ProductMasterSummaryResponse, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normTenant := normalizeTenantKey(tenantID)
	base := c.productMaster[normTenant]
	if base == nil {
		return &domain.ProductMasterSummaryResponse{
			TenantID:           normTenant,
			CompanyName:        "شركة الاسكندرية للكيماويات و المنظفات ( ادكو )",
			SheetDateLabel:     "تحديث 01-08-2026",
			DefaultDiscountPct: 0.10,
			DefaultVATRate:     0.14,
			AvailablePrefixes:  []string{},
			AvailableBrands:    []string{},
			AvailablePackaging: []string{},
			Items:              []domain.ProductMasterItem{},
		}, nil
	}

	prefixFilter := strings.ToUpper(strings.TrimSpace(filter.Prefix))
	if prefixFilter == "ALL" || prefixFilter == "الكل" {
		prefixFilter = ""
	}
	brandFilter := strings.TrimSpace(filter.Brand)
	if brandFilter == "all" || brandFilter == "الكل" {
		brandFilter = ""
	}
	typeFilter := strings.TrimSpace(filter.ItemType)
	if typeFilter == "all" || typeFilter == "الكل" {
		typeFilter = ""
	}
	packFilter := strings.TrimSpace(filter.PackagingType)
	if packFilter == "all" || packFilter == "الكل" {
		packFilter = ""
	}
	pullFilter := strings.ToLower(strings.TrimSpace(filter.PullStatus))
	if pullFilter == "all" || pullFilter == "الكل" {
		pullFilter = ""
	}
	priceChangeFilter := strings.ToLower(strings.TrimSpace(filter.PriceChange))
	if priceChangeFilter == "all" || priceChangeFilter == "الكل" {
		priceChangeFilter = ""
	}
	searchQ := strings.TrimSpace(filter.SearchQuery)

	statsByCode := c.computeSKUChainPullStatsLocked(normTenant)
	activeCount := 0
	unpulledCount := 0

	filtered := make([]domain.ProductMasterItem, 0, len(base.Items))
	for _, it := range base.Items {
		if it.ERPPrefix == "" {
			it.ERPPrefix = it.ItemCodePrefix
		}
		if it.DepartmentAr == "" {
			it.DepartmentAr = domain.InferDepartmentArFromPrefix(it.ItemCodePrefix)
		}
		if it.PriceChangeDirection == "" {
			it.PriceChangeDirection = "same"
		}
		code := domain.NormalizeItemCode(it.ItemCode)
		if agg, ok := statsByCode[code]; ok && (agg.units > 0 || len(agg.chains) > 0) {
			it.IsActiveInChains = true
			it.TotalPOSUnitsSold = agg.units
			upc := it.UnitsPerCarton
			if upc <= 0 {
				upc = 12
			}
			it.TotalPOSCartonsSold = math.Round((float64(agg.units)/float64(upc))*100) / 100
			it.TotalPOSRevenue = math.Round(agg.rev*100) / 100
			if agg.units > 0 {
				it.AvgRetailSellingPrice = math.Round((agg.rev/float64(agg.units))*100) / 100
			}
			chains := make([]string, 0, len(agg.chains))
			for ch := range agg.chains {
				chains = append(chains, ch)
			}
			sort.Strings(chains)
			it.ActiveChains = chains
			activeCount++
		} else {
			it.IsActiveInChains = false
			unpulledCount++
		}

		if prefixFilter != "" {
			if prefixFilter == "PR" {
				if !strings.HasPrefix(it.ItemCodePrefix, "PR") {
					continue
				}
			} else if !strings.EqualFold(it.ItemCodePrefix, prefixFilter) {
				continue
			}
		}
		if brandFilter != "" && !strings.EqualFold(it.Brand, brandFilter) && !strings.Contains(strings.ToLower(it.Brand), strings.ToLower(brandFilter)) {
			continue
		}
		if typeFilter != "" && it.ItemType != typeFilter {
			continue
		}
		if packFilter != "" && it.PackagingType != packFilter {
			continue
		}
		if pullFilter != "" {
			if (pullFilter == "active" || pullFilter == "pulled") && !it.IsActiveInChains {
				continue
			}
			if (pullFilter == "unpulled" || pullFilter == "inactive" || pullFilter == "gap") && it.IsActiveInChains {
				continue
			}
		}
		if priceChangeFilter != "" {
			dir := strings.ToLower(strings.TrimSpace(it.PriceChangeDirection))
			switch priceChangeFilter {
			case "changed", "diff", "any_change":
				if dir != "up" && dir != "down" && dir != "new" {
					continue
				}
			case "up", "increased", "increase":
				if dir != "up" {
					continue
				}
			case "down", "decreased", "decrease":
				if dir != "down" {
					continue
				}
			case "new", "added":
				if dir != "new" {
					continue
				}
			case "same", "unchanged":
				if dir != "" && dir != "same" {
					continue
				}
			}
		}
		if searchQ != "" {
			if !domain.MatchesProductSearchQuery(searchQ, it.ItemCode, it.Barcode, it.OfficialName, it.DepartmentAr, it.Category, it.Brand) {
				continue
			}
		}
		filtered = append(filtered, it)
	}

	if searchQ != "" && len(filtered) == 0 {
		if pm, ok := c.lookupProductMasterLocked(normTenant, searchQ, searchQ, searchQ); ok {
			code := domain.NormalizeItemCode(pm.ItemCode)
			if agg, okAgg := statsByCode[code]; okAgg && (agg.units > 0 || len(agg.chains) > 0) {
				pm.IsActiveInChains = true
				pm.TotalPOSUnitsSold = agg.units
				upc := pm.UnitsPerCarton
				if upc <= 0 {
					upc = 12
				}
				pm.TotalPOSCartonsSold = math.Round((float64(agg.units)/float64(upc))*100) / 100
				pm.TotalPOSRevenue = math.Round(agg.rev*100) / 100
				if agg.units > 0 {
					pm.AvgRetailSellingPrice = math.Round((agg.rev/float64(agg.units))*100) / 100
				}
				chains := make([]string, 0, len(agg.chains))
				for ch := range agg.chains {
					chains = append(chains, ch)
				}
				sort.Strings(chains)
				pm.ActiveChains = chains
			}
			filtered = append(filtered, pm)
		}
	}

	// Sort by SerialNo ascending
	sort.Slice(filtered, func(i, j int) bool {
		if filtered[i].SerialNo != filtered[j].SerialNo {
			return filtered[i].SerialNo < filtered[j].SerialNo
		}
		return filtered[i].ItemCode < filtered[j].ItemCode
	})

	return &domain.ProductMasterSummaryResponse{
		TenantID:            base.TenantID,
		CompanyName:         base.CompanyName,
		SheetDateLabel:      base.SheetDateLabel,
		SourceFilename:      base.SourceFilename,
		DefaultDiscountPct:  base.DefaultDiscountPct,
		DefaultVATRate:      base.DefaultVATRate,
		TotalSKUs:           base.TotalSKUs,
		RegularSKUsCount:    base.RegularSKUsCount,
		PromoSKUsCount:      base.PromoSKUsCount,
		UniqueBarcodesCount: base.UniqueBarcodesCount,
		AvgUnitsPerCarton:   base.AvgUnitsPerCarton,
		ActiveInChainsCount: activeCount,
		UnpulledSKUsCount:   unpulledCount,
		PriceIncreasedCount: base.PriceIncreasedCount,
		PriceDecreasedCount: base.PriceDecreasedCount,
		PriceUnchangedCount: base.PriceUnchangedCount,
		NewSKUsCount:        base.NewSKUsCount,
		AvailablePrefixes:   base.AvailablePrefixes,
		AvailableBrands:     base.AvailableBrands,
		AvailablePackaging:  base.AvailablePackaging,
		DiffSummary:         base.DiffSummary,
		Items:               filtered,
	}, nil
}

// SetProductMaster replaces or merges the Product Master catalog for a tenant, computes price diffs against the previous version, persists it to disk, and retroactively enriches all tenant data.
func (c *Client) SetProductMaster(ctx context.Context, tenantID string, summary *domain.ProductMasterSummaryResponse) (*domain.ProductMasterSummaryResponse, error) {
	if summary == nil || len(summary.Items) == 0 {
		return nil, fmt.Errorf("empty product master summary")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidateKPICache()

	normTenant := normalizeTenantKey(tenantID)
	prev := c.productMaster[normTenant]
	if prev != nil && len(prev.Items) > 0 && summary.DiffSummary == nil {
		ComputeProductMasterDiff(prev, summary)
	}
	c.indexProductMasterLocked(normTenant, summary)
	c.persistTenantProductMasterLocked(normTenant)
	c.enrichAllTenantDataLocked(normTenant)

	return c.productMaster[normTenant], nil
}

// ClearProductMaster removes the Product Master catalog for a tenant (used when all Product Master sheets are deleted).
func (c *Client) ClearProductMaster(ctx context.Context, tenantID string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidateKPICache()

	normTenant := normalizeTenantKey(tenantID)
	delete(c.productMaster, normTenant)
	delete(c.productMasterByCode, normTenant)
	delete(c.productMasterByBarcode, normTenant)
	delete(c.productMasterByBarcodeCandidates, normTenant)
	delete(c.productMasterByName, normTenant)

	if flag.Lookup("test.v") == nil || os.Getenv("TASHIL_PRODUCT_MASTER_DIR") != "" {
		dir := getProductMasterStorageDir()
		_ = os.Remove(filepath.Join(dir, normTenant+".json"))
	}
	return nil
}

// RestoreBaselineProductMaster restores the clean startup baseline Product Master catalog for a tenant if one exists and was not itself the deleted file.
func (c *Client) RestoreBaselineProductMaster(ctx context.Context, tenantID, deletedFilename string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidateKPICache()

	normTenant := normalizeTenantKey(tenantID)
	base := c.baselineProductMaster[normTenant]
	if base == nil || len(base.Items) == 0 {
		return false
	}
	if deletedFilename != "" && (strings.EqualFold(deletedFilename, base.SourceFilename) || strings.EqualFold(deletedFilename, "pm_default_seed")) {
		delete(c.baselineProductMaster, normTenant)
		return false
	}
	restored := cloneCleanBaselineSummary(base)
	c.indexProductMasterLocked(normTenant, restored)
	c.persistTenantProductMasterLocked(normTenant)
	c.enrichAllTenantDataLocked(normTenant)
	return true
}

// UpsertProductMasterItem updates or inserts a single ProductMasterItem in the tenant's catalog, recalculating derived VAT/discount prices and tracking price changes.
func (c *Client) UpsertProductMasterItem(ctx context.Context, tenantID string, item domain.ProductMasterItem) (*domain.ProductMasterItem, error) {
	code := domain.NormalizeItemCode(item.ItemCode)
	if code == "" {
		return nil, fmt.Errorf("item_code is required")
	}

	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidateKPICache()

	normTenant := normalizeTenantKey(tenantID)
	base := c.productMaster[normTenant]
	if base == nil {
		base = &domain.ProductMasterSummaryResponse{
			TenantID:           normTenant,
			CompanyName:        "شركة الاسكندرية للكيماويات و المنظفات ( ادكو )",
			SheetDateLabel:     time.Now().Format("2006-01-02"),
			DefaultDiscountPct: 0.10,
			DefaultVATRate:     0.14,
			Items:              []domain.ProductMasterItem{},
		}
	}

	item.ItemCode = code
	item.ItemCodePrefix = domain.ExtractItemCodePrefix(code)
	item.ERPPrefix = item.ItemCodePrefix
	if item.DepartmentAr == "" {
		item.DepartmentAr = domain.InferDepartmentArFromPrefix(item.ItemCodePrefix)
	}
	item.Barcode = domain.CleanBarcode(item.Barcode)
	if item.UnitsPerCarton <= 0 {
		item.UnitsPerCarton = 12
	}
	if item.VATRate <= 0 {
		item.VATRate = 0.14
	} else if item.VATRate > 1.0 && item.VATRate <= 100.0 {
		item.VATRate = item.VATRate / 100.0
	}
	if item.InvoiceDiscountPct > 1.0 && item.InvoiceDiscountPct <= 100.0 {
		item.InvoiceDiscountPct = item.InvoiceDiscountPct / 100.0
	}
	if item.ExtraDiscountPct > 1.0 && item.ExtraDiscountPct <= 100.0 {
		item.ExtraDiscountPct = item.ExtraDiscountPct / 100.0
	}

	if item.UnitPriceExclVAT > 0 {
		item.UnitPriceInclVAT = math.Round(item.UnitPriceExclVAT*(1.0+item.VATRate)*1000) / 1000
	} else if item.UnitPriceInclVAT > 0 {
		item.UnitPriceExclVAT = math.Round((item.UnitPriceInclVAT/(1.0+item.VATRate))*1000) / 1000
	}
	item.CartonPriceExclVAT = math.Round(item.UnitPriceExclVAT*float64(item.UnitsPerCarton)*100) / 100
	item.CartonPriceInclVAT = math.Round(item.UnitPriceInclVAT*float64(item.UnitsPerCarton)*100) / 100
	item.NetUnitInvoiceCost = math.Round(item.UnitPriceInclVAT*(1.0-item.InvoiceDiscountPct)*(1.0-additionalDiscountPct)*1000) / 1000
	item.NetCartonInvoiceCost = math.Round(item.NetUnitInvoiceCost*float64(item.UnitsPerCarton)*100) / 100
	if item.Category == "" {
		item.Category = domain.InferCategoryFromItemCodeAndName(item.ItemCodePrefix, item.OfficialName)
	}
	if item.Brand == "" {
		item.Brand = domain.InferBrandFromItemName(item.OfficialName, item.Category)
	}
	if item.ItemType == "" {
		item.ItemType = "عادي"
	}
	if item.PackagingType == "" {
		item.PackagingType = "عبوة"
	}
	item.UpdatedAt = time.Now().Format("2006-01-02")

	found := false
	for i := range base.Items {
		if strings.EqualFold(base.Items[i].ItemCode, code) {
			old := base.Items[i]
			if item.SerialNo <= 0 {
				item.SerialNo = old.SerialNo
			}
			diffEGP := math.Round((item.UnitPriceInclVAT-old.UnitPriceInclVAT)*100) / 100
			if math.Abs(diffEGP) >= 0.01 && old.UnitPriceInclVAT > 0 {
				item.PrevUnitPriceExclVAT = old.UnitPriceExclVAT
				item.PrevUnitPriceInclVAT = old.UnitPriceInclVAT
				item.PrevCartonPriceInclVAT = old.CartonPriceInclVAT
				item.PrevNetUnitInvoiceCost = old.NetUnitInvoiceCost
				item.PrevNetCartonInvoiceCost = old.NetCartonInvoiceCost
				item.PriceChangeDiffEGP = diffEGP
				item.PriceChangePct = math.Round(((item.UnitPriceInclVAT-old.UnitPriceInclVAT)/old.UnitPriceInclVAT)*1000) / 10
				if diffEGP > 0 {
					item.PriceChangeDirection = "up"
				} else {
					item.PriceChangeDirection = "down"
				}
			} else if item.PriceChangeDirection == "" {
				item.PrevUnitPriceExclVAT = old.PrevUnitPriceExclVAT
				item.PrevUnitPriceInclVAT = old.PrevUnitPriceInclVAT
				item.PrevCartonPriceInclVAT = old.PrevCartonPriceInclVAT
				item.PrevNetUnitInvoiceCost = old.PrevNetUnitInvoiceCost
				item.PrevNetCartonInvoiceCost = old.PrevNetCartonInvoiceCost
				item.PriceChangeDirection = old.PriceChangeDirection
				item.PriceChangeDiffEGP = old.PriceChangeDiffEGP
				item.PriceChangePct = old.PriceChangePct
			}
			base.Items[i] = item
			found = true
			break
		}
	}
	if !found {
		for i := range base.SupplementalPOSItems {
			if strings.EqualFold(base.SupplementalPOSItems[i].ItemCode, code) || (item.Barcode != "" && base.SupplementalPOSItems[i].Barcode == item.Barcode) {
				old := base.SupplementalPOSItems[i]
				if item.SerialNo <= 0 {
					item.SerialNo = old.SerialNo
				}
				base.SupplementalPOSItems[i] = item
				found = true
				break
			}
		}
	}
	if !found {
		if item.SerialNo <= 0 {
			item.SerialNo = len(base.Items) + 1
		}
		if item.PriceChangeDirection == "" {
			item.PriceChangeDirection = "new"
		}
		base.Items = append(base.Items, item)
	}

	c.indexProductMasterLocked(normTenant, base)
	c.persistTenantProductMasterLocked(normTenant)
	c.enrichAllTenantDataLocked(normTenant)

	updated, ok := c.productMasterByCode[normTenant][code]
	if !ok && item.Barcode != "" {
		updated = c.productMasterByBarcode[normTenant][item.Barcode]
	}
	return &updated, nil
}

// sellInQtyLooksLikePieces reports whether a Sell-In quantity is really in pieces: the net value per
// "case" is much closer to the official unit price than to the carton price.
func sellInQtyLooksLikePieces(qty, net, unitPrice, cartonPrice float64, upc int) bool {
	if upc <= 1 || unitPrice <= 0 || cartonPrice <= 0 || math.Abs(qty) < 0.001 || math.Abs(net) < 0.01 {
		return false
	}
	per := math.Abs(net / qty)
	dUnit := math.Abs(math.Log(per / unitPrice))
	dCarton := math.Abs(math.Log(per / cartonPrice))
	return dUnit < dCarton
}

// sellOutHasForeignBarcodeLocked is true when the row carries a full retail barcode (8+ digits) that is
// not in the tenant's product master, i.e. the item is not ours.
func (c *Client) sellOutHasForeignBarcodeLocked(normTenant, barcode string) bool {
	bc := domain.CleanBarcode(barcode)
	if len(bc) < 8 {
		return false
	}
	for _, ch := range bc {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	if len(c.productMasterByBarcode[normTenant]) == 0 {
		return false
	}
	if _, ok := c.productMasterByBarcode[normTenant][bc]; ok {
		return false
	}
	if _, ok := c.productMasterByBarcode[normTenant][strings.TrimSpace(barcode)]; ok {
		return false
	}
	if len(c.productMasterByBarcodeCandidates[normTenant][bc]) > 0 {
		return false
	}
	return true
}

// isProductMasterCodeLocked reports whether code is one of the tenant's own item codes (a row already
// tied to an Adeco item keeps re-enriching even if its barcode changed in the price list).
func (c *Client) isProductMasterCodeLocked(normTenant, code string) bool {
	code = strings.TrimSpace(code)
	if code == "" {
		return false
	}
	_, ok := c.productMasterByCode[normTenant][code]
	if !ok {
		_, ok = c.productMasterByCode[normTenant][strings.ToUpper(code)]
	}
	return ok
}

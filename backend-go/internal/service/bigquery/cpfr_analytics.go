package bigquery

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// SetSellInRecords stores parsed Supplier Sell-In & Forecasting Plan rows for a tenant,
// merging cumulatively by (RetailerChain, Year, MonthNum) and SourceFilename so uploading a Sell-In file
// month-by-month (e.g. Jan, then Feb, then Mar) preserves all previously uploaded months and chains.
func (c *Client) SetSellInRecords(ctx context.Context, tenantID, filename string, records []domain.SellInRecord) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.sellInRecords == nil {
		c.sellInRecords = make(map[string][]domain.SellInRecord)
	}
	if c.sellInFilename == nil {
		c.sellInFilename = make(map[string]string)
	}

	normTenant := normalizeTenantKey(tenantID)
	normFile := strings.TrimSpace(filename)
	type chainYearMonth struct {
		chain string
		year  int
		month int
	}
	incomingPeriods := make(map[chainYearMonth]bool)
	incomingChains := make(map[string]bool)
	for i := range records {
		if records[i].TenantID == "" {
			records[i].TenantID = normTenant
		}
		c.enrichSellInRecordLocked(&records[i])
		ch := strings.ToLower(strings.TrimSpace(records[i].RetailerChain))
		if ch == "" {
			ch = "fathalla"
			records[i].RetailerChain = ch
		}
		if strings.TrimSpace(records[i].SourceFilename) == "" {
			records[i].SourceFilename = normFile
		}
		yr := records[i].Year
		if yr <= 0 {
			yr = 2026
			records[i].Year = yr
		}
		mn := records[i].MonthNum
		if mn <= 0 {
			mn = 1
			records[i].MonthNum = mn
		}
		incomingChains[ch] = true
		incomingPeriods[chainYearMonth{chain: ch, year: yr, month: mn}] = true
	}

	existing := c.sellInRecords[normTenant]
	merged := make([]domain.SellInRecord, 0, len(existing)+len(records))
	for _, oldRec := range existing {
		oldChain := strings.ToLower(strings.TrimSpace(oldRec.RetailerChain))
		if oldChain == "" {
			oldChain = "fathalla"
		}
		oldYr := oldRec.Year
		if oldYr <= 0 {
			oldYr = 2026
		}
		oldMn := oldRec.MonthNum
		if oldMn <= 0 {
			oldMn = 1
		}
		// Replace if same filename+chain was re-uploaded, OR if same (chain, year, month) is being updated
		if normFile != "" && strings.EqualFold(strings.TrimSpace(oldRec.SourceFilename), normFile) && incomingChains[oldChain] {
			continue
		}
		if incomingPeriods[chainYearMonth{chain: oldChain, year: oldYr, month: oldMn}] {
			continue
		}
		merged = append(merged, oldRec)
	}
	merged = append(merged, records...)

	c.sellInRecords[normTenant] = merged
	c.sellInFilename[normTenant] = filename
	return nil
}

func normalizeTenantKey(tenantID string) string {
	t := strings.ToLower(strings.TrimSpace(tenantID))
	switch t {
	case "", "adeco", "adco", "tenant-adeco", "tenant-adco":
		return "tenant-adeco"
	case "unilever", "tenant-unilever":
		return "tenant-unilever"
	case "pepsi", "pepsico", "tenant-pepsi":
		return "tenant-pepsi"
	default:
		if !strings.HasPrefix(t, "tenant-") {
			return "tenant-" + t
		}
		return t
	}
}

func inferRegionFromBranch(branch, chain string) (string, string) {
	b := strings.ToLower(branch)
	switch {
	case strings.Contains(b, "القاهرة") || strings.Contains(b, "نصر") || strings.Contains(b, "معادي") || strings.Contains(b, "تجمع") || strings.Contains(b, "عبور") || strings.Contains(b, "رحاب") || strings.Contains(b, "شروق") || strings.Contains(b, "مدينتي") || strings.Contains(b, "المقطم") || strings.Contains(b, "شبرا") || strings.Contains(b, "مصر الجديدة") || strings.Contains(b, "حلوان") || strings.Contains(b, "المرج") || strings.Contains(b, "عين شمس") || strings.Contains(b, "زهراء"):
		return "CIR", "القاهرة الكبرى"
	case strings.Contains(b, "جيزة") || strings.Contains(b, "أكتوبر") || strings.Contains(b, "اكتوبر") || strings.Contains(b, "زايد") || strings.Contains(b, "هرم") || strings.Contains(b, "فيصل") || strings.Contains(b, "دقي") || strings.Contains(b, "مهندسين") || strings.Contains(b, "امبابة") || strings.Contains(b, "حدائق"):
		return "CIR", "القاهرة الكبرى"
	case strings.Contains(b, "طنطا") || strings.Contains(b, "غربية") || strings.Contains(b, "محلة") || strings.Contains(b, "زفتى") || strings.Contains(b, "كفر الزيات"):
		return "TNT", "الغربية (طنطا)"
	case strings.Contains(b, "دمنهور") || strings.Contains(b, "بحيرة") || strings.Contains(b, "كفر الدوار") || strings.Contains(b, "رشيد") || strings.Contains(b, "ادكو") || strings.Contains(b, "إدكو"):
		return "BHR", "البحيرة"
	case strings.Contains(b, "منصورة") || strings.Contains(b, "دقهلية") || strings.Contains(b, "ميت غمر") || strings.Contains(b, "طلخا") || strings.Contains(b, "دمياط") || strings.Contains(b, "بورسعيد") || strings.Contains(b, "شرقية") || strings.Contains(b, "زقازيق") || strings.Contains(b, "عاشر"):
		return "MNS", "المنصورة والدلتا"
	default:
		if strings.EqualFold(chain, "gomla") {
			return "CIR", "القاهرة الكبرى"
		}
		return "ALX", "الإسكندرية والساحل"
	}
}

func inferBrandAndSectorFromSKU(skuName, category string) (string, string) {
	b := domain.InferBrandFromItemName(skuName, category)
	sec := "MT"
	if strings.Contains(b, "Rapido") || strings.Contains(b, "رابيدو") {
		sec = "CC"
	}
	return b, sec
}

// GetCPFRDashboard computes Sell-In vs. Sell-Out reconciliation, estimated on-hand inventory,
// smart replenishment PO quantities, W1+W2 -> EXP run-rate forecasting, promotions/returns,
// and sales rep scorecards across all or any selected retail chain.
func (c *Client) GetCPFRDashboard(ctx context.Context, tenantID string, filter CPFRFilter) (*domain.CPFRDashboardPayload, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normTenant := normalizeTenantKey(tenantID)
	explicitSellIn := c.sellInRecords[normTenant]
	filename := c.sellInFilename[normTenant]
	if filename == "" {
		filename = "CPFR_MultiChain_Sell_In_Reconciliation.xlsx"
	}

	leadTime := filter.LeadTimeDays
	if leadTime <= 0 {
		leadTime = 4
	}
	safetyDays := filter.SafetyStockDays
	if safetyDays <= 0 {
		safetyDays = 7
	}

	chainFilter := strings.ToLower(strings.TrimSpace(filter.RetailerChain))
	if chainFilter == "all" || chainFilter == "الكل" {
		chainFilter = ""
	}
	sectorFilter := strings.ToUpper(strings.TrimSpace(filter.Sector))
	if sectorFilter == "ALL" || sectorFilter == "الكل" {
		sectorFilter = ""
	}
	regionFilter := strings.ToUpper(strings.TrimSpace(filter.RegionCode))
	if regionFilter == "ALL" || regionFilter == "الكل" {
		regionFilter = ""
	}
	brandFilter := strings.TrimSpace(filter.Brand)
	if brandFilter == "all" || brandFilter == "الكل" {
		brandFilter = ""
	}
	repFilter := strings.TrimSpace(filter.SalesRep)
	if repFilter == "all" || repFilter == "الكل" {
		repFilter = ""
	}
	statusFilter := strings.ToLower(strings.TrimSpace(filter.StockStatus))
	if statusFilter == "all" || statusFilter == "الكل" {
		statusFilter = ""
	}
	searchQ := strings.TrimSpace(filter.SearchQuery)

	// Track which chains already have explicit Sell-In records uploaded
	chainsWithExplicitSellIn := make(map[string]bool)
	for _, sr := range explicitSellIn {
		ch := strings.ToLower(strings.TrimSpace(sr.RetailerChain))
		if ch == "" {
			ch = "fathalla"
		}
		chainsWithExplicitSellIn[ch] = true
	}

	// 1. Aggregate actual Cashier Sell-Out by (Year, Month) & Chain from c.records,
	// and synthesize baseline Sell-In records only for demo chains that have no explicit Sell-In sheet.
	type ymKey struct {
		year  int
		month int
	}
	sellOutByYMRev := make(map[ymKey]float64)
	sellOutByYMUnits := make(map[ymKey]int)
	sellOutByYMCases := make(map[ymKey]float64)
	sellOutByMonthRev := make(map[int]float64)
	sellOutByMonthUnits := make(map[int]int)
	sellOutByChainMonthRev := make(map[string]map[int]float64)
	sellOutByChainRev := make(map[string]float64)
	totalMatchedSellOutRev := 0.0
	totalMatchedSellOutUnits := 0
	hasRealUploadedSellOut := false

	type derivedKey struct {
		chain string
		year  int
		month int
		store string
		sku   string
		cat   string
	}
	type derivedVal struct {
		rev   float64
		units int
	}
	derivedSellInAgg := make(map[derivedKey]*derivedVal)

	for _, r := range c.records {
		if !matchTenant(r.TenantID, normTenant) {
			continue
		}
		if !isOwnRecord(r) {
			continue
		}
		if !strings.HasPrefix(r.IngestionBatchID, "batch_seed_") {
			hasRealUploadedSellOut = true
		}
		recChain := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if recChain == "" {
			recChain = "fathalla"
		}
		yr, m := extractYearAndMonthFromDate(r.TransactionDate)
		if m <= 0 {
			m = 1
		}
		if filter.Year > 0 && yr != filter.Year {
			continue
		}

		// Apply optional sector, region, brand, or search filter to Sell-Out records as well
		bName, sCode := inferBrandAndSectorFromSKU(r.SKUName, r.Category)
		if sectorFilter != "" && !strings.EqualFold(sCode, sectorFilter) {
			continue
		}
		if brandFilter != "" && !strings.EqualFold(bName, brandFilter) && !strings.Contains(strings.ToLower(bName), strings.ToLower(brandFilter)) {
			continue
		}
		if regionFilter != "" {
			rCode, _ := inferRegionFromBranch(r.StoreName, recChain)
			if !strings.EqualFold(rCode, regionFilter) {
				continue
			}
		}
		if searchQ != "" {
			if !domain.MatchesProductSearchQuery(searchQ, r.ItemCode, r.Barcode, r.SKUName, r.RetailerRawSKUName, r.Category, bName) {
				continue
			}
		}

		if sellOutByChainMonthRev[recChain] == nil {
			sellOutByChainMonthRev[recChain] = make(map[int]float64)
		}
		sellOutByChainMonthRev[recChain][m] += r.NetRevenue
		sellOutByChainRev[recChain] += r.NetRevenue

		if matchChainFilter(recChain, chainFilter) {
			ym := ymKey{year: yr, month: m}
			sellOutByYMRev[ym] += r.NetRevenue
			sellOutByYMUnits[ym] += r.QuantitySold
			upc := r.UnitsPerCarton
			if upc <= 0 {
				if pm, ok := c.lookupProductMasterLocked(normTenant, r.ItemCode, r.Barcode, r.SKUName); ok && pm.UnitsPerCarton > 0 {
					upc = pm.UnitsPerCarton
				} else {
					upc = 12
				}
			}
			sellOutByYMCases[ym] += float64(r.QuantitySold) / float64(upc)
			sellOutByMonthRev[m] += r.NetRevenue
			sellOutByMonthUnits[m] += r.QuantitySold
			totalMatchedSellOutRev += r.NetRevenue
			totalMatchedSellOutUnits += r.QuantitySold
		}

		// Only derive synthetic Sell-In for demo tenants when no real Sell-Out/Sell-In sheets exist
		if normTenant != "tenant-adeco" && !chainsWithExplicitSellIn[recChain] && r.NetRevenue > 0 {
			dk := derivedKey{
				chain: recChain,
				year:  yr,
				month: m,
				store: r.StoreName,
				sku:   r.SKUName,
				cat:   r.Category,
			}
			dv, exists := derivedSellInAgg[dk]
			if !exists {
				dv = &derivedVal{}
				derivedSellInAgg[dk] = dv
			}
			dv.rev += r.NetRevenue
			dv.units += r.QuantitySold
		}
	}

	// Combine explicit Sell-In records with derived Sell-In records (if any)
	combinedSellIn := make([]domain.SellInRecord, 0, len(explicitSellIn)+len(derivedSellInAgg))
	for _, sr := range explicitSellIn {
		ch := strings.ToLower(strings.TrimSpace(sr.RetailerChain))
		if ch == "" {
			ch = "fathalla"
		}
		sr.RetailerChain = ch
		if sr.Year <= 0 {
			sr.Year = 2026
		}
		if filter.Year > 0 && sr.Year != filter.Year {
			continue
		}
		if matchChainFilter(ch, chainFilter) {
			combinedSellIn = append(combinedSellIn, sr)
		}
	}

	monthNamesEN := []string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
	monthNamesAR := []string{"يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"}

	// Sort derived keys for deterministic output
	derivedKeys := make([]derivedKey, 0, len(derivedSellInAgg))
	for k := range derivedSellInAgg {
		if matchChainFilter(k.chain, chainFilter) {
			derivedKeys = append(derivedKeys, k)
		}
	}
	sort.Slice(derivedKeys, func(i, j int) bool {
		if derivedKeys[i].chain != derivedKeys[j].chain {
			return derivedKeys[i].chain < derivedKeys[j].chain
		}
		if derivedKeys[i].year != derivedKeys[j].year {
			return derivedKeys[i].year < derivedKeys[j].year
		}
		if derivedKeys[i].month != derivedKeys[j].month {
			return derivedKeys[i].month < derivedKeys[j].month
		}
		return derivedKeys[i].sku < derivedKeys[j].sku
	})

	for idx, dk := range derivedKeys {
		dv := derivedSellInAgg[dk]
		sellInVal := round2(dv.rev / 0.918)
		cases := round2(math.Max(1.0, float64(dv.units)/12.0/0.918))
		tons := round2(cases * 0.012)
		expCases := round2(cases * 1.06)
		expVal := round2(sellInVal * 1.06)
		regCode, govName := inferRegionFromBranch(dk.store, dk.chain)
		brandName, sectorCode := inferBrandAndSectorFromSKU(dk.sku, dk.cat)
		mIdx := dk.month
		if mIdx < 1 || mIdx > 12 {
			mIdx = 1
		}
		yr := dk.year
		if yr <= 0 {
			yr = 2026
		}
		chainDisplay := getRetailChainDisplayName(dk.chain)
		combinedSellIn = append(combinedSellIn, domain.SellInRecord{
			RecordID:           fmt.Sprintf("derived_%s_%d_%d_%d", dk.chain, yr, mIdx, idx),
			TenantID:           normTenant,
			RetailerChain:      dk.chain,
			Year:               yr,
			MonthNum:           mIdx,
			MonthEN:            monthNamesEN[mIdx-1],
			MonthAR:            monthNamesAR[mIdx-1],
			PeriodWeek:         "Full Month",
			RegionCode:         regCode,
			Governorate:        govName,
			Sector:             sectorCode,
			CustomerName:       chainDisplay,
			CustomerBranchCode: dk.store,
			Brand:              brandName,
			SubCategory:        dk.cat,
			ItemName:           dk.sku,
			PromotionType:      "عادي",
			SalesManager:       "إدارة مبيعات السلاسل التجارية",
			KAOfficer:          "مسؤول حسابات " + chainDisplay,
			SalesRep:           "فريق مبيعات " + govName,
			NetQtyCases:        cases,
			NetValueEGP:        sellInVal,
			TurnoverEGP:        sellInVal,
			WeightTons:         tons,
			ExpectedQtyCases:   expCases,
			ExpectedValueEGP:   expVal,
			TransactionType:    "مسحوبات بيع (Sale)",
		})
	}

	// Filter Sell-In rows by sector/region/brand/rep when requested
	filteredSellIn := make([]domain.SellInRecord, 0, len(combinedSellIn))
	allSkusSet := make(map[string]bool)
	allRepsSet := make(map[string]bool)
	salesMgrName := "إدارة المبيعات وتطوير السلاسل"
	kaOfficerName := "إدارة كبار العملاء (Key Accounts)"

	var mtRevTotal, ccRevTotal float64
	var ytdSellInEGP, ytdSellInCases, ytdWeightTons, ytdExpectedEGP float64
	var octActualEGP, octActualCases, octProjEGP, octProjCases float64
	var latestYM ymKey

	type monthAgg struct {
		year        int
		monthNum    int
		monthEN     string
		monthAR     string
		skus        map[string]bool
		sellInCases float64
		sellInEGP   float64
		tons        float64
		expCases    float64
		expEGP      float64
		hasWeekly   bool
	}
	monthMap := make(map[ymKey]*monthAgg)

	type brandAgg struct {
		sector   string
		brand    string
		skus     map[string]bool
		actCases float64
		actEGP   float64
		expCases float64
		expEGP   float64
		tons     float64
	}
	brandMap := make(map[string]*brandAgg)

	type regionAgg struct {
		code     string
		gov      string
		records  int
		actCases float64
		actEGP   float64
		expCases float64
		expEGP   float64
		tons     float64
	}
	regionMap := make(map[string]*regionAgg)

	type repAgg struct {
		rep      string
		officer  string
		mgr      string
		region   string
		gov      string
		branches map[string]bool
		skus     map[string]bool
		records  int
		actCases float64
		actEGP   float64
		expCases float64
		expEGP   float64
		tons     float64
		promoEGP float64
		retCases float64
		retEGP   float64
		mtEGP    float64
		ccEGP    float64
	}
	repMap := make(map[string]*repAgg)

	var promoSummary domain.PromoAndReturnSummary
	type returnAgg struct {
		itemName string
		brand    string
		sector   string
		region   string
		gov      string
		rep      string
		retCases float64
		retEGP   float64
		grossEGP float64
	}
	returnItemMap := make(map[string]*returnAgg)

	type skuInvAgg struct {
		skuName     string
		brand       string
		sector      string
		subCat      string
		region      string
		gov         string
		rep         string
		sellInCases float64
		sellInEGP   float64
		retCases    float64
		retEGP      float64
		tons        float64
		octCases    float64
		sepCases    float64
	}
	skuInvMap := make(map[string]*skuInvAgg)

	for _, rec := range combinedSellIn {
		if rec.SalesManager != "" && salesMgrName == "إدارة المبيعات وتطوير السلاسل" {
			salesMgrName = rec.SalesManager
		}
		if rec.KAOfficer != "" && kaOfficerName == "إدارة كبار العملاء (Key Accounts)" {
			kaOfficerName = rec.KAOfficer
		}
		if rec.Brand == "" || rec.Brand == "عام" || strings.EqualFold(rec.Brand, "other") || strings.EqualFold(rec.Brand, "general") || rec.Brand == "منتجات الشركة" {
			inferredBrand, inferredSec := inferBrandAndSectorFromSKU(rec.ItemName, rec.SubCategory)
			rec.Brand = inferredBrand
			if rec.Sector == "" || rec.Sector == "عام" {
				rec.Sector = inferredSec
			}
		}

		// Sector breakdown across tenant data
		if strings.EqualFold(rec.Sector, "CC") {
			ccRevTotal += rec.NetValueEGP
		} else {
			mtRevTotal += rec.NetValueEGP
		}

		if sectorFilter != "" && !strings.EqualFold(rec.Sector, sectorFilter) {
			continue
		}
		if regionFilter != "" && !strings.EqualFold(rec.RegionCode, regionFilter) {
			continue
		}
		if brandFilter != "" && !strings.EqualFold(rec.Brand, brandFilter) {
			continue
		}
		if repFilter != "" && !strings.EqualFold(rec.SalesRep, repFilter) {
			continue
		}
		if searchQ != "" {
			if !domain.MatchesProductSearchQuery(searchQ, rec.ItemCode, rec.Barcode, rec.ItemName, "", rec.SubCategory, rec.Brand) {
				continue
			}
		}

		filteredSellIn = append(filteredSellIn, rec)
		if rec.ItemName != "" {
			allSkusSet[rec.ItemName] = true
		}
		if rec.SalesRep != "" && !strings.Contains(rec.SalesRep, "توزيع مركزي") {
			allRepsSet[rec.SalesRep] = true
		}

		ytdSellInEGP += rec.NetValueEGP
		ytdSellInCases += rec.NetQtyCases
		ytdWeightTons += rec.WeightTons
		ytdExpectedEGP += rec.ExpectedValueEGP

		yr := rec.Year
		if yr <= 0 {
			yr = 2026
		}
		m := rec.MonthNum
		if m <= 0 || m > 12 {
			m = 1
		}
		curYM := ymKey{year: yr, month: m}
		if curYM.year > latestYM.year || (curYM.year == latestYM.year && curYM.month > latestYM.month) {
			latestYM = curYM
		}

		if m == 10 {
			octActualEGP += rec.NetValueEGP
			octActualCases += rec.NetQtyCases
			octProjEGP += rec.ExpectedValueEGP
			octProjCases += rec.ExpectedQtyCases
		}

		// 1) Monthly Aggregation by (Year, Month)
		ma, ok := monthMap[curYM]
		if !ok {
			mEN := rec.MonthEN
			if mEN == "" {
				mEN = monthNamesEN[m-1]
			}
			mAR := rec.MonthAR
			if mAR == "" {
				mAR = monthNamesAR[m-1]
			}
			ma = &monthAgg{
				year:     yr,
				monthNum: m,
				monthEN:  mEN,
				monthAR:  mAR,
				skus:     make(map[string]bool),
			}
			monthMap[curYM] = ma
		}
		if rec.ItemName != "" {
			ma.skus[rec.ItemName] = true
		}
		ma.sellInCases += rec.NetQtyCases
		ma.sellInEGP += rec.NetValueEGP
		ma.tons += rec.WeightTons
		ma.expCases += rec.ExpectedQtyCases
		ma.expEGP += rec.ExpectedValueEGP
		if rec.PeriodWeek == "W1" || rec.PeriodWeek == "W2" {
			ma.hasWeekly = true
		}

		// 2) Brand Forecast Aggregation
		bKey := rec.Sector + "|" + rec.Brand
		ba, ok := brandMap[bKey]
		if !ok {
			ba = &brandAgg{
				sector: rec.Sector,
				brand:  rec.Brand,
				skus:   make(map[string]bool),
			}
			brandMap[bKey] = ba
		}
		if rec.ItemName != "" {
			ba.skus[rec.ItemName] = true
		}
		ba.actCases += rec.NetQtyCases
		ba.actEGP += rec.NetValueEGP
		ba.expCases += rec.ExpectedQtyCases
		ba.expEGP += rec.ExpectedValueEGP
		ba.tons += rec.WeightTons

		// 3) Region & Governorate Aggregation
		rKey := rec.RegionCode + "|" + rec.Governorate
		ra, ok := regionMap[rKey]
		if !ok {
			ra = &regionAgg{
				code: rec.RegionCode,
				gov:  rec.Governorate,
			}
			regionMap[rKey] = ra
		}
		ra.records++
		ra.actCases += rec.NetQtyCases
		ra.actEGP += rec.NetValueEGP
		ra.expCases += rec.ExpectedQtyCases
		ra.expEGP += rec.ExpectedValueEGP
		ra.tons += rec.WeightTons

		// 4) Sales Rep Aggregation
		repName := rec.SalesRep
		if repName == "" {
			repName = "توزيع مركزي (Central KA)"
		}
		repKey := repName + "|" + rec.RegionCode + "|" + rec.Governorate
		rpa, ok := repMap[repKey]
		if !ok {
			rpa = &repAgg{
				rep:      repName,
				officer:  rec.KAOfficer,
				mgr:      rec.SalesManager,
				region:   rec.RegionCode,
				gov:      rec.Governorate,
				branches: make(map[string]bool),
				skus:     make(map[string]bool),
			}
			repMap[repKey] = rpa
		}
		rpa.records++
		if rec.CustomerBranchCode != "" {
			rpa.branches[rec.CustomerBranchCode] = true
		}
		if rec.ItemName != "" {
			rpa.skus[rec.ItemName] = true
		}
		rpa.actCases += rec.NetQtyCases
		rpa.actEGP += rec.NetValueEGP
		rpa.expCases += rec.ExpectedQtyCases
		rpa.expEGP += rec.ExpectedValueEGP
		rpa.tons += rec.WeightTons
		if strings.Contains(rec.PromotionType, "عرض") {
			rpa.promoEGP += rec.NetValueEGP
		}
		if rec.NetQtyCases < 0 || rec.NetValueEGP < 0 || strings.Contains(rec.TransactionType, "مرتجع") {
			rpa.retCases += math.Abs(rec.NetQtyCases)
			rpa.retEGP += math.Abs(rec.NetValueEGP)
		}
		if strings.EqualFold(rec.Sector, "CC") {
			rpa.ccEGP += rec.NetValueEGP
		} else {
			rpa.mtEGP += rec.NetValueEGP
		}

		// 5) Promo vs Regular & Returns Summary
		if strings.Contains(rec.PromotionType, "عرض") {
			promoSummary.PromoRecordsCount++
			promoSummary.PromoCases += rec.NetQtyCases
			promoSummary.PromoValueEGP += rec.NetValueEGP
			promoSummary.PromoTons += rec.WeightTons
		} else {
			promoSummary.RegularRecordsCount++
			promoSummary.RegularCases += rec.NetQtyCases
			promoSummary.RegularValueEGP += rec.NetValueEGP
			promoSummary.RegularTons += rec.WeightTons
		}

		if rec.NetQtyCases < 0 || rec.NetValueEGP < 0 || strings.Contains(rec.TransactionType, "مرتجع") {
			promoSummary.ReturnRecordsCount++
			absQ := math.Abs(rec.NetQtyCases)
			absV := math.Abs(rec.NetValueEGP)
			promoSummary.TotalReturnCases += absQ
			promoSummary.TotalReturnValueEGP += absV

			retKey := rec.ItemName + "|" + rec.RegionCode
			ri, exists := returnItemMap[retKey]
			if !exists {
				ri = &returnAgg{
					itemName: rec.ItemName,
					brand:    rec.Brand,
					sector:   rec.Sector,
					region:   rec.RegionCode,
					gov:      rec.Governorate,
					rep:      rec.SalesRep,
				}
				returnItemMap[retKey] = ri
			}
			ri.retCases += absQ
			ri.retEGP += absV
		} else if rec.NetValueEGP > 0 {
			retKey := rec.ItemName + "|" + rec.RegionCode
			if ri, exists := returnItemMap[retKey]; exists {
				ri.grossEGP += rec.NetValueEGP
			}
		}

		// 6) SKU x Region Inventory & Replenishment Aggregation
		if rec.ItemName != "" {
			invKey := rec.ItemName + "|" + rec.RegionCode
			sia, ok := skuInvMap[invKey]
			if !ok {
				sia = &skuInvAgg{
					skuName: rec.ItemName,
					brand:   rec.Brand,
					sector:  rec.Sector,
					subCat:  rec.SubCategory,
					region:  rec.RegionCode,
					gov:     rec.Governorate,
					rep:     rec.SalesRep,
				}
				skuInvMap[invKey] = sia
			}
			if rec.SalesRep != "" && !strings.Contains(rec.SalesRep, "توزيع مركزي") {
				sia.rep = rec.SalesRep
			}
			if rec.NetQtyCases >= 0 {
				sia.sellInCases += rec.NetQtyCases
				sia.sellInEGP += rec.NetValueEGP
			} else {
				sia.retCases += math.Abs(rec.NetQtyCases)
				sia.retEGP += math.Abs(rec.NetValueEGP)
			}
			sia.tons += rec.WeightTons
			if m == 10 {
				sia.octCases += math.Max(0, rec.NetQtyCases)
			} else if m == 9 {
				sia.sepCases += math.Max(0, rec.NetQtyCases)
			}
		}
	}

	// Ensure any (Year, Month) that has actual Sell-Out is also included in monthMap even if Sell-In is 0 for that month
	for ym, rev := range sellOutByYMRev {
		if rev <= 0 && sellOutByYMUnits[ym] <= 0 {
			continue
		}
		if _, exists := monthMap[ym]; !exists {
			mIdx := ym.month
			if mIdx < 1 || mIdx > 12 {
				mIdx = 1
			}
			monthMap[ym] = &monthAgg{
				year:     ym.year,
				monthNum: mIdx,
				monthEN:  monthNamesEN[mIdx-1],
				monthAR:  monthNamesAR[mIdx-1],
				skus:     make(map[string]bool),
			}
		}
	}

	// If latest month is not October, populate the Forecast cards from the latest active month
	if octActualEGP == 0 && latestYM.month > 0 {
		if lm, ok := monthMap[latestYM]; ok {
			octActualEGP = lm.sellInEGP
			octActualCases = lm.sellInCases
			octProjEGP = lm.expEGP
			octProjCases = lm.expCases
		}
	}

	// Sort all (Year, Month) keys chronologically for cumulative remaining stock reconciliation
	sortedYMKeys := make([]ymKey, 0, len(monthMap))
	for k := range monthMap {
		sortedYMKeys = append(sortedYMKeys, k)
	}
	sort.Slice(sortedYMKeys, func(i, j int) bool {
		if sortedYMKeys[i].year != sortedYMKeys[j].year {
			return sortedYMKeys[i].year < sortedYMKeys[j].year
		}
		return sortedYMKeys[i].month < sortedYMKeys[j].month
	})

	reconciliationList := make([]domain.ReconciliationMonthItem, 0, len(sortedYMKeys))

	monthlySellThroughRatios := map[int]float64{
		1:  0.9339,
		2:  0.928,
		3:  0.945,
		4:  0.916,
		5:  0.931,
		6:  0.942,
		7:  0.918,
		8:  0.918,
		9:  0.924,
		10: 0.895,
		11: 0.920,
		12: 0.930,
	}

	var totalReconciledSellOutEGP float64
	runningStockCasesByYear := make(map[int]float64)
	runningStockValByYear := make(map[int]float64)
	useRealSellOutReconciliation := hasRealUploadedSellOut || normTenant == "tenant-adeco"

	for _, ym := range sortedYMKeys {
		ma := monthMap[ym]
		m := ym.month
		yr := ym.year

		var sellOutVal float64
		var sellOutUnits int
		if useRealSellOutReconciliation {
			// Use 100% real uploaded Sell-Out for this exact (Year, Month)
			sellOutVal = round2(sellOutByYMRev[ym])
			sellOutUnits = sellOutByYMUnits[ym]
		} else {
			ratio := monthlySellThroughRatios[m]
			if ratio <= 0 {
				ratio = 0.918
			}
			sellOutVal = round2(ma.sellInEGP * ratio)
			sellOutUnits = int(math.Round(ma.sellInCases * 12.0 * ratio))
		}

		totalReconciledSellOutEGP += sellOutVal

		openingCases := round2(runningStockCasesByYear[yr])
		openingVal := round2(runningStockValByYear[yr])
		sellInCases := round2(ma.sellInCases)
		sellInVal := round2(ma.sellInEGP)

		var sellOutEstCases float64
		if sellInCases > 0 && sellInVal > 0 {
			avgCasePrice := sellInVal / sellInCases
			if avgCasePrice > 0 {
				sellOutEstCases = round2(sellOutVal / avgCasePrice)
			}
		} else if useRealSellOutReconciliation && sellOutByYMCases[ym] > 0 {
			sellOutEstCases = round2(sellOutByYMCases[ym])
		} else if sellOutUnits > 0 {
			sellOutEstCases = round2(float64(sellOutUnits) / 12.0)
		}

		monthlyNetCases := round2(sellInCases - sellOutEstCases)
		monthlyNetVal := round2(sellInVal - sellOutVal)

		closingCases := round2(math.Max(0, openingCases+monthlyNetCases))
		closingVal := round2(math.Max(0, openingVal+monthlyNetVal))
		runningStockCasesByYear[yr] = closingCases
		runningStockValByYear[yr] = closingVal

		gap := monthlyNetVal
		strPct := 0.0
		if sellInVal > 0 {
			strPct = round2((sellOutVal / sellInVal) * 100.0)
		} else if sellOutVal > 0 {
			strPct = 100.0
		}

		status := "مغلق (Full Month)"
		if ma.hasWeekly || (m == 10 && sellInVal > 0 && ma.expEGP > sellInVal) {
			status = "قيد الإغلاق (W1+W2 → EXP)"
		}

		var healthStatus, healthLabelAr string
		switch {
		case sellInVal > 0 && sellOutVal == 0:
			healthStatus = "awaiting_sell_out"
			healthLabelAr = "رصيد مضاف للمخزن (بانتظار رفع شيت السحب Sell-Out للشهر)"
		case sellInVal == 0 && sellOutVal > 0:
			healthStatus = "awaiting_sell_in"
			healthLabelAr = "سحب فعلي مسجل (بانتظار رفع شيت التوريد Sell-In للشهر)"
		case sellOutVal > sellInVal:
			healthStatus = "drawdown"
			healthLabelAr = "سحب عالٍ يفوق توريد الشهر (تصريف من الرصيد السابق - يحتاج تعويض)"
		case strPct >= 75.0:
			healthStatus = "balanced"
			healthLabelAr = "معدل تصريف صحي ورصيد متبقي آمن"
		default:
			healthStatus = "accumulation"
			healthLabelAr = "تراكم مخزني بالفرع (التوريد أعلى من السحب - راقب الرصيد المتبقي)"
		}

		reconciliationList = append(reconciliationList, domain.ReconciliationMonthItem{
			Year:                 yr,
			MonthNum:             m,
			MonthEN:              ma.monthEN,
			MonthAR:              ma.monthAR,
			PeriodStatus:         status,
			ActiveSKUsCount:      len(ma.skus),
			OpeningStockCases:    openingCases,
			OpeningStockValueEGP: openingVal,
			SellInCases:          sellInCases,
			SellInValueEGP:       sellInVal,
			SellOutUnits:         sellOutUnits,
			SellOutEstCases:      sellOutEstCases,
			SellOutValueEGP:      sellOutVal,
			MonthlyNetCases:      monthlyNetCases,
			MonthlyNetValueEGP:   monthlyNetVal,
			ClosingStockCases:    closingCases,
			ClosingStockValueEGP: closingVal,
			InventoryGapEGP:      gap,
			SellThroughRatePct:   strPct,
			WeightTons:           round2(ma.tons),
			ExpectedCases:        round2(ma.expCases),
			ExpectedValueEGP:     round2(ma.expEGP),
			StockHealthStatus:    healthStatus,
			StockHealthLabelAr:   healthLabelAr,
		})
	}

	// Determine Spotlight KPI metrics (Sell-In, Sell-Out, Remaining Balance Gap, STR%)
	spotlightSellInEGP := round2(ytdSellInEGP)
	spotlightSellOutEGP := round2(totalReconciledSellOutEGP)
	spotlightGapEGP := round2(math.Max(0, spotlightSellInEGP-spotlightSellOutEGP))
	spotlightSTR := 0.0
	if spotlightSellInEGP > 0 {
		spotlightSTR = round2((spotlightSellOutEGP / spotlightSellInEGP) * 100.0)
	} else if spotlightSellOutEGP > 0 {
		spotlightSTR = 100.0
	}

	// Build Brand Forecasts list
	brandList := make([]domain.BrandForecastItem, 0, len(brandMap))
	for _, ba := range brandMap {
		ach := 100.0
		if ba.expEGP > 0 {
			ach = round2((ba.actEGP / ba.expEGP) * 100.0)
		}
		share := 0.0
		if ytdSellInEGP > 0 {
			share = round2((ba.actEGP / ytdSellInEGP) * 100.0)
		}
		secAr := ba.sector
		if strings.EqualFold(ba.sector, "MT") {
			secAr = "قطاع المنظفات والعناية المنزلية (MT)"
		} else if strings.EqualFold(ba.sector, "CC") {
			secAr = "قطاع العناية بالسيارات (CC)"
		}
		brandList = append(brandList, domain.BrandForecastItem{
			Sector:             ba.sector,
			SectorNameAr:       secAr,
			Brand:              ba.brand,
			ActiveSKUsCount:    len(ba.skus),
			ActualCases:        round2(ba.actCases),
			ActualValueEGP:     round2(ba.actEGP),
			ExpectedCases:      round2(ba.expCases),
			ExpectedValueEGP:   round2(ba.expEGP),
			ForecastUpliftEGP:  round2(ba.expEGP - ba.actEGP),
			AchievementRatePct: ach,
			WeightTons:         round2(ba.tons),
			ShareOfTotalPct:    share,
		})
	}
	sort.Slice(brandList, func(i, j int) bool {
		return brandList[i].ActualValueEGP > brandList[j].ActualValueEGP
	})

	// Build Region Performance list
	regionList := make([]domain.RegionPerformanceItem, 0, len(regionMap))
	for _, ra := range regionMap {
		share := 0.0
		if ytdSellInEGP > 0 {
			share = round2((ra.actEGP / ytdSellInEGP) * 100.0)
		}
		regionList = append(regionList, domain.RegionPerformanceItem{
			RegionCode:       ra.code,
			Governorate:      ra.gov,
			RecordsCount:     ra.records,
			ActualCases:      round2(ra.actCases),
			ActualValueEGP:   round2(ra.actEGP),
			ExpectedCases:    round2(ra.expCases),
			ExpectedValueEGP: round2(ra.expEGP),
			WeightTons:       round2(ra.tons),
			SharePct:         share,
		})
	}
	sort.Slice(regionList, func(i, j int) bool {
		return regionList[i].ActualValueEGP > regionList[j].ActualValueEGP
	})

	// Build Sales Rep Scorecards
	repList := make([]domain.SalesRepScorecard, 0, len(repMap))
	for _, rpa := range repMap {
		ach := 100.0
		if rpa.expEGP > 0 {
			ach = round2((rpa.actEGP / rpa.expEGP) * 100.0)
		}
		promoShare := 0.0
		if rpa.actEGP > 0 {
			promoShare = round2((rpa.promoEGP / rpa.actEGP) * 100.0)
		}
		retRate := 0.0
		if rpa.actEGP+rpa.retEGP > 0 {
			retRate = round2((rpa.retEGP / (rpa.actEGP + rpa.retEGP)) * 100.0)
		}
		branchesCnt := len(rpa.branches)
		if branchesCnt <= 0 {
			branchesCnt = 1
		}
		repList = append(repList, domain.SalesRepScorecard{
			SalesRep:            rpa.rep,
			KAOfficer:           rpa.officer,
			SalesManager:        rpa.mgr,
			RegionCode:          rpa.region,
			Governorate:         rpa.gov,
			ServedBranchesCount: branchesCnt,
			ActiveSKUsCount:     len(rpa.skus),
			RecordsCount:        rpa.records,
			ActualCases:         round2(rpa.actCases),
			ActualValueEGP:      round2(rpa.actEGP),
			ExpectedCases:       round2(rpa.expCases),
			ExpectedValueEGP:    round2(rpa.expEGP),
			AchievementPct:      ach,
			WeightTons:          round2(rpa.tons),
			PromoValueEGP:       round2(rpa.promoEGP),
			PromoSharePct:       promoShare,
			ReturnCases:         round2(rpa.retCases),
			ReturnValueEGP:      round2(rpa.retEGP),
			ReturnRatePct:       retRate,
			MTValueEGP:          round2(rpa.mtEGP),
			CCValueEGP:          round2(rpa.ccEGP),
		})
	}
	sort.Slice(repList, func(i, j int) bool {
		iCentral := strings.Contains(repList[i].SalesRep, "توزيع مركزي")
		jCentral := strings.Contains(repList[j].SalesRep, "توزيع مركزي")
		if iCentral != jCentral {
			return !iCentral
		}
		return repList[i].ActualValueEGP > repList[j].ActualValueEGP
	})

	// Build Promo & Returns summary
	promoSummary.RegularCases = round2(promoSummary.RegularCases)
	promoSummary.RegularValueEGP = round2(promoSummary.RegularValueEGP)
	promoSummary.RegularTons = round2(promoSummary.RegularTons)
	promoSummary.PromoCases = round2(promoSummary.PromoCases)
	promoSummary.PromoValueEGP = round2(promoSummary.PromoValueEGP)
	promoSummary.PromoTons = round2(promoSummary.PromoTons)
	promoSummary.TotalReturnCases = round2(promoSummary.TotalReturnCases)
	promoSummary.TotalReturnValueEGP = round2(promoSummary.TotalReturnValueEGP)

	if ytdSellInEGP > 0 {
		promoSummary.PromoValueSharePct = round2((promoSummary.PromoValueEGP / ytdSellInEGP) * 100.0)
		promoSummary.OverallReturnPct = round2((promoSummary.TotalReturnValueEGP / (ytdSellInEGP + promoSummary.TotalReturnValueEGP)) * 100.0)
	}
	if ytdSellInCases > 0 {
		promoSummary.PromoVolumeSharePct = round2((promoSummary.PromoCases / ytdSellInCases) * 100.0)
	}
	if promoSummary.PromoCases > 0 {
		promoSummary.AvgPromoCaseTons = round2(promoSummary.PromoTons / promoSummary.PromoCases)
	}

	topReturns := make([]domain.ReturnItemSummary, 0, len(returnItemMap))
	for _, ri := range returnItemMap {
		if ri.retEGP <= 0 {
			continue
		}
		retPct := 100.0
		if ri.grossEGP+ri.retEGP > 0 {
			retPct = round2((ri.retEGP / (ri.grossEGP + ri.retEGP)) * 100.0)
		}
		topReturns = append(topReturns, domain.ReturnItemSummary{
			ItemName:       ri.itemName,
			Brand:          ri.brand,
			Sector:         ri.sector,
			RegionCode:     ri.region,
			Governorate:    ri.gov,
			SalesRep:       ri.rep,
			ReturnCases:    round2(ri.retCases),
			ReturnValueEGP: round2(ri.retEGP),
			ReturnRatePct:  retPct,
		})
	}
	sort.Slice(topReturns, func(i, j int) bool {
		return topReturns[i].ReturnValueEGP > topReturns[j].ReturnValueEGP
	})
	if len(topReturns) > 25 {
		topReturns = topReturns[:25]
	}
	promoSummary.TopReturnItems = topReturns

	// Build SKU x Region Estimated Inventory & Suggested Replenishment PO
	invItems := make([]domain.SKUBranchInventoryItem, 0, len(skuInvMap))
	var totalEstStockCases, totalEstStockEGP float64
	var totalSuggestedPOCases int
	var totalSuggestedPOEGP, totalSuggestedPOTons float64
	var urgentCount, overstockCount int

	activeDays := math.Max(30.0, float64(len(monthMap))*30.0)

	for _, sia := range skuInvMap {
		if sia.sellInCases <= 0 {
			continue
		}
		casePrice := 480.0
		if sia.sellInCases > 0 && sia.sellInEGP > 0 {
			casePrice = sia.sellInEGP / sia.sellInCases
		}
		caseTons := 0.012
		if sia.sellInCases > 0 && sia.tons > 0 {
			caseTons = sia.tons / sia.sellInCases
		}

		sellThroughFactor := 0.918
		if chainFilter == "fathalla" {
			sellThroughFactor = 0.934
		}
		if sia.retCases > 0 && sia.sellInCases > 0 {
			retRatio := math.Min(0.15, sia.retCases/sia.sellInCases)
			sellThroughFactor = math.Max(0.82, 0.945-retRatio)
		} else if sia.octCases > sia.sepCases*0.45 && sia.octCases > 0 {
			sellThroughFactor = 0.955
		}

		netSupplyCases := math.Max(0, sia.sellInCases-sia.retCases)
		sellOutCases := round2(netSupplyCases * sellThroughFactor)
		sellOutVal := round2(sellOutCases * casePrice)

		estStockCases := round2(math.Max(0, netSupplyCases-sellOutCases))
		estStockVal := round2(estStockCases * casePrice)

		adr := sellOutCases / activeDays
		if sia.octCases > 0 {
			octDaily := (sia.octCases * sellThroughFactor) / 14.0
			adr = (adr*0.4 + octDaily*0.6)
		}
		if adr < 0.05 {
			adr = 0.05
		}
		adr = round2(adr)

		doi := 0.0
		if adr > 0 {
			doi = round2(estStockCases / adr)
		}

		targetCases := float64(leadTime+safetyDays) * adr
		rawNeeded := math.Max(0, targetCases-estStockCases)
		suggestedCases := int(math.Ceil(rawNeeded))
		suggestedVal := round2(float64(suggestedCases) * casePrice)
		suggestedTons := round2(float64(suggestedCases) * caseTons)

		status := "optimal"
		statusAr := "رصيد آمن ومثالي"
		if doi <= float64(leadTime+4) || suggestedCases >= 5 {
			status = "urgent_replenishment"
			statusAr = "خطر نفاد عاجل - أمر توريد فوري"
		} else if doi > 28 {
			status = "overstock"
			statusAr = "تكدس مخزني - تجميد سيولة"
		}

		if statusFilter != "" && status != statusFilter {
			continue
		}

		if status == "urgent_replenishment" {
			urgentCount++
		} else if status == "overstock" {
			overstockCount++
		}

		totalEstStockCases += estStockCases
		totalEstStockEGP += estStockVal
		totalSuggestedPOCases += suggestedCases
		totalSuggestedPOEGP += suggestedVal
		totalSuggestedPOTons += suggestedTons

		invItem := domain.SKUBranchInventoryItem{
			SKUName:                sia.skuName,
			Brand:                  sia.brand,
			Sector:                 sia.sector,
			SubCategory:            sia.subCat,
			RegionCode:             sia.region,
			Governorate:            sia.gov,
			SalesRep:               sia.rep,
			SellInCases:            round2(sia.sellInCases),
			SellInValueEGP:         round2(sia.sellInEGP),
			SellOutEstCases:        sellOutCases,
			SellOutValueEGP:        sellOutVal,
			ReturnCases:            round2(sia.retCases),
			ReturnValueEGP:         round2(sia.retEGP),
			EstimatedStockCases:    estStockCases,
			EstimatedStockValueEGP: estStockVal,
			DailyRunRateCases:      adr,
			DaysOfInventory:        doi,
			StockStatus:            status,
			StockStatusAr:          statusAr,
			CasePriceEGP:           round2(casePrice),
			WeightTons:             round2(sia.tons),
			SuggestedPOCases:       suggestedCases,
			SuggestedPOValueEGP:    suggestedVal,
			SuggestedPOTons:        suggestedTons,
		}
		if pm, ok := c.lookupProductMasterLocked(normTenant, "", "", sia.skuName); ok {
			invItem.ItemCode = pm.ItemCode
			invItem.Barcode = pm.Barcode
			invItem.UnitsPerCarton = pm.UnitsPerCarton
			invItem.ItemType = pm.ItemType
			invItem.FactoryCartonCost = pm.NetCartonInvoiceCost
		}
		invItems = append(invItems, invItem)
	}

	sort.Slice(invItems, func(i, j int) bool {
		if invItems[i].SuggestedPOValueEGP != invItems[j].SuggestedPOValueEGP {
			return invItems[i].SuggestedPOValueEGP > invItems[j].SuggestedPOValueEGP
		}
		return invItems[i].SellInValueEGP > invItems[j].SellInValueEGP
	})

	combinedSectorRev := mtRevTotal + ccRevTotal
	mtShare := 0.0
	ccShare := 0.0
	if combinedSectorRev > 0 {
		mtShare = round2((mtRevTotal / combinedSectorRev) * 100.0)
		ccShare = round2((ccRevTotal / combinedSectorRev) * 100.0)
	}

	displayInvItems := invItems
	if len(displayInvItems) > 150 {
		displayInvItems = displayInvItems[:150]
	}

	effectiveChainOut := chainFilter
	if effectiveChainOut == "" {
		effectiveChainOut = "all"
	}

	payload := &domain.CPFRDashboardPayload{
		TenantID:                 normTenant,
		RetailerChain:            effectiveChainOut,
		SourceFilename:           filename,
		TotalRecords:             len(filteredSellIn),
		ActiveSKUsCount:          len(allSkusSet),
		ActiveRepsCount:          len(allRepsSet),
		SalesManagerName:         salesMgrName,
		KAOfficerName:            kaOfficerName,
		Jan2026SellInEGP:         round2(spotlightSellInEGP),
		Jan2026SellOutEGP:        round2(spotlightSellOutEGP),
		Jan2026GapEGP:            round2(spotlightGapEGP),
		Jan2026SellThroughPct:    spotlightSTR,
		YTD2026SellInEGP:         round2(ytdSellInEGP),
		YTD2026SellInCases:       round2(ytdSellInCases),
		YTD2026WeightTons:        round2(ytdWeightTons),
		YTD2026ExpectedEGP:       round2(ytdExpectedEGP),
		OctW1W2ActualEGP:         round2(octActualEGP),
		OctW1W2ActualCases:       round2(octActualCases),
		OctProjectedMonthEndEGP:  round2(octProjEGP),
		OctProjectedCases:        round2(octProjCases),
		MTRevenueEGP:             round2(mtRevTotal),
		MTSharePct:               mtShare,
		CCRevenueEGP:             round2(ccRevTotal),
		CCSharePct:               ccShare,
		TotalEstimatedStockCases: round2(totalEstStockCases),
		TotalEstimatedStockEGP:   round2(totalEstStockEGP),
		TotalSuggestedPOCases:    totalSuggestedPOCases,
		TotalSuggestedPOEGP:      round2(totalSuggestedPOEGP),
		TotalSuggestedPOTons:     round2(totalSuggestedPOTons),
		UrgentReplenishmentCount: urgentCount,
		OverstockAlertCount:      overstockCount,
		LeadTimeDays:             leadTime,
		SafetyStockDays:          safetyDays,
		MonthlyReconciliation:    reconciliationList,
		InventoryAndPOItems:      displayInvItems,
		BrandForecasts:           brandList,
		RegionPerformances:       regionList,
		SalesRepScorecards:       repList,
		PromoAndReturns:          promoSummary,
	}

	return payload, nil
}

func extractYearAndMonthFromDate(dateStr string) (int, int) {
	parts := strings.Split(strings.TrimSpace(dateStr), "-")
	yr := 2026
	if len(parts) >= 1 && len(parts[0]) == 4 {
		switch parts[0] {
		case "2024":
			yr = 2024
		case "2025":
			yr = 2025
		case "2026":
			yr = 2026
		case "2027":
			yr = 2027
		}
	}
	return yr, extractMonthFromDate(dateStr)
}

func extractMonthFromDate(dateStr string) int {
	parts := strings.Split(strings.TrimSpace(dateStr), "-")
	if len(parts) >= 2 {
		switch parts[1] {
		case "01", "1":
			return 1
		case "02", "2":
			return 2
		case "03", "3":
			return 3
		case "04", "4":
			return 4
		case "05", "5":
			return 5
		case "06", "6":
			return 6
		case "07", "7":
			return 7
		case "08", "8":
			return 8
		case "09", "9":
			return 9
		case "10":
			return 10
		case "11":
			return 11
		case "12":
			return 12
		}
	}
	return 1
}

func round2(v float64) float64 {
	return math.Round(v*100.0) / 100.0
}

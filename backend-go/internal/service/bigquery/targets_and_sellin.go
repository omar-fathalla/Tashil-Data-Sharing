package bigquery

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func getTargetsStorageDir() string {
	dir := os.Getenv("TASHIL_TARGETS_DIR")
	if dir == "" {
		dir = "data/targets"
	}
	return dir
}

func (c *Client) loadPersistedTargets() {
	dir := getTargetsStorageDir()
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
		var list []domain.TargetRecord
		if err := json.Unmarshal(raw, &list); err != nil {
			continue
		}
		tenantKey := strings.TrimSuffix(entry.Name(), ".json")
		normTenant := normalizeTenantKey(tenantKey)
		c.targets[normTenant] = list
	}
}

func (c *Client) persistTenantTargetsLocked(normTenant string) {
	dir := getTargetsStorageDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	list := c.targets[normTenant]
	if list == nil {
		list = []domain.TargetRecord{}
	}
	if data, err := json.MarshalIndent(list, "", "  "); err == nil {
		_ = os.WriteFile(filepath.Join(dir, normTenant+".json"), data, 0o644)
	}
}

func formatTargetMonthLabel(year, month int) string {
	if month <= 0 || month > 12 {
		return fmt.Sprintf("إجمالي سنة %d (كل الشهور)", year)
	}
	arabicMonths := map[int]string{
		1:  "يناير",
		2:  "فبراير",
		3:  "مارس",
		4:  "أبريل",
		5:  "مايو",
		6:  "يونيو",
		7:  "يوليو",
		8:  "أغسطس",
		9:  "سبتمبر",
		10: "أكتوبر",
		11: "نوفمبر",
		12: "ديسمبر",
	}
	return fmt.Sprintf("%s %d", arabicMonths[month], year)
}

func buildDeterministicTargetID(normTenant, targetType, chain string, year, month int, branch, category string) string {
	ch := strings.ToLower(strings.TrimSpace(chain))
	if ch == "" {
		ch = "all"
	}
	br := strings.ToLower(strings.TrimSpace(branch))
	if br == "" || br == "كل الفروع" {
		br = "all"
	}
	cat := strings.ToLower(strings.TrimSpace(category))
	if cat == "" || cat == "كل الفئات" {
		cat = "all"
	}
	tType := strings.ToLower(strings.TrimSpace(targetType))
	if tType != "sell_in" {
		tType = "sell_out"
	}
	return fmt.Sprintf("tgt_%s_%s_%s_%04d_%02d_%s_%s", normTenant, tType, ch, year, month, br, cat)
}

// GetSellInRecords returns filtered and paginated Supplier Sell-In records for the Sell-In Explorer table.
func (c *Client) GetSellInRecords(ctx context.Context, tenantID string, filter SellInRecordFilter) ([]domain.SellInRecord, int, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normTenant := normalizeTenantKey(tenantID)
	rawRecords := c.sellInRecords[normTenant]

	chainFilter := strings.ToLower(strings.TrimSpace(filter.RetailerChain))
	if chainFilter == "all" || chainFilter == "الكل" {
		chainFilter = ""
	}
	regionFilter := strings.ToUpper(strings.TrimSpace(filter.RegionCode))
	if regionFilter == "ALL" || regionFilter == "الكل" {
		regionFilter = ""
	}
	sectorFilter := strings.ToUpper(strings.TrimSpace(filter.Sector))
	if sectorFilter == "ALL" || sectorFilter == "الكل" {
		sectorFilter = ""
	}
	brandFilter := strings.ToLower(strings.TrimSpace(filter.Brand))
	if brandFilter == "all" || brandFilter == "الكل" {
		brandFilter = ""
	}
	qLower := strings.ToLower(strings.TrimSpace(filter.SearchQuery))

	var matched []domain.SellInRecord
	for _, r := range rawRecords {
		if r.TenantID == "" {
			r.TenantID = normTenant
		}
		if r.ItemCode == "" || r.TotalUnitsSupplied == 0 || r.CanonicalFamilyKey == "" {
			c.enrichSellInRecordLocked(&r)
		}
		rChain := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if rChain == "" {
			rChain = "fathalla"
			r.RetailerChain = rChain
		}
		if chainFilter != "" && !strings.EqualFold(rChain, chainFilter) {
			continue
		}
		if filter.Year > 0 && r.Year != filter.Year {
			continue
		}
		if filter.Month > 0 && r.MonthNum != filter.Month {
			continue
		}
		if regionFilter != "" && !strings.EqualFold(r.RegionCode, regionFilter) && !strings.Contains(strings.ToUpper(r.Governorate), regionFilter) {
			continue
		}
		if sectorFilter != "" && !strings.EqualFold(r.Sector, sectorFilter) {
			continue
		}
		if brandFilter != "" && !strings.Contains(strings.ToLower(r.Brand), brandFilter) {
			continue
		}
		if qLower != "" {
			matchProd := domain.MatchesProductSearchQuery(filter.SearchQuery, r.ItemCode, r.Barcode, r.ItemName, r.ItemName, r.SubCategory, r.Brand)
			matchCustomer := strings.Contains(strings.ToLower(r.CustomerName), qLower)
			matchRep := strings.Contains(strings.ToLower(r.SalesRep), qLower)
			matchGov := strings.Contains(strings.ToLower(r.Governorate), qLower)
			if !matchProd && !matchCustomer && !matchRep && !matchGov {
				continue
			}
		}
		matched = append(matched, r)
	}

	sort.Slice(matched, func(i, j int) bool {
		if matched[i].Year != matched[j].Year {
			return matched[i].Year > matched[j].Year
		}
		if matched[i].MonthNum != matched[j].MonthNum {
			return matched[i].MonthNum > matched[j].MonthNum
		}
		return matched[i].NetValueEGP > matched[j].NetValueEGP
	})

	total := len(matched)
	if filter.Offset >= total {
		return []domain.SellInRecord{}, total, nil
	}
	end := filter.Offset + filter.Limit
	if filter.Limit <= 0 || end > total {
		end = total
	}
	return matched[filter.Offset:end], total, nil
}

// inferChainUnitPriceAndTonsLocked computes the historical average case/unit price and tons per case for auto-conversion.
func (c *Client) inferChainUnitPriceAndTonsLocked(normTenant, targetType, chain string) (avgPrice float64, tonsPerUnit float64) {
	ch := strings.ToLower(strings.TrimSpace(chain))
	if ch == "all" || ch == "الكل" {
		ch = ""
	}
	if targetType == "sell_in" {
		var totRev, totCases, totTons float64
		for _, r := range c.sellInRecords[normTenant] {
			rChain := strings.ToLower(strings.TrimSpace(r.RetailerChain))
			if rChain == "" {
				rChain = "fathalla"
			}
			if ch != "" && !strings.EqualFold(rChain, ch) {
				continue
			}
			if r.NetValueEGP > 0 && r.NetQtyCases > 0 {
				totRev += r.NetValueEGP
				totCases += r.NetQtyCases
				if r.WeightTons > 0 {
					totTons += r.WeightTons
				}
			}
		}
		if totCases <= 0 && ch != "" {
			// Fallback to tenant-wide Sell-In average if the specific chain has no Sell-In rows yet
			for _, r := range c.sellInRecords[normTenant] {
				if r.NetValueEGP > 0 && r.NetQtyCases > 0 {
					totRev += r.NetValueEGP
					totCases += r.NetQtyCases
					if r.WeightTons > 0 {
						totTons += r.WeightTons
					}
				}
			}
		}
		avgPrice = 585.0
		if totCases > 0 && totRev > 0 {
			avgPrice = totRev / totCases
		}
		tonsPerUnit = 0.0145
		if totCases > 0 && totTons > 0 {
			tonsPerUnit = totTons / totCases
		}
		return avgPrice, tonsPerUnit
	}

	// sell_out
	var totRev float64
	var totUnits int
	for _, r := range c.records {
		if !matchTenant(r.TenantID, normTenant) || !isOwnRecord(r) {
			continue
		}
		if ch != "" && !strings.EqualFold(r.RetailerChain, ch) {
			continue
		}
		if r.NetRevenue > 0 && r.QuantitySold > 0 {
			totRev += r.NetRevenue
			totUnits += r.QuantitySold
		}
	}
	avgPrice = 70.0
	if totUnits > 0 && totRev > 0 {
		avgPrice = totRev / float64(totUnits)
	}
	return avgPrice, 0.001
}

// UpsertTarget creates or updates a Sell-Out or Sell-In target for a tenant and persists it to disk.
func (c *Client) UpsertTarget(ctx context.Context, tenantID string, target domain.TargetRecord) (*domain.TargetRecord, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.bumpSourceVersion()

	normTenant := normalizeTenantKey(tenantID)
	tType := strings.ToLower(strings.TrimSpace(target.TargetType))
	if tType != "sell_in" {
		tType = "sell_out"
	}
	target.TargetType = tType
	target.TenantID = normTenant

	ch := strings.ToLower(strings.TrimSpace(target.RetailerChain))
	if ch == "" || ch == "الكل" {
		ch = "all"
	}
	target.RetailerChain = ch
	if ch == "all" {
		target.ChainDisplayName = "كل السلاسل (All Chains)"
	} else {
		target.ChainDisplayName = getRetailChainDisplayName(ch)
	}

	if target.Year <= 0 {
		target.Year = 2026
	}
	if target.Month < 0 || target.Month > 12 {
		target.Month = 0
	}
	target.MonthLabel = formatTargetMonthLabel(target.Year, target.Month)

	br := strings.TrimSpace(target.BranchName)
	if br == "" || strings.EqualFold(br, "all") {
		br = "كل الفروع"
	}
	target.BranchName = br

	cat := strings.TrimSpace(target.Category)
	if cat == "" || strings.EqualFold(cat, "all") {
		cat = "كل الفئات"
	}
	target.Category = cat

	// Auto-complete TargetUnits or TargetRevenueEGP if the user entered one and left the other open
	avgPrice, _ := c.inferChainUnitPriceAndTonsLocked(normTenant, tType, ch)
	if target.TargetRevenueEGP > 0 && target.TargetUnits <= 0 && avgPrice > 0 {
		target.TargetUnits = math.Round(target.TargetRevenueEGP / avgPrice)
	} else if target.TargetUnits > 0 && target.TargetRevenueEGP <= 0 && avgPrice > 0 {
		target.TargetRevenueEGP = math.Round(target.TargetUnits * avgPrice)
	}

	if strings.TrimSpace(target.ID) == "" {
		target.ID = buildDeterministicTargetID(normTenant, tType, ch, target.Year, target.Month, br, cat)
	}
	target.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	existing := c.targets[normTenant]
	updated := false
	for i := range existing {
		if existing[i].ID == target.ID ||
			(existing[i].TargetType == target.TargetType &&
				strings.EqualFold(existing[i].RetailerChain, target.RetailerChain) &&
				existing[i].Year == target.Year &&
				existing[i].Month == target.Month &&
				strings.EqualFold(existing[i].BranchName, target.BranchName) &&
				strings.EqualFold(existing[i].Category, target.Category)) {
			target.ID = existing[i].ID
			existing[i] = target
			updated = true
			break
		}
	}
	if !updated {
		existing = append(existing, target)
	}
	c.targets[normTenant] = existing
	c.persistTenantTargetsLocked(normTenant)

	res := target
	return &res, nil
}

// DeleteTarget deletes a target record by ID for a tenant and updates disk storage.
func (c *Client) DeleteTarget(ctx context.Context, tenantID, targetID string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.bumpSourceVersion()

	normTenant := normalizeTenantKey(tenantID)
	existing := c.targets[normTenant]
	var kept []domain.TargetRecord
	found := false
	for _, item := range existing {
		if item.ID == targetID {
			found = true
			continue
		}
		kept = append(kept, item)
	}
	if !found {
		return fmt.Errorf("target not found: %s", targetID)
	}
	c.targets[normTenant] = kept
	c.persistTenantTargetsLocked(normTenant)
	return nil
}

// GetTargetsSummary returns all targets for a tenant & targetType ("sell_out" or "sell_in") compared against real Actual data
// and decomposed into a full 3-tier hierarchy (Chain -> Branch -> SKU) + Chain Total SKUs + Brands + Sales Reps + Monthly Phasing.
func (c *Client) GetTargetsSummary(ctx context.Context, tenantID, targetType, chain string, year int) (*domain.TargetsSummaryResponse, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normTenant := normalizeTenantKey(tenantID)
	tType := strings.ToLower(strings.TrimSpace(targetType))
	if tType != "sell_in" {
		tType = "sell_out"
	}
	chainFilter := strings.ToLower(strings.TrimSpace(chain))
	if chainFilter == "all" || chainFilter == "الكل" {
		chainFilter = ""
	}

	savedTargets := c.targets[normTenant]
	var items []domain.TargetComparisonItem
	var totalTargetRev, totalActualRev, totalTargetUnits, totalActualUnits float64
	var compTargetRev, compActualRev, compTargetUnits, compActualUnits, noDataTargetRev, noDataTargetUnits float64
	var compCount, noDataCount int
	var totalTargetTons, totalActualTons, totalExpRev, totalExpUnits, totalGrossRev, totalGrossUnits float64
	branchesSet := make(map[string]bool)
	skusSet := make(map[string]bool)

	for _, t := range savedTargets {
		if t.TargetType != tType {
			continue
		}
		if chainFilter != "" && t.RetailerChain != "all" && !strings.EqualFold(t.RetailerChain, chainFilter) {
			continue
		}
		if year > 0 && t.Year != year {
			continue
		}

		item := c.buildComprehensiveTargetItemLocked(normTenant, t)
		items = append(items, item)

		totalTargetRev += item.TargetRevenueEGP
		totalActualRev += item.ActualRevenueEGP
		totalTargetUnits += item.TargetUnits
		totalActualUnits += item.ActualUnits
		if item.HasActuals {
			compTargetRev += item.TargetRevenueEGP
			compActualRev += item.ActualRevenueEGP
			compTargetUnits += item.TargetUnits
			compActualUnits += item.ActualUnits
			compCount++
		} else {
			noDataCount++
			noDataTargetRev += item.TargetRevenueEGP
			noDataTargetUnits += item.TargetUnits
		}
		totalTargetTons += item.TargetWeightTons
		totalActualTons += item.ActualWeightTons
		totalExpRev += item.ExpectedRevenueEGP
		totalExpUnits += item.ExpectedUnits
		totalGrossRev += item.GrossTargetRevenueEGP
		totalGrossUnits += item.GrossTargetUnits

		for _, b := range item.Branches {
			branchesSet[b.BranchName] = true
		}
		for _, s := range item.ChainSKUTotals {
			skusSet[s.SKUName] = true
		}
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].Year != items[j].Year {
			return items[i].Year > items[j].Year
		}
		if items[i].Month != items[j].Month {
			return items[i].Month < items[j].Month
		}
		return items[i].TargetRevenueEGP > items[j].TargetRevenueEGP
	})

	if items == nil {
		items = []domain.TargetComparisonItem{}
	}

	// Achievement and variance only compare periods that have actual data; a future-year target
	// stays in the target total but never counts as "0% achieved".
	overallAch := 0.0
	if compTargetRev > 0 {
		overallAch = math.Round((compActualRev/compTargetRev)*1000) / 10
	} else if compTargetUnits > 0 {
		overallAch = math.Round((compActualUnits/compTargetUnits)*1000) / 10
	}

	avgCasePrice, _ := c.inferChainUnitPriceAndTonsLocked(normTenant, tType, chainFilter)

	return &domain.TargetsSummaryResponse{
		TenantID:                   normTenant,
		TargetType:                 tType,
		TotalTargetRevenueEGP:      round2(totalTargetRev),
		TotalActualRevenueEGP:      round2(totalActualRev),
		TotalVarianceEGP:           round2(compActualRev - compTargetRev),
		OverallAchievementPct:      overallAch,
		TotalTargetUnits:           round2(totalTargetUnits),
		TotalActualUnits:           round2(totalActualUnits),
		TotalTargetWeightTons:      round2(totalTargetTons),
		TotalActualWeightTons:      round2(totalActualTons),
		TotalExpectedRevenueEGP:    round2(totalExpRev),
		TotalExpectedUnits:         round2(totalExpUnits),
		TotalGrossTargetRevenueEGP: round2(totalGrossRev),
		TotalGrossTargetUnits:      round2(totalGrossUnits),
		AvgCasePriceEGP:            round2(avgCasePrice),
		TotalBranchesCovered:       len(branchesSet),
		TotalSKUsCovered:           len(skusSet),
		ComparableTargetRevenueEGP: round2(compTargetRev),
		ComparableActualRevenueEGP: round2(compActualRev),
		ComparableTargetsCount:     compCount,
		NoDataTargetsCount:         noDataCount,
		NoDataTargetRevenueEGP:     round2(noDataTargetRev),
		NoDataTargetUnits:          round2(noDataTargetUnits),
		Items:                      items,
	}, nil
}

// chainBranchTemplate defines a canonical branch metadata entry when decomposing regional Sell-In across physical chain branches.
type chainBranchTemplate struct {
	Code        string
	Name        string
	RegionCode  string
	Governorate string
	SalesRep    string
	KAOfficer   string
	BaseWeight  float64
}

func defaultChainBranchCatalog(chainCode string) []chainBranchTemplate {
	ch := strings.ToLower(strings.TrimSpace(chainCode))
	switch ch {
	case "gomla":
		return []chainBranchTemplate{
			{"gom_nasr_city", "جملة ماركت - مدينة نصر", "CIR", "القاهرة الكبرى", "فريق مبيعات شرق القاهرة", "إدارة كبار العملاء - جملة ماركت", 0.22},
			{"gom_maadi", "جملة ماركت - المعادي", "CIR", "القاهرة الكبرى", "فريق مبيعات جنوب القاهرة", "إدارة كبار العملاء - جملة ماركت", 0.18},
			{"gom_october", "جملة ماركت - 6 أكتوبر", "CIR", "القاهرة الكبرى", "فريق مبيعات الجيزة وأكتوبر", "إدارة كبار العملاء - جملة ماركت", 0.16},
			{"gom_tagamoa", "جملة ماركت - التجمع الخامس", "CIR", "القاهرة الكبرى", "فريق مبيعات القاهرة الجديدة", "إدارة كبار العملاء - جملة ماركت", 0.15},
			{"gom_smouha", "جملة ماركت - سموحة الإسكندرية", "ALX", "الإسكندرية", "فريق مبيعات الإسكندرية", "إدارة كبار العملاء - جملة ماركت", 0.15},
			{"gom_mansoura", "جملة ماركت - المنصورة", "MNS", "المنصورة (الدقهلية)", "فريق مبيعات الدلتا", "إدارة كبار العملاء - جملة ماركت", 0.14},
		}
	case "beet-elgomla", "beet_elgomla":
		return []chainBranchTemplate{
			{"bg_smouha", "بيت الجملة - سموحة", "ALX", "الإسكندرية", "كريم محمد محمد", "إدارة كبار العملاء - بيت الجملة", 0.20},
			{"bg_louran", "بيت الجملة - لوران", "ALX", "الإسكندرية", "عصام الدين احمد محمد", "إدارة كبار العملاء - بيت الجملة", 0.17},
			{"bg_agamy", "بيت الجملة - البيطاش العجمي", "ALX", "الإسكندرية", "عبدالله محمد محمود", "إدارة كبار العملاء - بيت الجملة", 0.15},
			{"bg_mandara", "بيت الجملة - المندرة", "ALX", "الإسكندرية", "خالد عبدالمنعم", "إدارة كبار العملاء - بيت الجملة", 0.14},
			{"bg_tanta", "بيت الجملة - طنطا", "TNT", "الغربية", "شعبان احمد مصباح", "إدارة كبار العملاء - بيت الجملة", 0.18},
			{"bg_damanhour", "بيت الجملة - دمنهور", "BHR", "البحيرة", "محمود محمد طه", "إدارة كبار العملاء - بيت الجملة", 0.16},
		}
	case "chain-1080314":
		return []chainBranchTemplate{
			{"wak_alex_main", "الوكالة - المركز الرئيسي الإسكندرية", "ALX", "الإسكندرية", "كريم محمد محمد", "إدارة حسابات الوكالة", 0.34},
			{"wak_alex_west", "الوكالة - فرع غرب الإسكندرية", "ALX", "الإسكندرية", "عبدالله محمد محمود", "إدارة حسابات الوكالة", 0.24},
			{"wak_beheira", "الوكالة - فرع البحيرة ودمنهور", "BHR", "البحيرة", "محمود محمد طه", "إدارة حسابات الوكالة", 0.22},
			{"wak_tanta", "الوكالة - فرع الدلتا وطنطا", "TNT", "الغربية", "شعبان احمد مصباح", "إدارة حسابات الوكالة", 0.20},
		}
	default:
		// Canonical 34 Fathalla branches with their ERP codes, Governorates, Region codes, and assigned Field Sales Reps
		return []chainBranchTemplate{
			{"311350557", "فرع فتح الله - مدينة الرحاب", "CIR", "القاهرة", "احمد مصطفى خلف", "اشرف احمد عبد السلام صفى الدين", 11844941.0},
			{"311350428", "فرع فتح الله - طنطا - اوت ليت مول", "TNT", "الغربية", "شعبان احمد مصباح", "اشرف احمد عبد السلام صفى الدين", 5324242.25},
			{"311350147", "فرع فتح الله - سموحة", "ALX", "الاسكندرية", "كريم محمد محمد", "اشرف احمد عبد السلام صفى الدين", 4979065.44},
			{"311351226", "فرع فتح الله - المحلة الكبرى", "TNT", "الغربية", "احمد محمد سعيد", "اشرف احمد عبد السلام صفى الدين", 4005793.25},
			{"311350034", "فرع فتح الله - فلمنج", "ALX", "الاسكندرية", "عصام الدين احمد محمد", "اشرف احمد عبد السلام صفى الدين", 3436683.05},
			{"311350893", "فرع فتح الله - عجمي ستار", "ALX", "الاسكندرية", "عبدالله محمد محمود", "اشرف احمد عبد السلام صفى الدين", 3418068.50},
			{"311350551", "فرع فتح الله - جاردينيا", "ALX", "الاسكندرية", "خالد عبدالمنعم", "اشرف احمد عبد السلام صفى الدين", 3174150.50},
			{"311350210", "فرع فتح الله - ستانلى", "ALX", "الاسكندرية", "حسام حسن عبدالله", "اشرف احمد عبد السلام صفى الدين", 3031742.00},
			{"311350954", "فرع فتح الله - دمنهور الأندلس", "BHR", "البحيرة", "محمود محمد طه", "اشرف احمد عبد السلام صفى الدين", 2802828.50},
			{"BHR-311350955", "فرع فتح الله - دمنهور - الاستاد", "BHR", "البحيرة", "محمود محمد طه", "اشرف احمد عبد السلام صفى الدين", 2325507.75},
			{"ALX-311350894", "فرع فتح الله - ابو يوسف", "ALX", "الاسكندرية", "عبدالله محمد محمود", "اشرف احمد عبد السلام صفى الدين", 2273009.75},
			{"311350051", "فرع فتح الله - مطروح", "ALX", "مطروح", "طه مصطفى سريع", "اشرف احمد عبد السلام صفى الدين", 2203467.25},
			{"ALX-311350148", "فرع فتح الله - النصر", "ALX", "الاسكندرية", "كريم محمد محمد", "اشرف احمد عبد السلام صفى الدين", 2067828.25},
			{"ALX-311350895", "فرع فتح الله - هانوفيل", "ALX", "الاسكندرية", "عبدالله محمد محمود", "اشرف احمد عبد السلام صفى الدين", 1919804.50},
			{"TNT-311350429", "فرع فتح الله - طنطا", "TNT", "الغربية", "شعبان احمد مصباح", "اشرف احمد عبد السلام صفى الدين", 1871965.50},
			{"311351458", "فرع فتح الله - كفر الدوار - مول", "BHR", "البحيرة", "مصطفى كمال احمد", "اشرف احمد عبد السلام صفى الدين", 1761058.25},
			{"MNS-311352001", "فرع فتح الله - دمياط الجديدة", "MNS", "المنصورة (الدقهلية)", "توزيع مركزي (Central KA)", "اشرف احمد عبد السلام صفى الدين", 1726377.25},
			{"ALX-311350552", "فرع فتح الله - طوسون", "ALX", "الاسكندرية", "خالد عبدالمنعم", "اشرف احمد عبد السلام صفى الدين", 1692509.50},
			{"311351471", "فرع فتح الله - الإبراهيمية", "ALX", "الاسكندرية", "عمار يسرى عبدالكريم", "اشرف احمد عبد السلام صفى الدين", 1688637.19},
			{"ALX-311350211", "فرع فتح الله - سيتي سكوير", "ALX", "الاسكندرية", "حسام حسن عبدالله", "اشرف احمد عبد السلام صفى الدين", 1493027.00},
			{"ALX-04058-0044", "فرع فتح الله - ملك حفنى", "ALX", "الاسكندرية", "أحمد محمد محمد", "اشرف احمد عبد السلام صفى الدين", 1246101.25},
			{"ALX-311350553", "فرع فتح الله - سيدي بشر ميني", "ALX", "الاسكندرية", "خالد عبدالمنعم", "اشرف احمد عبد السلام صفى الدين", 1224098.75},
			{"CIR-311350558", "فرع فتح الله - أكتوبر", "CIR", "القاهرة", "احمد مصطفى خلف", "اشرف احمد عبد السلام صفى الدين", 1135596.75},
			{"BHR-311351459", "فرع فتح الله - كفر الدوار", "BHR", "البحيرة", "مصطفى كمال احمد", "اشرف احمد عبد السلام صفى الدين", 1118669.75},
			{"ALX-311350052", "فرع فتح الله - أمواج - الساحل الشمالي", "ALX", "مطروح", "طه مصطفى سريع", "اشرف احمد عبد السلام صفى الدين", 908030.75},
			{"ALX-311350035", "فرع فتح الله - سيدي جابر المحطة", "ALX", "الاسكندرية", "عصام الدين احمد محمد", "اشرف احمد عبد السلام صفى الدين", 852223.25},
			{"ALX-311351472", "فرع فتح الله - الأنفوشي", "ALX", "الاسكندرية", "عمار يسرى عبدالكريم", "اشرف احمد عبد السلام صفى الدين", 815907.25},
			{"ALX-311351473", "فرع فتح الله - الإبراهيمية ميني", "ALX", "الاسكندرية", "عمار يسرى عبدالكريم", "اشرف احمد عبد السلام صفى الدين", 711506.75},
			{"ALX-311350036", "فرع فتح الله - سيدي جابر ميني", "ALX", "الاسكندرية", "عصام الدين احمد محمد", "اشرف احمد عبد السلام صفى الدين", 570639.25},
			{"ALX-311350896", "فرع فتح الله - الدخيلة ميني", "ALX", "الاسكندرية", "عبدالله محمد محمود", "اشرف احمد عبد السلام صفى الدين", 432705.75},
			{"ALX-311350149", "فرع فتح الله - سموحة ميني", "ALX", "الاسكندرية", "كريم محمد محمد", "اشرف احمد عبد السلام صفى الدين", 374321.75},
			{"ALX-311350897", "فرع فتح الله - الدخيلة مينى 2", "ALX", "الاسكندرية", "عبدالله محمد محمود", "اشرف احمد عبد السلام صفى الدين", 134250.50},
			{"ALX-311350150", "فرع فتح الله - روزانا", "ALX", "الاسكندرية", "كريم محمد محمد", "اشرف احمد عبد السلام صفى الدين", 102009.50},
			{"ALX-311350212", "فرع فتح الله - نيس2", "ALX", "الاسكندرية", "حسام حسن عبدالله", "اشرف احمد عبد السلام صفى الدين", 77070.00},
		}
	}
}

func classifyTargetStatus(pct float64) (string, string) {
	if pct >= 100.0 {
		return "exceeded", "تجاوز المستهدف"
	}
	if pct >= 85.0 {
		return "on_track", "قيد التحقيق الجيد"
	}
	return "at_risk", "أقل من المستهدف"
}

// buildComprehensiveTargetItemLocked builds a complete TargetComparisonItem with 3-tier drill-down:
// Level 1: Chain Summary (Target vs Actual vs Expected, Cases, Tons, Return Buffer, Promo Mix)
// Level 2: All Chain Branches (Target EGP, Target Cases, Target Tons, Actuals, Variance, Sales Rep, Governorate)
// Level 3: All SKUs inside each Branch + Chain-wide Total SKUs Summary + Brand Summary + Sales Rep Quotas + 12-Month Seasonality Phasing.
func (c *Client) buildComprehensiveTargetItemLocked(normTenant string, t domain.TargetRecord) domain.TargetComparisonItem {
	ch := strings.ToLower(strings.TrimSpace(t.RetailerChain))
	if ch == "all" || ch == "الكل" {
		ch = ""
	}
	brFilter := strings.ToLower(strings.TrimSpace(t.BranchName))
	if brFilter == "all" || brFilter == "كل الفروع" {
		brFilter = ""
	}
	catFilter := strings.ToLower(strings.TrimSpace(t.Category))
	if catFilter == "all" || catFilter == "كل الفئات" {
		catFilter = ""
	}

	avgCasePrice, avgTonsPerCase := c.inferChainUnitPriceAndTonsLocked(normTenant, t.TargetType, ch)
	targetRev := t.TargetRevenueEGP
	targetUnits := t.TargetUnits
	if targetRev > 0 && targetUnits <= 0 && avgCasePrice > 0 {
		targetUnits = math.Round(targetRev / avgCasePrice)
	} else if targetUnits > 0 && targetRev <= 0 && avgCasePrice > 0 {
		targetRev = math.Round(targetUnits * avgCasePrice)
	}
	targetTons := round2(targetUnits * avgTonsPerCase)

	chainDisp := t.ChainDisplayName
	if chainDisp == "" {
		if t.RetailerChain == "all" {
			chainDisp = "كل السلاسل (All Chains)"
		} else {
			chainDisp = getRetailChainDisplayName(t.RetailerChain)
		}
	}

	// If targetType is sell_out, preserve fast sell_out comparison
	if t.TargetType != "sell_in" {
		actualRev, actualUnits, actualRows := c.computeActualForTargetLocked(normTenant, t)
		varianceRev := round2(actualRev - targetRev)
		varianceUnits := round2(actualUnits - targetUnits)
		achRevPct := 0.0
		if targetRev > 0 {
			achRevPct = math.Round((actualRev/targetRev)*1000) / 10
		}
		achUnitsPct := 0.0
		if targetUnits > 0 {
			achUnitsPct = math.Round((actualUnits/targetUnits)*1000) / 10
		}
		checkPct := achRevPct
		if targetRev <= 0 && targetUnits > 0 {
			checkPct = achUnitsPct
		}
		status, statusAr := classifyTargetStatus(checkPct)
		if actualRows == 0 {
			varianceRev, varianceUnits, achRevPct, achUnitsPct = 0, 0, 0, 0
			status, statusAr = "no_data", "لا توجد مبيعات بعد"
		}
		return domain.TargetComparisonItem{
			ID:                  t.ID,
			TenantID:            normTenant,
			TargetType:          t.TargetType,
			RetailerChain:       t.RetailerChain,
			ChainDisplayName:    chainDisp,
			Year:                t.Year,
			Month:               t.Month,
			MonthLabel:          formatTargetMonthLabel(t.Year, t.Month),
			BranchName:          t.BranchName,
			Category:            t.Category,
			TargetRevenueEGP:    round2(targetRev),
			ActualRevenueEGP:    round2(actualRev),
			VarianceRevenueEGP:  varianceRev,
			AchievementRevPct:   achRevPct,
			TargetUnits:         round2(targetUnits),
			ActualUnits:         round2(actualUnits),
			VarianceUnits:       varianceUnits,
			AchievementUnitsPct: achUnitsPct,
			AvgCasePriceEGP:     round2(avgCasePrice),
			HasActuals:          actualRows > 0,
			Status:              status,
			StatusAr:            statusAr,
			Notes:               t.Notes,
			UpdatedAt:           t.UpdatedAt,
			Branches:            []domain.TargetBranchBreakdown{},
			ChainSKUTotals:      []domain.TargetSKUBreakdown{},
			Brands:              []domain.TargetBrandBreakdown{},
			SalesRepQuotas:      []domain.TargetSalesRepQuota{},
			MonthlyPhasing:      []domain.TargetMonthBreakdown{},
		}
	}

	// =========================================================================
	// COMPREHENSIVE SELL-IN TARGET DECOMPOSITION (CHAIN -> BRANCH -> SKU)
	// =========================================================================
	allTenantSellIn := c.sellInRecords[normTenant]

	// 1. Collect Period Actual Sell-In Records & Historical Baseline Weight Records
	var periodRecs []domain.SellInRecord
	var chainHistoryRecs []domain.SellInRecord

	for _, r := range allTenantSellIn {
		rChain := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if rChain == "" {
			rChain = "fathalla"
		}
		matchChain := (ch == "" || strings.EqualFold(rChain, ch))
		if !matchChain {
			continue
		}
		if catFilter != "" &&
			!strings.Contains(strings.ToLower(r.Brand), catFilter) &&
			!strings.Contains(strings.ToLower(r.SubCategory), catFilter) &&
			!strings.Contains(strings.ToLower(r.Sector), catFilter) &&
			!strings.Contains(strings.ToLower(r.ItemName), catFilter) {
			continue
		}
		chainHistoryRecs = append(chainHistoryRecs, r)

		if t.Year > 0 && r.Year != t.Year {
			continue
		}
		if t.Month > 0 && r.MonthNum != t.Month {
			continue
		}
		if brFilter != "" &&
			!strings.Contains(strings.ToLower(r.CustomerName), brFilter) &&
			!strings.Contains(strings.ToLower(r.CustomerBranchCode), brFilter) &&
			!strings.Contains(strings.ToLower(r.Governorate), brFilter) &&
			!strings.EqualFold(r.RegionCode, brFilter) {
			continue
		}
		periodRecs = append(periodRecs, r)
	}

	// If a chain has no explicit Sell-In history yet, fallback to tenant-wide Sell-In history for SKU/Brand structure
	weightRecs := chainHistoryRecs
	if len(weightRecs) == 0 {
		weightRecs = allTenantSellIn
	}

	// Compute overall Actuals & Expected from periodRecs, and Return/Promo/Sector ratios from weightRecs
	var actualRev, actualUnits, actualTons, expRev, expUnits float64
	for _, r := range periodRecs {
		actualRev += r.NetValueEGP
		actualUnits += r.NetQtyCases
		actualTons += r.WeightTons
		expRev += r.ExpectedValueEGP
		expUnits += r.ExpectedQtyCases
	}

	var histGrossRev, histReturnRev, histPromoRev, histMTRev, histCCRev float64
	var histTotalRev, histTotalCases, histTotalTons float64
	for _, r := range weightRecs {
		if r.NetValueEGP < 0 || r.NetQtyCases < 0 || strings.Contains(r.TransactionType, "مرتجع") {
			histReturnRev += math.Abs(r.NetValueEGP)
		} else {
			histGrossRev += r.NetValueEGP
			if strings.Contains(r.PromotionType, "عرض") {
				histPromoRev += r.NetValueEGP
			}
		}
		if r.NetValueEGP > 0 {
			histTotalRev += r.NetValueEGP
		}
		if r.NetQtyCases > 0 {
			histTotalCases += r.NetQtyCases
		}
		if r.WeightTons > 0 {
			histTotalTons += r.WeightTons
		}
		if strings.EqualFold(r.Sector, "CC") {
			histCCRev += math.Max(0, r.NetValueEGP)
		} else {
			histMTRev += math.Max(0, r.NetValueEGP)
		}
	}

	if histTotalCases > 0 && histTotalRev > 0 {
		avgCasePrice = histTotalRev / histTotalCases
	}
	if histTotalCases > 0 && histTotalTons > 0 {
		avgTonsPerCase = histTotalTons / histTotalCases
		targetTons = round2(targetUnits * avgTonsPerCase)
	}

	returnRatePct := 1.8 // realistic baseline buffer if zero returns recorded
	if histGrossRev > 0 && histReturnRev > 0 {
		returnRatePct = math.Round((histReturnRev/histGrossRev)*1000) / 10
		if returnRatePct < 0.5 {
			returnRatePct = 0.5
		}
	}
	grossMultiplier := 1.0 + (returnRatePct / 100.0)
	grossTargetRev := round2(targetRev * grossMultiplier)
	grossTargetUnits := round2(targetUnits * grossMultiplier)

	promoSharePct := 28.5
	if histGrossRev > 0 {
		promoSharePct = math.Round((histPromoRev/histGrossRev)*1000) / 10
	}
	promoTargetRev := round2(targetRev * (promoSharePct / 100.0))
	regTargetRev := round2(targetRev - promoTargetRev)

	mtShare := 0.92
	if (histMTRev + histCCRev) > 0 {
		mtShare = histMTRev / (histMTRev + histCCRev)
	}
	mtTargetRev := round2(targetRev * mtShare)
	ccTargetRev := round2(targetRev - mtTargetRev)

	// 2. Build Sell-Out SKU & Store Maps for Stock-Aware Allocation & Physical Branch Weights
	sellOutStoreRev := make(map[string]float64)
	sellOutSkuUnits := make(map[string]int)
	sellOutCodeUnits := make(map[string]int)
	sellOutFamCases := make(map[string]float64)
	sellOutMonths := make(map[int]bool)
	for _, sr := range c.records {
		if !matchTenant(sr.TenantID, normTenant) || !isOwnRecord(sr) {
			continue
		}
		srChain := strings.ToLower(strings.TrimSpace(sr.RetailerChain))
		if srChain == "" {
			srChain = "fathalla"
		}
		if ch != "" && !strings.EqualFold(srChain, ch) {
			continue
		}
		if sr.StoreName != "" && sr.NetRevenue > 0 {
			sellOutStoreRev[sr.StoreName] += sr.NetRevenue
		}
		yr, m := extractYearAndMonthFromDate(sr.TransactionDate)
		if t.Year > 0 && yr > 0 && yr != t.Year {
			continue
		}
		if m > 0 {
			sellOutMonths[m] = true
		}
		if sr.SKUName != "" && sr.QuantitySold > 0 {
			sellOutSkuUnits[sr.SKUName] += sr.QuantitySold
			upc := sr.UnitsPerCarton
			pm, pmOk := c.lookupProductMasterLocked(normTenant, sr.ItemCode, sr.Barcode, sr.SKUName)
			if upc <= 0 {
				if pmOk && pm.UnitsPerCarton > 0 {
					upc = pm.UnitsPerCarton
				} else {
					upc = 12
				}
			}
			codeKey := strings.ToUpper(strings.TrimSpace(sr.ItemCode))
			if codeKey == "" && pmOk {
				codeKey = strings.ToUpper(strings.TrimSpace(pm.ItemCode))
			}
			if codeKey != "" {
				sellOutCodeUnits[codeKey] += sr.QuantitySold
			}
			var famKey string
			if pmOk {
				famKey = CanonicalSellInFamilyKey(&pm, sr.SKUName)
			} else {
				famKey = CanonicalSellInFamilyKey(nil, sr.SKUName)
			}
			sellOutFamCases[famKey] += float64(sr.QuantitySold) / float64(upc)
		}
	}

	// 3. Aggregate Chain-Wide SKUs from weightRecs (and periodRecs for actuals)
	type skuStat struct {
		itemCode              string
		barcode               string
		unitsPerCarton        int
		departmentAr          string
		officialCartonExclVAT float64
		officialCartonInclVAT float64
		famKey                string
		promoType             string
		name                  string
		brand                 string
		sector                string
		subCat                string
		histRev               float64
		histCases             float64
		matchedCases          float64
		histTons              float64
		promoRev              float64
		actRev                float64
		actCases              float64
		actTons               float64
		expRev                float64
		expCases              float64
		byRegionRev           map[string]float64
	}
	skuMap := make(map[string]*skuStat)

	for _, r := range weightRecs {
		name := strings.TrimSpace(r.ItemName)
		if name == "" {
			continue
		}
		st, ok := skuMap[name]
		if !ok {
			brand := strings.TrimSpace(r.Brand)
			sec := strings.TrimSpace(r.Sector)
			if brand == "" || brand == "عام" {
				brand, sec = inferBrandAndSectorFromSKU(name, r.SubCategory)
			}
			if sec == "" {
				sec = "MT"
			}
			st = &skuStat{
				itemCode:              r.ItemCode,
				barcode:               r.Barcode,
				unitsPerCarton:        r.UnitsPerCarton,
				departmentAr:          r.DepartmentAr,
				officialCartonExclVAT: r.OfficialCartonExclVATEGP,
				officialCartonInclVAT: r.OfficialCartonInclVATEGP,
				famKey:                r.CanonicalFamilyKey,
				promoType:             r.PromotionType,
				name:                  name,
				brand:                 brand,
				sector:                sec,
				subCat:                r.SubCategory,
				byRegionRev:           make(map[string]float64),
			}
			skuMap[name] = st
		}
		if st.itemCode == "" && r.ItemCode != "" {
			st.itemCode = r.ItemCode
			st.barcode = r.Barcode
			st.unitsPerCarton = r.UnitsPerCarton
			st.departmentAr = r.DepartmentAr
			st.officialCartonExclVAT = r.OfficialCartonExclVATEGP
			st.officialCartonInclVAT = r.OfficialCartonInclVATEGP
			st.famKey = r.CanonicalFamilyKey
		}
		if r.NetValueEGP > 0 {
			st.histRev += r.NetValueEGP
			reg := strings.ToUpper(strings.TrimSpace(r.RegionCode))
			if reg == "" {
				reg = "ALX"
			}
			st.byRegionRev[reg] += r.NetValueEGP
			if strings.Contains(r.PromotionType, "عرض") {
				st.promoRev += r.NetValueEGP
			}
		}
		if r.NetQtyCases > 0 {
			st.histCases += r.NetQtyCases
			if sellOutMonths[r.MonthNum] && (t.Year == 0 || r.Year == 0 || r.Year == t.Year) {
				st.matchedCases += r.NetQtyCases
			}
		}
		if r.WeightTons > 0 {
			st.histTons += r.WeightTons
		}
	}

	for _, r := range periodRecs {
		name := strings.TrimSpace(r.ItemName)
		if name == "" {
			continue
		}
		st, ok := skuMap[name]
		if !ok {
			brand, sec := inferBrandAndSectorFromSKU(name, r.SubCategory)
			st = &skuStat{
				itemCode:              r.ItemCode,
				barcode:               r.Barcode,
				unitsPerCarton:        r.UnitsPerCarton,
				departmentAr:          r.DepartmentAr,
				officialCartonExclVAT: r.OfficialCartonExclVATEGP,
				officialCartonInclVAT: r.OfficialCartonInclVATEGP,
				famKey:                r.CanonicalFamilyKey,
				promoType:             r.PromotionType,
				name:                  name,
				brand:                 brand,
				sector:                sec,
				subCat:                r.SubCategory,
				byRegionRev:           make(map[string]float64),
			}
			skuMap[name] = st
		}
		st.actRev += r.NetValueEGP
		st.actCases += r.NetQtyCases
		st.actTons += r.WeightTons
		st.expRev += r.ExpectedValueEGP
		st.expCases += r.ExpectedQtyCases
	}

	// Build sorted list of Chain-Wide SKUs and compute total weight + enrich from Product Master
	skuList := make([]*skuStat, 0, len(skuMap))
	var totalSkuHistRev, totalSkuHistCases float64
	famHistCasesTotal := make(map[string]float64)
	famMatchedCasesTotal := make(map[string]float64)
	for _, st := range skuMap {
		if st.histRev <= 0 && st.actRev > 0 {
			st.histRev = st.actRev
		}
		if st.histCases <= 0 && st.actCases > 0 {
			st.histCases = st.actCases
		}
		if st.histRev <= 0 {
			st.histRev = 1000.0
		}
		if st.histCases <= 0 {
			st.histCases = math.Max(1.0, st.histRev/avgCasePrice)
		}
		actualCP := 0.0
		if st.histCases > 0 && st.histRev > 0 {
			actualCP = st.histRev / st.histCases
		}
		if st.itemCode == "" || st.unitsPerCarton <= 0 || st.officialCartonExclVAT <= 0 {
			if pm, pmOk := c.lookupProductMasterWithPriceLocked(normTenant, st.itemCode, st.barcode, st.name, st.promoType, actualCP); pmOk {
				st.itemCode = pm.ItemCode
				st.barcode = pm.Barcode
				st.unitsPerCarton = pm.UnitsPerCarton
				st.departmentAr = pm.DepartmentAr
				if st.departmentAr == "" {
					st.departmentAr = domain.InferDepartmentArFromPrefix(pm.ItemCodePrefix)
				}
				st.officialCartonExclVAT = pm.CartonPriceExclVAT
				st.officialCartonInclVAT = pm.CartonPriceInclVAT
				st.famKey = CanonicalSellInFamilyKey(&pm, st.name)
			}
		}
		if st.unitsPerCarton <= 0 {
			st.unitsPerCarton = 12
		}
		if st.famKey == "" {
			st.famKey = CanonicalSellInFamilyKey(nil, st.name)
		}
		famHistCasesTotal[st.famKey] += st.histCases
		famMatchedCasesTotal[st.famKey] += st.matchedCases
		totalSkuHistRev += st.histRev
		totalSkuHistCases += st.histCases
		skuList = append(skuList, st)
	}
	sort.Slice(skuList, func(i, j int) bool {
		if skuList[i].histRev != skuList[j].histRev {
			return skuList[i].histRev > skuList[j].histRev
		}
		return skuList[i].name < skuList[j].name
	})

	// Build ChainSKUTotals (إجمالي البضاعة المطلوبة للسلسلة بالكامل صنفاً بصنف)
	chainSKUTotals := make([]domain.TargetSKUBreakdown, 0, len(skuList))
	var allocatedChainSkuRev, allocatedChainSkuUnits float64
	for idx, st := range skuList {
		revShare := 0.0
		if totalSkuHistRev > 0 {
			revShare = st.histRev / totalSkuHistRev
		}
		unitShare := revShare
		if totalSkuHistCases > 0 {
			unitShare = st.histCases / totalSkuHistCases
		}

		sTargetRev := round2(targetRev * revShare)
		sTargetUnits := round2(targetUnits * unitShare)
		if idx == len(skuList)-1 && len(skuList) > 0 {
			// Exact reconciliation on the final SKU so sum == Chain Target
			if targetRev > 0 {
				sTargetRev = round2(math.Max(0, targetRev-allocatedChainSkuRev))
			}
			if targetUnits > 0 {
				sTargetUnits = round2(math.Max(0, targetUnits-allocatedChainSkuUnits))
			}
		}
		allocatedChainSkuRev += sTargetRev
		allocatedChainSkuUnits += sTargetUnits

		casePrice := avgCasePrice
		if st.histCases > 0 && st.histRev > 0 {
			casePrice = st.histRev / st.histCases
		} else if st.officialCartonExclVAT > 0 {
			casePrice = st.officialCartonExclVAT * 0.90
		}
		tonsPerC := avgTonsPerCase
		if st.histCases > 0 && st.histTons > 0 {
			tonsPerC = st.histTons / st.histCases
		}
		sTargetTons := round2(sTargetUnits * tonsPerC)

		achPct := 0.0
		if sTargetRev > 0 {
			achPct = math.Round((st.actRev/sTargetRev)*1000) / 10
		} else if sTargetUnits > 0 {
			achPct = math.Round((st.actCases/sTargetUnits)*1000) / 10
		}

		upc := st.unitsPerCarton
		if upc <= 0 {
			upc = 12
		}

		// Estimate remaining stock & stock health for this SKU using canonical family Sell-Out across matched months
		var sellOutEstCases float64
		codeKey := strings.ToUpper(strings.TrimSpace(st.itemCode))
		if famCases, ok := sellOutFamCases[st.famKey]; ok && famCases > 0 {
			if famMatchedCasesTotal[st.famKey] > 0 && st.matchedCases > 0 {
				sellOutEstCases = famCases * (st.matchedCases / famMatchedCasesTotal[st.famKey])
			} else if famHistCasesTotal[st.famKey] > 0 {
				sellOutEstCases = famCases * (st.histCases / famHistCasesTotal[st.famKey])
			}
		} else if codeUnits, ok := sellOutCodeUnits[codeKey]; ok && codeKey != "" && codeUnits > 0 {
			sellOutEstCases = float64(codeUnits) / float64(upc)
		} else if rawUnits, ok := sellOutSkuUnits[st.name]; ok && rawUnits > 0 {
			sellOutEstCases = float64(rawUnits) / float64(upc)
		} else if len(sellOutFamCases) == 0 && st.histCases > 0 {
			sellOutEstCases = st.histCases * 0.85
		}
		supplyBasis := st.histCases
		if len(sellOutMonths) > 0 && st.matchedCases > 0 {
			supplyBasis = st.matchedCases
		}
		remStock := round2(math.Max(0, supplyBasis-sellOutEstCases))
		stockRatio := 0.22
		if supplyBasis > 0 {
			stockRatio = remStock / supplyBasis
		}
		stStatus := "optimal"
		stStatusAr := "رصيد آمن ومتوازن"
		if stockRatio < 0.14 {
			stStatus = "urgent_replenishment"
			stStatusAr = "سحب عالي / أولوية توريد"
		} else if stockRatio > 0.38 {
			stStatus = "overstock"
			stStatusAr = "تكدس مخزني - تهدئة توريد"
		}

		pShare := 0.0
		if st.histRev > 0 {
			pShare = math.Round((st.promoRev/st.histRev)*1000) / 10
		}

		chainSKUTotals = append(chainSKUTotals, domain.TargetSKUBreakdown{
			ItemCode:                 st.itemCode,
			Barcode:                  st.barcode,
			UnitsPerCarton:           upc,
			DepartmentAr:             st.departmentAr,
			OfficialCartonExclVATEGP: round2(st.officialCartonExclVAT),
			OfficialCartonInclVATEGP: round2(st.officialCartonInclVAT),
			TargetPieces:             int(math.Round(sTargetUnits * float64(upc))),
			ActualPieces:             int(math.Round(st.actCases * float64(upc))),
			SKUName:                  st.name,
			Brand:                    st.brand,
			Sector:                   st.sector,
			SubCategory:              st.subCat,
			SharePct:                 math.Round(revShare*10000) / 100,
			CasePriceEGP:             round2(casePrice),
			TargetRevenueEGP:         sTargetRev,
			TargetUnits:              sTargetUnits,
			TargetWeightTons:         sTargetTons,
			ActualRevenueEGP:         round2(st.actRev),
			ActualUnits:              round2(st.actCases),
			ActualWeightTons:         round2(st.actTons),
			ExpectedRevenueEGP:       round2(st.expRev),
			ExpectedUnits:            round2(st.expCases),
			VarianceRevenueEGP:       round2(st.actRev - sTargetRev),
			VarianceUnits:            round2(st.actCases - sTargetUnits),
			AchievementPct:           achPct,
			RemainingStockCases:      remStock,
			StockStatus:              stStatus,
			StockStatusAr:            stStatusAr,
			PromoSharePct:            pShare,
		})
	}

	// 4. Build Brand & Sector Breakdown (Brands []domain.TargetBrandBreakdown)
	type brandAgg struct {
		brand     string
		sector    string
		skusCount int
		tRev      float64
		tUnits    float64
		tTons     float64
		aRev      float64
		aUnits    float64
		eRev      float64
	}
	brandAggMap := make(map[string]*brandAgg)
	for _, s := range chainSKUTotals {
		key := s.Sector + "|" + s.Brand
		ba, ok := brandAggMap[key]
		if !ok {
			ba = &brandAgg{brand: s.Brand, sector: s.Sector}
			brandAggMap[key] = ba
		}
		ba.skusCount++
		ba.tRev += s.TargetRevenueEGP
		ba.tUnits += s.TargetUnits
		ba.tTons += s.TargetWeightTons
		ba.aRev += s.ActualRevenueEGP
		ba.aUnits += s.ActualUnits
		ba.eRev += s.ExpectedRevenueEGP
	}
	brandsBreakdown := make([]domain.TargetBrandBreakdown, 0, len(brandAggMap))
	for _, ba := range brandAggMap {
		secAr := "قطاع المنظفات والعناية المنزلية (MT)"
		if strings.EqualFold(ba.sector, "CC") {
			secAr = "قطاع العناية بالسيارات - رابيدو (CC)"
		}
		shPct := 0.0
		if targetRev > 0 {
			shPct = math.Round((ba.tRev/targetRev)*1000) / 10
		}
		ach := 0.0
		if ba.tRev > 0 {
			ach = math.Round((ba.aRev/ba.tRev)*1000) / 10
		}
		brandsBreakdown = append(brandsBreakdown, domain.TargetBrandBreakdown{
			Brand:              ba.brand,
			Sector:             ba.sector,
			SectorNameAr:       secAr,
			SharePct:           shPct,
			ActiveSKUsCount:    ba.skusCount,
			TargetRevenueEGP:   round2(ba.tRev),
			TargetUnits:        round2(ba.tUnits),
			TargetWeightTons:   round2(ba.tTons),
			ActualRevenueEGP:   round2(ba.aRev),
			ActualUnits:        round2(ba.aUnits),
			ExpectedRevenueEGP: round2(ba.eRev),
			VarianceRevenueEGP: round2(ba.aRev - ba.tRev),
			VarianceUnits:      round2(ba.aUnits - ba.tUnits),
			AchievementPct:     ach,
		})
	}
	sort.Slice(brandsBreakdown, func(i, j int) bool {
		return brandsBreakdown[i].TargetRevenueEGP > brandsBreakdown[j].TargetRevenueEGP
	})

	// 5. Build Level 2 (Branches inside the Chain) & Level 3 (SKUs inside each Branch)
	effectiveChain := ch
	if effectiveChain == "" {
		effectiveChain = "fathalla"
	}
	branchTemplates := defaultChainBranchCatalog(effectiveChain)
	// Override BaseWeight with actual Sell-Out branch revenue when available in c.records
	for i := range branchTemplates {
		if realStoreRev, ok := sellOutStoreRev[branchTemplates[i].Name]; ok && realStoreRev > 0 {
			branchTemplates[i].BaseWeight = realStoreRev
			continue
		}
		shortName := strings.TrimSpace(strings.TrimPrefix(branchTemplates[i].Name, "فرع فتح الله -"))
		for storeName, rev := range sellOutStoreRev {
			if rev > 0 && shortName != "" && strings.Contains(storeName, shortName) {
				branchTemplates[i].BaseWeight = rev
				break
			}
		}
	}

	// Filter branches if the target was created for a specific branch/region
	var activeBranches []chainBranchTemplate
	var totalBranchWeight float64
	for _, bt := range branchTemplates {
		if brFilter != "" &&
			!strings.Contains(strings.ToLower(bt.Name), brFilter) &&
			!strings.Contains(strings.ToLower(bt.Code), brFilter) &&
			!strings.Contains(strings.ToLower(bt.Governorate), brFilter) &&
			!strings.EqualFold(bt.RegionCode, brFilter) {
			continue
		}
		activeBranches = append(activeBranches, bt)
		totalBranchWeight += bt.BaseWeight
	}
	if len(activeBranches) == 0 {
		activeBranches = branchTemplates
		for _, bt := range activeBranches {
			totalBranchWeight += bt.BaseWeight
		}
	}

	branchesBreakdown := make([]domain.TargetBranchBreakdown, 0, len(activeBranches))
	var allocBranchRev, allocBranchUnits, allocBranchTons float64

	for bIdx, bt := range activeBranches {
		bShare := 1.0 / float64(len(activeBranches))
		if totalBranchWeight > 0 {
			bShare = bt.BaseWeight / totalBranchWeight
		}

		bTargetRev := round2(targetRev * bShare)
		bTargetUnits := round2(targetUnits * bShare)
		bTargetTons := round2(targetTons * bShare)
		if bIdx == len(activeBranches)-1 && len(activeBranches) > 0 {
			if targetRev > 0 {
				bTargetRev = round2(math.Max(0, targetRev-allocBranchRev))
			}
			if targetUnits > 0 {
				bTargetUnits = round2(math.Max(0, targetUnits-allocBranchUnits))
			}
			if targetTons > 0 {
				bTargetTons = round2(math.Max(0, targetTons-allocBranchTons))
			}
		}
		allocBranchRev += bTargetRev
		allocBranchUnits += bTargetUnits
		allocBranchTons += bTargetTons

		bActualRev := round2(actualRev * bShare)
		bActualUnits := round2(actualUnits * bShare)
		bActualTons := round2(actualTons * bShare)
		bExpRev := round2(expRev * bShare)
		bExpUnits := round2(expUnits * bShare)

		bAchRevPct := 0.0
		if bTargetRev > 0 {
			bAchRevPct = math.Round((bActualRev/bTargetRev)*1000) / 10
		}
		bAchUnitsPct := 0.0
		if bTargetUnits > 0 {
			bAchUnitsPct = math.Round((bActualUnits/bTargetUnits)*1000) / 10
		}
		bStatus, bStatusAr := classifyTargetStatus(bAchRevPct)

		// Build Level 3: SKUs inside this Branch!
		// Every SKU's share inside this branch is weighted by its regional affinity (st.byRegionRev[bt.RegionCode]) + chain share
		branchSKUs := make([]domain.TargetSKUBreakdown, 0, len(chainSKUTotals))
		var allocBSkuRev, allocBSkuUnits float64
		for sIdx, chainSku := range chainSKUTotals {
			skuShare := chainSku.SharePct / 100.0
			bsTargetRev := round2(bTargetRev * skuShare)
			bsTargetUnits := round2(bTargetUnits * skuShare)
			if sIdx == len(chainSKUTotals)-1 && len(chainSKUTotals) > 0 {
				if bTargetRev > 0 {
					bsTargetRev = round2(math.Max(0, bTargetRev-allocBSkuRev))
				}
				if bTargetUnits > 0 {
					bsTargetUnits = round2(math.Max(0, bTargetUnits-allocBSkuUnits))
				}
			}
			allocBSkuRev += bsTargetRev
			allocBSkuUnits += bsTargetUnits

			bsTargetTons := round2(chainSku.TargetWeightTons * bShare)
			bsActualRev := round2(chainSku.ActualRevenueEGP * bShare)
			bsActualUnits := round2(chainSku.ActualUnits * bShare)
			bsActualTons := round2(chainSku.ActualWeightTons * bShare)
			bsExpRev := round2(chainSku.ExpectedRevenueEGP * bShare)
			bsExpUnits := round2(chainSku.ExpectedUnits * bShare)
			bsRemStock := round2(chainSku.RemainingStockCases * bShare)

			bsAch := 0.0
			if bsTargetRev > 0 {
				bsAch = math.Round((bsActualRev/bsTargetRev)*1000) / 10
			}
			upc := chainSku.UnitsPerCarton
			if upc <= 0 {
				upc = 12
			}

			branchSKUs = append(branchSKUs, domain.TargetSKUBreakdown{
				ItemCode:                 chainSku.ItemCode,
				Barcode:                  chainSku.Barcode,
				UnitsPerCarton:           upc,
				DepartmentAr:             chainSku.DepartmentAr,
				OfficialCartonExclVATEGP: chainSku.OfficialCartonExclVATEGP,
				OfficialCartonInclVATEGP: chainSku.OfficialCartonInclVATEGP,
				TargetPieces:             int(math.Round(bsTargetUnits * float64(upc))),
				ActualPieces:             int(math.Round(bsActualUnits * float64(upc))),
				SKUName:                  chainSku.SKUName,
				Brand:                    chainSku.Brand,
				Sector:                   chainSku.Sector,
				SubCategory:              chainSku.SubCategory,
				SharePct:                 chainSku.SharePct,
				CasePriceEGP:             chainSku.CasePriceEGP,
				TargetRevenueEGP:         bsTargetRev,
				TargetUnits:              bsTargetUnits,
				TargetWeightTons:         bsTargetTons,
				ActualRevenueEGP:         bsActualRev,
				ActualUnits:              bsActualUnits,
				ActualWeightTons:         bsActualTons,
				ExpectedRevenueEGP:       bsExpRev,
				ExpectedUnits:            bsExpUnits,
				VarianceRevenueEGP:       round2(bsActualRev - bsTargetRev),
				VarianceUnits:            round2(bsActualUnits - bsTargetUnits),
				AchievementPct:           bsAch,
				RemainingStockCases:      bsRemStock,
				StockStatus:              chainSku.StockStatus,
				StockStatusAr:            chainSku.StockStatusAr,
				PromoSharePct:            chainSku.PromoSharePct,
			})
		}

		branchesBreakdown = append(branchesBreakdown, domain.TargetBranchBreakdown{
			BranchCode:          bt.Code,
			BranchName:          bt.Name,
			RegionCode:          bt.RegionCode,
			Governorate:         bt.Governorate,
			SalesRep:            bt.SalesRep,
			KAOfficer:           bt.KAOfficer,
			ShareOfChainPct:     math.Round(bShare*10000) / 100,
			ActiveSKUsCount:     len(branchSKUs),
			TargetRevenueEGP:    bTargetRev,
			TargetUnits:         bTargetUnits,
			TargetWeightTons:    bTargetTons,
			GrossTargetUnits:    round2(bTargetUnits * grossMultiplier),
			ActualRevenueEGP:    bActualRev,
			ActualUnits:         bActualUnits,
			ActualWeightTons:    bActualTons,
			ExpectedRevenueEGP:  bExpRev,
			ExpectedUnits:       bExpUnits,
			VarianceRevenueEGP:  round2(bActualRev - bTargetRev),
			VarianceUnits:       round2(bActualUnits - bTargetUnits),
			AchievementRevPct:   bAchRevPct,
			AchievementUnitsPct: bAchUnitsPct,
			Status:              bStatus,
			StatusAr:            bStatusAr,
			SKUs:                branchSKUs,
		})
	}

	// 6. Build Automatic Sales Rep Quotas rolled up from their assigned branches
	type repRollup struct {
		rep       string
		kaOfficer string
		region    string
		gov       string
		branches  int
		tRev      float64
		tUnits    float64
		tTons     float64
		aRev      float64
		aUnits    float64
		eRev      float64
	}
	repRollupMap := make(map[string]*repRollup)
	for _, b := range branchesBreakdown {
		rr, ok := repRollupMap[b.SalesRep]
		if !ok {
			rr = &repRollup{
				rep:       b.SalesRep,
				kaOfficer: b.KAOfficer,
				region:    b.RegionCode,
				gov:       b.Governorate,
			}
			repRollupMap[b.SalesRep] = rr
		}
		rr.branches++
		rr.tRev += b.TargetRevenueEGP
		rr.tUnits += b.TargetUnits
		rr.tTons += b.TargetWeightTons
		rr.aRev += b.ActualRevenueEGP
		rr.aUnits += b.ActualUnits
		rr.eRev += b.ExpectedRevenueEGP
	}
	repQuotas := make([]domain.TargetSalesRepQuota, 0, len(repRollupMap))
	for _, rr := range repRollupMap {
		sh := 0.0
		if targetRev > 0 {
			sh = math.Round((rr.tRev/targetRev)*1000) / 10
		}
		ach := 0.0
		if rr.tRev > 0 {
			ach = math.Round((rr.aRev/rr.tRev)*1000) / 10
		}
		repQuotas = append(repQuotas, domain.TargetSalesRepQuota{
			SalesRep:           rr.rep,
			KAOfficer:          rr.kaOfficer,
			SalesManager:       "ملاك مجدى عزيز عبده",
			RegionCode:         rr.region,
			Governorate:        rr.gov,
			BranchesCount:      rr.branches,
			ActiveSKUsCount:    len(chainSKUTotals),
			SharePct:           sh,
			TargetRevenueEGP:   round2(rr.tRev),
			TargetUnits:        round2(rr.tUnits),
			TargetWeightTons:   round2(rr.tTons),
			ActualRevenueEGP:   round2(rr.aRev),
			ActualUnits:        round2(rr.aUnits),
			ExpectedRevenueEGP: round2(rr.eRev),
			VarianceRevenueEGP: round2(rr.aRev - rr.tRev),
			AchievementPct:     ach,
			MTTargetRevenueEGP: round2(rr.tRev * mtShare),
			CCTargetRevenueEGP: round2(rr.tRev * (1.0 - mtShare)),
		})
	}
	sort.Slice(repQuotas, func(i, j int) bool {
		return repQuotas[i].TargetRevenueEGP > repQuotas[j].TargetRevenueEGP
	})

	// 7. Build 12-Month Seasonality Phasing (التوزيع الشهري للمستهدف السنوي)
	monthRevHist := make(map[int]float64)
	monthActRev := make(map[int]float64)
	monthActUnits := make(map[int]float64)
	monthExpRev := make(map[int]float64)
	for _, r := range weightRecs {
		if r.MonthNum >= 1 && r.MonthNum <= 12 && r.NetValueEGP > 0 {
			monthRevHist[r.MonthNum] += r.NetValueEGP
		}
	}
	for _, r := range periodRecs {
		if r.MonthNum >= 1 && r.MonthNum <= 12 {
			monthActRev[r.MonthNum] += r.NetValueEGP
			monthActUnits[r.MonthNum] += r.NetQtyCases
			monthExpRev[r.MonthNum] += r.ExpectedValueEGP
		}
	}
	// Default FMCG Egyptian seasonality curve if some months in the year haven't happened yet
	defaultSeasonality := map[int]float64{
		1: 0.078, 2: 0.082, 3: 0.098, 4: 0.085,
		5: 0.080, 6: 0.086, 7: 0.090, 8: 0.088,
		9: 0.082, 10: 0.079, 11: 0.075, 12: 0.077,
	}
	monthArNames := []string{"يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"}
	monthEnNames := []string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

	var monthlyPhasing []domain.TargetMonthBreakdown
	if t.Month == 0 {
		for m := 1; m <= 12; m++ {
			sh := defaultSeasonality[m]
			mTargetRev := round2(targetRev * sh)
			mTargetUnits := round2(targetUnits * sh)
			mTargetTons := round2(targetTons * sh)
			mActRev := round2(monthActRev[m])
			mActUnits := round2(monthActUnits[m])
			mExp := round2(monthExpRev[m])
			mAch := 0.0
			if mTargetRev > 0 {
				mAch = math.Round((mActRev/mTargetRev)*1000) / 10
			}
			monthlyPhasing = append(monthlyPhasing, domain.TargetMonthBreakdown{
				Year:                t.Year,
				Month:               m,
				MonthLabelAr:        fmt.Sprintf("%s %d", monthArNames[m-1], t.Year),
				MonthLabelEn:        fmt.Sprintf("%s %d", monthEnNames[m-1], t.Year),
				SeasonalitySharePct: math.Round(sh*1000) / 10,
				TargetRevenueEGP:    mTargetRev,
				TargetUnits:         mTargetUnits,
				TargetWeightTons:    mTargetTons,
				ActualRevenueEGP:    mActRev,
				ActualUnits:         mActUnits,
				ExpectedRevenueEGP:  mExp,
				VarianceRevenueEGP:  round2(mActRev - mTargetRev),
				AchievementPct:      mAch,
			})
		}
	} else if t.Month >= 1 && t.Month <= 12 {
		m := t.Month
		mAch := 0.0
		if targetRev > 0 {
			mAch = math.Round((actualRev/targetRev)*1000) / 10
		}
		monthlyPhasing = append(monthlyPhasing, domain.TargetMonthBreakdown{
			Year:                t.Year,
			Month:               m,
			MonthLabelAr:        fmt.Sprintf("%s %d", monthArNames[m-1], t.Year),
			MonthLabelEn:        fmt.Sprintf("%s %d", monthEnNames[m-1], t.Year),
			SeasonalitySharePct: 100.0,
			TargetRevenueEGP:    round2(targetRev),
			TargetUnits:         round2(targetUnits),
			TargetWeightTons:    round2(targetTons),
			ActualRevenueEGP:    round2(actualRev),
			ActualUnits:         round2(actualUnits),
			ExpectedRevenueEGP:  round2(expRev),
			VarianceRevenueEGP:  round2(actualRev - targetRev),
			AchievementPct:      mAch,
		})
	}

	varianceRev := round2(actualRev - targetRev)
	varianceUnits := round2(actualUnits - targetUnits)
	achRevPct := 0.0
	if targetRev > 0 {
		achRevPct = math.Round((actualRev/targetRev)*1000) / 10
	}
	achUnitsPct := 0.0
	if targetUnits > 0 {
		achUnitsPct = math.Round((actualUnits/targetUnits)*1000) / 10
	}
	expAchPct := 0.0
	if targetRev > 0 {
		expAchPct = math.Round((expRev/targetRev)*1000) / 10
	}
	checkPct := achRevPct
	if targetRev <= 0 && targetUnits > 0 {
		checkPct = achUnitsPct
	}
	status, statusAr := classifyTargetStatus(checkPct)

	return domain.TargetComparisonItem{
		ID:                      t.ID,
		TenantID:                normTenant,
		TargetType:              t.TargetType,
		RetailerChain:           t.RetailerChain,
		ChainDisplayName:        chainDisp,
		Year:                    t.Year,
		Month:                   t.Month,
		MonthLabel:              formatTargetMonthLabel(t.Year, t.Month),
		BranchName:              t.BranchName,
		Category:                t.Category,
		TargetRevenueEGP:        round2(targetRev),
		ActualRevenueEGP:        round2(actualRev),
		VarianceRevenueEGP:      varianceRev,
		AchievementRevPct:       achRevPct,
		TargetUnits:             round2(targetUnits),
		ActualUnits:             round2(actualUnits),
		VarianceUnits:           varianceUnits,
		AchievementUnitsPct:     achUnitsPct,
		TargetWeightTons:        targetTons,
		ActualWeightTons:        round2(actualTons),
		ExpectedRevenueEGP:      round2(expRev),
		ExpectedUnits:           round2(expUnits),
		ExpectedAchievementPct:  expAchPct,
		AvgCasePriceEGP:         round2(avgCasePrice),
		HistoricalReturnRatePct: returnRatePct,
		GrossTargetRevenueEGP:   grossTargetRev,
		GrossTargetUnits:        grossTargetUnits,
		PromoSharePct:           promoSharePct,
		PromoTargetRevenueEGP:   promoTargetRev,
		RegularTargetRevenueEGP: regTargetRev,
		MTTargetRevenueEGP:      mtTargetRev,
		CCTargetRevenueEGP:      ccTargetRev,
		BranchesCount:           len(branchesBreakdown),
		ActiveSKUsCount:         len(chainSKUTotals),
		HasActuals:              len(periodRecs) > 0,
		Status:                  status,
		StatusAr:                statusAr,
		Notes:                   t.Notes,
		UpdatedAt:               t.UpdatedAt,
		Branches:                branchesBreakdown,
		ChainSKUTotals:          chainSKUTotals,
		Brands:                  brandsBreakdown,
		SalesRepQuotas:          repQuotas,
		MonthlyPhasing:          monthlyPhasing,
	}
}

// computeActualForTargetLocked returns the actual revenue, units and the number of matching rows
// (rows == 0 means the target period has no data in scope, e.g. a future year).
func (c *Client) computeActualForTargetLocked(normTenant string, t domain.TargetRecord) (float64, float64, int) {
	ch := strings.ToLower(strings.TrimSpace(t.RetailerChain))
	if ch == "all" || ch == "الكل" {
		ch = ""
	}
	br := strings.ToLower(strings.TrimSpace(t.BranchName))
	if br == "all" || br == "كل الفروع" {
		br = ""
	}
	cat := strings.ToLower(strings.TrimSpace(t.Category))
	if cat == "all" || cat == "كل الفئات" {
		cat = ""
	}

	if t.TargetType == "sell_in" {
		var rev, cases float64
		var matched int
		for _, r := range c.sellInRecords[normTenant] {
			rChain := strings.ToLower(strings.TrimSpace(r.RetailerChain))
			if rChain == "" {
				rChain = "fathalla"
			}
			if ch != "" && !strings.EqualFold(rChain, ch) {
				continue
			}
			if t.Year > 0 && r.Year != t.Year {
				continue
			}
			if t.Month > 0 && r.MonthNum != t.Month {
				continue
			}
			if br != "" &&
				!strings.Contains(strings.ToLower(r.CustomerName), br) &&
				!strings.Contains(strings.ToLower(r.Governorate), br) &&
				!strings.EqualFold(r.RegionCode, br) {
				continue
			}
			if cat != "" &&
				!strings.Contains(strings.ToLower(r.Brand), cat) &&
				!strings.Contains(strings.ToLower(r.SubCategory), cat) &&
				!strings.Contains(strings.ToLower(r.Sector), cat) {
				continue
			}
			rev += r.NetValueEGP
			cases += r.NetQtyCases
			matched++
		}
		return rev, cases, matched
	}

	// Default: "sell_out"
	var rev float64
	var units, matched int
	yrPrefix := fmt.Sprintf("%04d-", t.Year)
	ymPrefix := fmt.Sprintf("%04d-%02d", t.Year, t.Month)

	for _, r := range c.records {
		if !matchTenant(r.TenantID, normTenant) || !isOwnRecord(r) {
			continue
		}
		if ch != "" && !strings.EqualFold(r.RetailerChain, ch) {
			continue
		}
		if t.Year > 0 {
			if t.Month > 0 {
				if !strings.HasPrefix(r.TransactionDate, ymPrefix) {
					continue
				}
			} else if !strings.HasPrefix(r.TransactionDate, yrPrefix) {
				continue
			}
		}
		if br != "" &&
			!strings.Contains(strings.ToLower(r.StoreName), br) &&
			!strings.Contains(strings.ToLower(r.StoreID), br) {
			continue
		}
		if cat != "" {
			normCat := strings.ToLower(domain.NormalizeProductCategory(r.Category))
			if !strings.Contains(normCat, cat) && !strings.Contains(strings.ToLower(r.Category), cat) && !strings.Contains(strings.ToLower(r.SKUName), cat) {
				continue
			}
		}
		rev += r.NetRevenue
		units += r.QuantitySold
		matched++
	}
	return rev, float64(units), matched
}

// EnrichSellInRecords applies the in-memory Sell-In enrichment (chain resolver, product master prices,
// pieces->cases fix) to rows read elsewhere, e.g. a BigQuery page, exactly as GetSellInRecords does.
func (c *Client) EnrichSellInRecords(tenantID string, recs []domain.SellInRecord) []domain.SellInRecord {
	c.mu.RLock()
	defer c.mu.RUnlock()
	normTenant := normalizeTenantKey(tenantID)
	out := make([]domain.SellInRecord, len(recs))
	for i, r := range recs {
		if r.TenantID == "" {
			r.TenantID = normTenant
		}
		c.enrichSellInRecordLocked(&r)
		if strings.TrimSpace(r.RetailerChain) == "" {
			r.RetailerChain = "fathalla"
		}
		out[i] = r
	}
	return out
}

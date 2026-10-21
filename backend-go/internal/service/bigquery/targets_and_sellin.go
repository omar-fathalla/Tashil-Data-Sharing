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
			matchItem := strings.Contains(strings.ToLower(r.ItemName), qLower)
			matchBrand := strings.Contains(strings.ToLower(r.Brand), qLower)
			matchCustomer := strings.Contains(strings.ToLower(r.CustomerName), qLower)
			matchRep := strings.Contains(strings.ToLower(r.SalesRep), qLower)
			matchGov := strings.Contains(strings.ToLower(r.Governorate), qLower)
			matchCat := strings.Contains(strings.ToLower(r.SubCategory), qLower)
			if !matchItem && !matchBrand && !matchCustomer && !matchRep && !matchGov && !matchCat {
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

// UpsertTarget creates or updates a Sell-Out or Sell-In target for a tenant and persists it to disk.
func (c *Client) UpsertTarget(ctx context.Context, tenantID string, target domain.TargetRecord) (*domain.TargetRecord, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

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
		target.Year = 2025
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

// GetTargetsSummary returns all targets for a tenant & targetType ("sell_out" or "sell_in") compared against real Actual data.
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

		actualRev, actualUnits := c.computeActualForTargetLocked(normTenant, t)
		varianceRev := math.Round((actualRev-t.TargetRevenueEGP)*100) / 100
		varianceUnits := math.Round((actualUnits-t.TargetUnits)*100) / 100

		achRevPct := 0.0
		if t.TargetRevenueEGP > 0 {
			achRevPct = math.Round((actualRev/t.TargetRevenueEGP)*1000) / 10
		}
		achUnitsPct := 0.0
		if t.TargetUnits > 0 {
			achUnitsPct = math.Round((actualUnits/t.TargetUnits)*1000) / 10
		}

		status := "at_risk"
		statusAr := "أقل من المستهدف"
		checkPct := achRevPct
		if t.TargetRevenueEGP <= 0 && t.TargetUnits > 0 {
			checkPct = achUnitsPct
		}
		if checkPct >= 100.0 {
			status = "exceeded"
			statusAr = "تجاوز المستهدف"
		} else if checkPct >= 85.0 {
			status = "on_track"
			statusAr = "قيد التحقيق الجيد"
		}

		chainDisp := t.ChainDisplayName
		if chainDisp == "" {
			if t.RetailerChain == "all" {
				chainDisp = "كل السلاسل (All Chains)"
			} else {
				chainDisp = getRetailChainDisplayName(t.RetailerChain)
			}
		}

		items = append(items, domain.TargetComparisonItem{
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
			TargetRevenueEGP:    math.Round(t.TargetRevenueEGP*100) / 100,
			ActualRevenueEGP:    math.Round(actualRev*100) / 100,
			VarianceRevenueEGP:  varianceRev,
			AchievementRevPct:   achRevPct,
			TargetUnits:         math.Round(t.TargetUnits*100) / 100,
			ActualUnits:         math.Round(actualUnits*100) / 100,
			VarianceUnits:       varianceUnits,
			AchievementUnitsPct: achUnitsPct,
			Status:              status,
			StatusAr:            statusAr,
			Notes:               t.Notes,
			UpdatedAt:           t.UpdatedAt,
		})

		totalTargetRev += t.TargetRevenueEGP
		totalActualRev += actualRev
		totalTargetUnits += t.TargetUnits
		totalActualUnits += actualUnits
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

	overallAch := 0.0
	if totalTargetRev > 0 {
		overallAch = math.Round((totalActualRev/totalTargetRev)*1000) / 10
	} else if totalTargetUnits > 0 {
		overallAch = math.Round((totalActualUnits/totalTargetUnits)*1000) / 10
	}

	return &domain.TargetsSummaryResponse{
		TenantID:              normTenant,
		TargetType:            tType,
		TotalTargetRevenueEGP: math.Round(totalTargetRev*100) / 100,
		TotalActualRevenueEGP: math.Round(totalActualRev*100) / 100,
		TotalVarianceEGP:      math.Round((totalActualRev-totalTargetRev)*100) / 100,
		OverallAchievementPct: overallAch,
		TotalTargetUnits:      math.Round(totalTargetUnits*100) / 100,
		TotalActualUnits:      math.Round(totalActualUnits*100) / 100,
		Items:                 items,
	}, nil
}

func (c *Client) computeActualForTargetLocked(normTenant string, t domain.TargetRecord) (float64, float64) {
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
		}
		return rev, cases
	}

	// Default: "sell_out"
	var rev float64
	var units int
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
	}
	return rev, float64(units)
}

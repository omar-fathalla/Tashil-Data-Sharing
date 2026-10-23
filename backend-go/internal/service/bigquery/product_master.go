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
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// ProductMasterFilter allows filtering the Product Master & Price List catalog by prefix, brand, item type, packaging, pull status, and search query.
type ProductMasterFilter struct {
	Prefix        string
	Brand         string
	ItemType      string // "all", "عادي", "عرض"
	PackagingType string
	PullStatus    string // "all", "active", "unpulled"
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
		tenantKey := strings.TrimSuffix(entry.Name(), ".json")
		normTenant := normalizeTenantKey(tenantKey)
		c.mu.Lock()
		c.indexProductMasterLocked(normTenant, &summary)
		c.enrichAllTenantDataLocked(normTenant)
		c.mu.Unlock()
	}
}

func (c *Client) persistTenantProductMasterLocked(normTenant string) {
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
	c.productMaster[normTenant] = rebuilt

	byCode := make(map[string]domain.ProductMasterItem, len(rebuilt.Items))
	byBarcode := make(map[string]domain.ProductMasterItem, len(rebuilt.Items))
	byName := make(map[string]domain.ProductMasterItem, len(rebuilt.Items))

	for _, it := range rebuilt.Items {
		code := domain.NormalizeItemCode(it.ItemCode)
		if code != "" {
			byCode[code] = it
		}
		bc := strings.TrimSpace(it.Barcode)
		if bc != "" {
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

	c.productMasterByCode[normTenant] = byCode
	c.productMasterByBarcode[normTenant] = byBarcode
	c.productMasterByName[normTenant] = byName
}

// LookupProductMaster resolves an item from the tenant's Product Master catalog by ItemCode, Barcode, or SKUName.
func (c *Client) LookupProductMaster(tenantID, itemCode, barcode, skuName string) (domain.ProductMasterItem, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.lookupProductMasterLocked(tenantID, itemCode, barcode, skuName)
}

func (c *Client) lookupProductMasterLocked(tenantID, itemCode, barcode, skuName string) (domain.ProductMasterItem, bool) {
	normTenant := normalizeTenantKey(tenantID)
	byCode := c.productMasterByCode[normTenant]
	byBarcode := c.productMasterByBarcode[normTenant]
	byName := c.productMasterByName[normTenant]

	if code := domain.NormalizeItemCode(itemCode); code != "" && byCode != nil {
		if it, ok := byCode[code]; ok {
			return it, true
		}
	}
	if bc := domain.CleanBarcode(barcode); bc != "" && byBarcode != nil {
		if it, ok := byBarcode[bc]; ok {
			return it, true
		}
	}
	if nameKey := normalizeArabicNameForLookup(skuName); nameKey != "" && byName != nil {
		if it, ok := byName[nameKey]; ok {
			return it, true
		}
		// Partial token match for Sell-In / Retailer SKU names
		for k, it := range byName {
			if len(nameKey) >= 8 && (strings.Contains(nameKey, k) || strings.Contains(k, nameKey)) {
				return it, true
			}
		}
	}
	return domain.ProductMasterItem{}, false
}

func (c *Client) enrichSellOutFactLocked(r *domain.SellOutFact) {
	lookupName := r.SKUName
	if r.RetailerRawSKUName != "" && r.ItemCode == "" {
		lookupName = r.RetailerRawSKUName
	}
	if pm, ok := c.lookupProductMasterLocked(r.TenantID, r.ItemCode, r.Barcode, lookupName); ok {
		r.ItemCode = pm.ItemCode
		if pm.Barcode != "" {
			r.Barcode = pm.Barcode
		}
		if r.RetailerRawSKUName == "" && r.SKUName != "" && r.SKUName != pm.OfficialName {
			r.RetailerRawSKUName = r.SKUName
		}
		if pm.OfficialName != "" {
			r.SKUName = pm.OfficialName
		}
		r.UnitsPerCarton = pm.UnitsPerCarton
		r.ItemType = pm.ItemType
		r.FactoryUnitCost = pm.NetUnitInvoiceCost
		if r.Category == "" || r.Category == "غير مصنف" {
			r.Category = pm.Category
		}
		if r.RecommendedPrice <= 0 && pm.UnitPriceInclVAT > 0 {
			r.RecommendedPrice = math.Round(pm.UnitPriceInclVAT*100) / 100
		}
	}
}

func (c *Client) enrichPricingItemLocked(item *domain.PricingComplianceItem) {
	tenantID := item.TenantID
	if tenantID == "" {
		tenantID = "tenant-adeco"
	}
	if pm, ok := c.lookupProductMasterLocked(tenantID, item.ItemCode, item.Barcode, item.SKUName); ok {
		item.ItemCode = pm.ItemCode
		if pm.Barcode != "" {
			item.Barcode = pm.Barcode
		}
		if pm.OfficialName != "" {
			item.SKUName = pm.OfficialName
		}
		item.UnitsPerCarton = pm.UnitsPerCarton
		item.ItemType = pm.ItemType
		item.FactoryUnitCost = pm.NetUnitInvoiceCost
		if item.ActualPrice > 0 && pm.NetUnitInvoiceCost > 0 {
			item.RetailerMarginPct = math.Round(((item.ActualPrice-pm.NetUnitInvoiceCost)/item.ActualPrice)*1000) / 10
		}
	}
}

func (c *Client) enrichSellInRecordLocked(r *domain.SellInRecord) {
	if pm, ok := c.lookupProductMasterLocked(r.TenantID, r.ItemCode, r.Barcode, r.ItemName); ok {
		r.ItemCode = pm.ItemCode
		if pm.Barcode != "" {
			r.Barcode = pm.Barcode
		}
		r.UnitsPerCarton = pm.UnitsPerCarton
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
		code := domain.NormalizeItemCode(r.ItemCode)
		if code == "" {
			if pm, ok := c.lookupProductMasterLocked(normTenant, r.ItemCode, r.Barcode, r.SKUName); ok {
				code = domain.NormalizeItemCode(pm.ItemCode)
			}
		}
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
		code := domain.NormalizeItemCode(sr.ItemCode)
		if code == "" {
			if pm, ok := c.lookupProductMasterLocked(normTenant, sr.ItemCode, sr.Barcode, sr.ItemName); ok {
				code = domain.NormalizeItemCode(pm.ItemCode)
			}
		}
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
		if searchQ != "" {
			if !domain.MatchesProductSearchQuery(searchQ, it.ItemCode, it.Barcode, it.OfficialName, it.DepartmentAr, it.Category, it.Brand) {
				continue
			}
		}
		filtered = append(filtered, it)
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
		AvailablePrefixes:   base.AvailablePrefixes,
		AvailableBrands:     base.AvailableBrands,
		AvailablePackaging:  base.AvailablePackaging,
		Items:               filtered,
	}, nil
}

// SetProductMaster replaces or merges the Product Master catalog for a tenant, persists it to disk, and retroactively enriches all tenant data.
func (c *Client) SetProductMaster(ctx context.Context, tenantID string, summary *domain.ProductMasterSummaryResponse) (*domain.ProductMasterSummaryResponse, error) {
	if summary == nil || len(summary.Items) == 0 {
		return nil, fmt.Errorf("empty product master summary")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidateKPICache()

	normTenant := normalizeTenantKey(tenantID)
	c.indexProductMasterLocked(normTenant, summary)
	c.persistTenantProductMasterLocked(normTenant)
	c.enrichAllTenantDataLocked(normTenant)

	return c.productMaster[normTenant], nil
}

// UpsertProductMasterItem updates or inserts a single ProductMasterItem in the tenant's catalog, recalculating derived VAT/discount prices.
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
	item.NetUnitInvoiceCost = math.Round(item.UnitPriceInclVAT*(1.0-item.InvoiceDiscountPct)*(1.0-item.ExtraDiscountPct)*1000) / 1000
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
			if item.SerialNo <= 0 {
				item.SerialNo = base.Items[i].SerialNo
			}
			base.Items[i] = item
			found = true
			break
		}
	}
	if !found {
		if item.SerialNo <= 0 {
			item.SerialNo = len(base.Items) + 1
		}
		base.Items = append(base.Items, item)
	}

	c.indexProductMasterLocked(normTenant, base)
	c.persistTenantProductMasterLocked(normTenant)
	c.enrichAllTenantDataLocked(normTenant)

	updated := c.productMasterByCode[normTenant][code]
	return &updated, nil
}

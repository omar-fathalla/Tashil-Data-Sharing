package bigquery

import (
	"context"
	"errors"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// Sell-In targets are never entered: they are derived on read from the Sell-Out targets.
//
//   - Quantity (pieces) is the primary metric: derived pieces = the Sell-Out target pieces, 1:1, for the
//     same chain / branch / SKU / period. Cases = pieces / pack size from the Product Master.
//   - Value is secondary: pieces x cost price from the Product Master (or the Sell-Out target's explicit
//     unit price when one is set).
//   - Achievement compares the actual Sell-In quantity first, then the actual Sell-In value.
//
// Legacy manually-entered sell_in records stay in the tenant JSON untouched but are ignored on read.

const (
	// DerivedSellInIDPrefix prefixes the id of a derived Sell-In target: derived_si_from_{sellOutTargetID}.
	DerivedSellInIDPrefix = "derived_si_from_"
	// NoBrandLabelAr groups items that have no brand in the Product Master.
	NoBrandLabelAr = "بدون براند"

	derivedExcludedSupersededByMonthly = "superseded_by_monthly"
	derivedUnallocatedSKUName          = "غير موزع على أصناف"
	derivedUnallocatedIdentity         = "unallocated"
)

// ErrSellInTargetsDerived is returned when a caller tries to create, upload or delete a Sell-In target.
var ErrSellInTargetsDerived = errors.New("sell-in targets are derived automatically from sell-out targets and cannot be created, uploaded or deleted")

// DerivedSellInTargetID returns the id of the Sell-In target derived from a Sell-Out target.
func DerivedSellInTargetID(sellOutTargetID string) string {
	return DerivedSellInIDPrefix + sellOutTargetID
}

// IsDerivedSellInTargetID reports whether id names a derived (read-only) Sell-In target.
func IsDerivedSellInTargetID(id string) bool {
	return strings.HasPrefix(strings.TrimSpace(id), DerivedSellInIDPrefix)
}

// DerivedBreakdownFunc returns the Sell-Out branch/SKU allocation of a target (for example from BigQuery).
// found=false makes the derivation fall back to the in-memory Sell-Out records.
type DerivedBreakdownFunc func(ctx context.Context, t domain.TargetRecord) (resp domain.TargetBreakdownResponse, found bool)

// DerivedSellInOptions scopes a derived Sell-In targets read.
type DerivedSellInOptions struct {
	Chain string
	Year  int
	// Brands is the multi-select brand filter (Product Master brand labels; NoBrandLabelAr for items
	// without a brand). Empty = every brand.
	Brands []string
	// Breakdown optionally supplies the Sell-Out allocation; nil = in-memory Sell-Out records.
	Breakdown DerivedBreakdownFunc
}

type derivedSKUInfo struct {
	itemCode    string
	barcode     string
	identity    string
	brand       string
	upc         int
	unitCost    float64
	costMissing bool
}

type derivedSellInRow struct {
	chain        string
	year, month  int
	pieces       float64
	cases        float64
	value        float64
	tons         float64
	brand        string
	identity     string
	name         string
	customerName string
	customerCode string
	governorate  string
	region       string
	sector       string
	subCat       string
	recBrand     string
	itemName     string
}

type derivedLeaf struct {
	branchKey, branchName string
	skuKey, skuName       string
	itemCode, barcode     string
	category              string
	info                  derivedSKUInfo
	pieces                int64
	unitCost              float64
	costMissing           bool
	unallocated           bool
}

type derivedTarget struct {
	t        domain.TargetRecord
	units    int64
	allocRev float64
	leaves   []derivedLeaf
	rows     []*derivedSellInRow
	excluded bool
	reason   string
}

func normalizeScopeLabel(v string, allLabels ...string) string {
	s := strings.ToLower(strings.TrimSpace(v))
	if s == "" || s == "all" || s == "الكل" {
		return ""
	}
	for _, l := range allLabels {
		if s == strings.ToLower(l) {
			return ""
		}
	}
	return s
}

func derivedChainKey(chain string) string {
	ch := strings.ToLower(strings.TrimSpace(chain))
	if ch == "all" || ch == "الكل" {
		return ""
	}
	return ch
}

// derivedScopeKey identifies the Sell-Out scope of a target apart from its month.
func derivedScopeKey(t domain.TargetRecord) string {
	ch := derivedChainKey(t.RetailerChain)
	if ch == "" {
		ch = "all"
	}
	br := normalizeScopeLabel(t.BranchName, "كل الفروع")
	cat := normalizeScopeLabel(t.Category, "كل الفئات")
	return ch + "|" + br + "|" + cat + "|" + strconv.Itoa(t.Year)
}

func derivedBrandSelected(brand string, selected []string) bool {
	if len(selected) == 0 {
		return true
	}
	for _, f := range selected {
		f = strings.TrimSpace(f)
		if f == "" {
			continue
		}
		if f == NoBrandLabelAr || brand == NoBrandLabelAr {
			if f == brand {
				return true
			}
			continue
		}
		if domain.BrandLabelMatches(brand, f) {
			return true
		}
	}
	return false
}

func derivedPct(num, den float64) float64 {
	if den <= 0 {
		return 0
	}
	return math.Round(num/den*1000) / 10
}

func floatPtr(v float64) *float64 {
	r := round2(v)
	return &r
}

// resolveDerivedSKUInfoLocked resolves brand, pack size and cost for one SKU from the Product Master.
func (c *Client) resolveDerivedSKUInfoLocked(normTenant, code, barcode, name string, cache map[string]derivedSKUInfo) derivedSKUInfo {
	ck := strings.ToLower(strings.TrimSpace(code)) + "|" + strings.TrimSpace(barcode) + "|" + strings.TrimSpace(name)
	if v, ok := cache[ck]; ok {
		return v
	}
	pm, ok := c.lookupProductMasterLocked(normTenant, code, barcode, name)
	info := derivedSKUInfo{brand: NoBrandLabelAr}
	if ok {
		info.identity = "pm:" + domain.NormalizeItemCode(pm.ItemCode)
		info.itemCode = pm.ItemCode
		info.barcode = pm.Barcode
		if b := strings.TrimSpace(pm.Brand); b != "" {
			info.brand = b
		}
		if pm.UnitsPerCarton > 0 {
			info.upc = pm.UnitsPerCarton
		}
	} else {
		raw := strings.TrimSpace(code)
		if raw == "" {
			raw = strings.TrimSpace(barcode)
		}
		if raw == "" {
			raw = strings.TrimSpace(name)
		}
		info.identity = "raw:" + strings.ToLower(raw)
	}
	cost, _, _ := resolveRealFactoryUnitCost(0, pm, ok)
	if cost > 0 {
		info.unitCost = cost
	} else {
		info.costMissing = true
	}
	cache[ck] = info
	return info
}

// derivedSellInRowsLocked loads the tenant's Sell-In records once per request as comparable rows.
func (c *Client) derivedSellInRowsLocked(normTenant string, cache map[string]derivedSKUInfo) []*derivedSellInRow {
	raw := c.sellInRecords[normTenant]
	rows := make([]*derivedSellInRow, 0, len(raw))
	for _, r := range raw {
		rec := r
		if rec.TenantID == "" {
			rec.TenantID = normTenant
		}
		if rec.ItemCode == "" || rec.TotalUnitsSupplied == 0 || rec.CanonicalFamilyKey == "" {
			c.enrichSellInRecordLocked(&rec)
		}
		chain := strings.ToLower(strings.TrimSpace(rec.RetailerChain))
		if chain == "" {
			chain = "fathalla"
		}
		info := c.resolveDerivedSKUInfoLocked(normTenant, rec.ItemCode, rec.Barcode, rec.ItemName, cache)
		upc := rec.UnitsPerCarton
		if upc <= 0 {
			upc = 12
		}
		rows = append(rows, &derivedSellInRow{
			chain:        chain,
			year:         rec.Year,
			month:        rec.MonthNum,
			pieces:       math.Round(rec.NetQtyCases * float64(upc)),
			cases:        rec.NetQtyCases,
			value:        rec.NetValueEGP,
			tons:         rec.WeightTons,
			brand:        info.brand,
			identity:     info.identity,
			name:         strings.TrimSpace(rec.ItemName),
			customerName: strings.ToLower(strings.TrimSpace(rec.CustomerName)),
			customerCode: strings.ToLower(strings.TrimSpace(rec.CustomerBranchCode)),
			governorate:  strings.ToLower(rec.Governorate),
			region:       strings.TrimSpace(rec.RegionCode),
			sector:       strings.ToLower(rec.Sector),
			subCat:       strings.ToLower(rec.SubCategory),
			recBrand:     strings.ToLower(rec.Brand),
			itemName:     strings.ToLower(rec.ItemName),
		})
	}
	return rows
}

// derivedRowInScope applies a Sell-Out target's chain / period / branch / category scope to a Sell-In row.
func derivedRowInScope(r *derivedSellInRow, t domain.TargetRecord, ch, br, cat string) bool {
	if ch != "" && !strings.EqualFold(r.chain, ch) {
		return false
	}
	if t.Year > 0 && r.year != t.Year {
		return false
	}
	if t.Month > 0 && r.month != t.Month {
		return false
	}
	if br != "" &&
		!strings.Contains(r.customerName, br) &&
		!strings.Contains(r.customerCode, br) &&
		!strings.Contains(r.governorate, br) &&
		!strings.EqualFold(r.region, br) {
		return false
	}
	if cat != "" &&
		!strings.Contains(r.recBrand, cat) &&
		!strings.Contains(r.subCat, cat) &&
		!strings.Contains(r.sector, cat) &&
		!strings.Contains(r.itemName, cat) {
		return false
	}
	return true
}

type derivedSKUAgg struct {
	identity, key, name, brand  string
	itemCode, barcode, category string
	upc                         int
	pieces                      int64
	value                       float64
	unitCost                    float64
	costMissing                 bool
	actualPieces                float64
	actualCases                 float64
	actualValue                 float64
	actualTons                  float64
}

type derivedBranchAgg struct {
	key, name    string
	pieces       int64
	cases        float64
	casesKnown   bool
	value        float64
	skus         map[string]*derivedSKUAgg
	skuOrder     []string
	actualPieces float64
	actualCases  float64
	actualValue  float64
	actualTons   float64
}

type derivedBrandAgg struct {
	brand        string
	skus         map[string]bool
	pieces       int64
	value        float64
	actualPieces float64
	actualValue  float64
}

// GetDerivedSellInTargetsSummary derives the Sell-In targets from the tenant's Sell-Out targets.
func (c *Client) GetDerivedSellInTargetsSummary(ctx context.Context, tenantID string, opts DerivedSellInOptions) (*domain.TargetsSummaryResponse, error) {
	normTenant := normalizeTenantKey(tenantID)
	chainFilter := derivedChainKey(opts.Chain)

	// Phase 1: snapshot the Sell-Out targets in scope (and every monthly scope, for de-duplication).
	c.mu.RLock()
	var all []domain.TargetRecord
	for _, t := range c.targets[normTenant] {
		if t.TargetType == "sell_in" {
			continue // legacy manual Sell-In targets are ignored on read, never deleted
		}
		all = append(all, t)
	}
	monthlyScopes := map[string]bool{}
	for _, t := range all {
		if t.Month >= 1 && t.Month <= 12 {
			monthlyScopes[derivedScopeKey(t)] = true
		}
	}
	var targets []*derivedTarget
	for _, t := range all {
		if chainFilter != "" && !strings.EqualFold(derivedChainKey(t.RetailerChain), chainFilter) && derivedChainKey(t.RetailerChain) != "" {
			continue
		}
		if opts.Year > 0 && t.Year != opts.Year {
			continue
		}
		dt := &derivedTarget{t: t}
		units := t.TargetUnits
		ch := derivedChainKey(t.RetailerChain)
		if units <= 0 && t.TargetRevenueEGP > 0 {
			if avg, _ := c.inferChainUnitPriceAndTonsLocked(normTenant, "sell_out", ch); avg > 0 {
				units = math.Round(t.TargetRevenueEGP / avg)
			}
		}
		dt.units = int64(math.Round(units))
		dt.allocRev = t.TargetRevenueEGP
		if dt.allocRev <= 0 && dt.units > 0 {
			if avg, _ := c.inferChainUnitPriceAndTonsLocked(normTenant, "sell_out", ch); avg > 0 {
				dt.allocRev = math.Round(float64(dt.units) * avg)
			}
		}
		// Avoid double counting: an annual target is superseded by monthly targets of the same scope.
		if t.Month == 0 && monthlyScopes[derivedScopeKey(t)] {
			dt.excluded = true
			dt.reason = derivedExcludedSupersededByMonthly
		}
		targets = append(targets, dt)
	}
	c.mu.RUnlock()

	// Phase 2: the Sell-Out branch/SKU allocation (takes its own locks; never nested inside ours).
	breakdowns := make([]domain.TargetBreakdownResponse, len(targets))
	for i, dt := range targets {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		work := dt.t
		work.TargetUnits = float64(dt.units)
		work.TargetRevenueEGP = dt.allocRev
		var resp domain.TargetBreakdownResponse
		found := false
		if opts.Breakdown != nil {
			resp, found = opts.Breakdown(ctx, work)
		}
		if !found {
			src := c.TargetBreakdownSource(normTenant, targetalloc.ChainFilter(work.RetailerChain))
			r, ok, err := targetalloc.ComputeFiltered(ctx, src, work, "memory", targetalloc.Filters{})
			if err == nil && ok {
				resp, found = r, true
			}
		}
		if found {
			breakdowns[i] = resp
		}
	}

	// Phase 3: leaves (SKU x branch pieces), Sell-In actuals, aggregation.
	c.mu.RLock()
	defer c.mu.RUnlock()

	infoCache := map[string]derivedSKUInfo{}
	sellInRows := c.derivedSellInRowsLocked(normTenant, infoCache)
	brandSet := map[string]bool{}

	for i, dt := range targets {
		dt.leaves = c.derivedLeavesLocked(normTenant, dt, breakdowns[i], infoCache)
		ch := derivedChainKey(dt.t.RetailerChain)
		br := normalizeScopeLabel(dt.t.BranchName, "كل الفروع")
		cat := normalizeScopeLabel(dt.t.Category, "كل الفئات")
		for _, r := range sellInRows {
			if derivedRowInScope(r, dt.t, ch, br, cat) {
				dt.rows = append(dt.rows, r)
				brandSet[r.brand] = true
			}
		}
		for _, l := range dt.leaves {
			brandSet[l.info.brand] = true
		}
	}

	sum := &domain.TargetsSummaryResponse{
		TenantID:            normTenant,
		TargetType:          "sell_in",
		Derived:             true,
		QuantityUnit:        "pieces",
		SellOutTargetsCount: len(targets),
		AvailableBrands:     sortedBrands(brandSet),
		AppliedBrands:       append([]string{}, opts.Brands...),
		Items:               []domain.TargetComparisonItem{},
	}

	var (
		totUnits, totActUnits, totRev, totActRev, totTons, totActTons float64
		compTU, compAU, compTR, compAR, noDataTR, noDataTU            float64
		totCases, totActCases                                         float64
		casesKnown                                                    bool
		compCount, noDataCount                                        int
	)
	branchSet := map[string]bool{}
	skuSet := map[string]bool{}
	packMissing := map[string]bool{}
	costMissing := map[string]bool{}

	for _, dt := range targets {
		item := c.buildDerivedItem(normTenant, dt, opts.Brands)
		if item == nil {
			continue
		}
		sum.Items = append(sum.Items, *item)
		if dt.excluded {
			sum.ExcludedFromTotalsCount++
			continue
		}
		totUnits += item.TargetUnits
		totActUnits += item.ActualUnits
		totRev += item.TargetRevenueEGP
		totActRev += item.ActualRevenueEGP
		totTons += item.TargetWeightTons
		totActTons += item.ActualWeightTons
		if item.TargetCases != nil {
			casesKnown = true
			totCases += *item.TargetCases
		}
		if item.ActualCases != nil {
			totActCases += *item.ActualCases
		}
		if item.HasActuals {
			compTU += item.TargetUnits
			compAU += item.ActualUnits
			compTR += item.TargetRevenueEGP
			compAR += item.ActualRevenueEGP
			compCount++
		} else {
			noDataCount++
			noDataTR += item.TargetRevenueEGP
			noDataTU += item.TargetUnits
		}
		for _, b := range item.Branches {
			branchSet[b.BranchName] = true
		}
		for _, s := range item.ChainSKUTotals {
			if s.TargetUnits > 0 {
				skuSet[s.SKUName] = true
			}
			if s.PackSizeMissing && s.TargetUnits > 0 {
				packMissing[s.ItemCode+"|"+s.SKUName] = true
			}
			if s.CostMissing && s.TargetUnits > 0 {
				costMissing[s.ItemCode+"|"+s.SKUName] = true
			}
		}
	}

	sort.SliceStable(sum.Items, func(i, j int) bool {
		a, b := sum.Items[i], sum.Items[j]
		if a.Year != b.Year {
			return a.Year > b.Year
		}
		if a.Month != b.Month {
			return a.Month < b.Month
		}
		if a.TargetUnits != b.TargetUnits {
			return a.TargetUnits > b.TargetUnits
		}
		return a.ID < b.ID
	})

	sum.TotalTargetUnits = round2(totUnits)
	sum.TotalActualUnits = round2(totActUnits)
	sum.TotalTargetRevenueEGP = round2(totRev)
	sum.TotalActualRevenueEGP = round2(totActRev)
	sum.TotalTargetWeightTons = round2(totTons)
	sum.TotalActualWeightTons = round2(totActTons)
	if casesKnown {
		sum.TotalTargetCases = floatPtr(totCases)
	}
	sum.ComparableTargetsCount = compCount
	if compCount > 0 {
		sum.TotalActualCases = floatPtr(totActCases)
	}
	sum.NoDataTargetsCount = noDataCount
	sum.NoDataTargetRevenueEGP = round2(noDataTR)
	sum.NoDataTargetUnits = round2(noDataTU)
	sum.ComparableTargetUnits = round2(compTU)
	sum.ComparableActualUnits = round2(compAU)
	sum.ComparableTargetRevenueEGP = round2(compTR)
	sum.ComparableActualRevenueEGP = round2(compAR)
	sum.TotalVarianceUnits = round2(compAU - compTU)
	sum.TotalVarianceEGP = round2(compAR - compTR)
	if compTU > 0 {
		sum.OverallAchievementPct = derivedPct(compAU, compTU)
	} else {
		sum.OverallAchievementPct = derivedPct(compAR, compTR)
	}
	sum.OverallAchievementRevPct = derivedPct(compAR, compTR)
	if totCases > 0 && totRev > 0 {
		sum.AvgCasePriceEGP = round2(totRev / totCases)
	}
	sum.TotalBranchesCovered = len(branchSet)
	sum.TotalSKUsCovered = len(skuSet)
	sum.PackSizeMissingSKUsCount = len(packMissing)
	sum.CostMissingSKUsCount = len(costMissing)
	return sum, nil
}

func sortedBrands(set map[string]bool) []string {
	out := make([]string, 0, len(set))
	hasNoBrand := false
	for b := range set {
		if b == NoBrandLabelAr {
			hasNoBrand = true
			continue
		}
		out = append(out, b)
	}
	sort.Strings(out)
	if hasNoBrand {
		out = append(out, NoBrandLabelAr)
	}
	return out
}

// derivedLeavesLocked splits the Sell-Out target pieces over the Sell-Out branch x SKU allocation.
// The pieces always add up to the Sell-Out target quantity exactly (largest-remainder apportionment).
func (c *Client) derivedLeavesLocked(normTenant string, dt *derivedTarget, bd domain.TargetBreakdownResponse, cache map[string]derivedSKUInfo) []derivedLeaf {
	type ref struct {
		b domain.TargetBreakdownBranch
		s domain.TargetBreakdownSKU
	}
	var refs []ref
	var unitWeights, revWeights []int64
	var anyUnits bool
	for _, b := range bd.Branches {
		for _, s := range b.SKUs {
			refs = append(refs, ref{b, s})
			var uw int64
			if s.AllocatedUnits != nil && *s.AllocatedUnits > 0 {
				uw = *s.AllocatedUnits
				anyUnits = true
			}
			unitWeights = append(unitWeights, uw)
			revWeights = append(revWeights, int64(math.Round(s.AllocatedTargetEGP*100)))
		}
	}
	weights := unitWeights
	if !anyUnits {
		weights = revWeights
	}
	pieces := targetalloc.Apportion(dt.units, weights)

	var leaves []derivedLeaf
	var placed int64
	for i, rf := range refs {
		if pieces[i] <= 0 {
			continue
		}
		placed += pieces[i]
		info := c.resolveDerivedSKUInfoLocked(normTenant, rf.s.SKUKey, rf.s.SKUKey, rf.s.SKUName, cache)
		leaves = append(leaves, c.newDerivedLeaf(dt.t, derivedLeaf{
			branchKey: rf.b.BranchKey, branchName: rf.b.BranchName,
			skuKey: rf.s.SKUKey, skuName: rf.s.SKUName, category: rf.s.Category,
			info: info, pieces: pieces[i],
		}))
	}
	if placed < dt.units {
		// No allocation history (or nothing to weight by): keep the full Sell-Out quantity, unallocated.
		leaves = append(leaves, c.newDerivedLeaf(dt.t, derivedLeaf{
			skuName: derivedUnallocatedSKUName,
			info:    derivedSKUInfo{identity: derivedUnallocatedIdentity, brand: NoBrandLabelAr, costMissing: true},
			pieces:  dt.units - placed, unallocated: true,
		}))
	}
	return leaves
}

func (c *Client) newDerivedLeaf(t domain.TargetRecord, l derivedLeaf) derivedLeaf {
	switch {
	case t.ExplicitUnitPriceEGP > 0:
		l.unitCost = t.ExplicitUnitPriceEGP
	case !l.info.costMissing:
		l.unitCost = l.info.unitCost
	}
	l.costMissing = l.unitCost <= 0
	return l
}

func (c *Client) buildDerivedItem(normTenant string, dt *derivedTarget, brands []string) *domain.TargetComparisonItem {
	t := dt.t
	skus := map[string]*derivedSKUAgg{}
	var skuOrder []string
	branches := map[string]*derivedBranchAgg{}
	var branchOrder []string
	brandAggs := map[string]*derivedBrandAgg{}

	var targetPieces int64
	var targetValue, targetCases float64
	casesKnown := false
	packMissing := map[string]bool{}
	costMissing := map[string]bool{}

	getSKU := func(identity, key, name, brand string) *derivedSKUAgg {
		s := skus[identity]
		if s == nil {
			s = &derivedSKUAgg{identity: identity, key: key, name: name, brand: brand}
			skus[identity] = s
			skuOrder = append(skuOrder, identity)
		}
		return s
	}
	getBrand := func(brand string) *derivedBrandAgg {
		b := brandAggs[brand]
		if b == nil {
			b = &derivedBrandAgg{brand: brand, skus: map[string]bool{}}
			brandAggs[brand] = b
		}
		return b
	}

	for _, l := range dt.leaves {
		if !derivedBrandSelected(l.info.brand, brands) {
			continue
		}
		value := 0.0
		if !l.costMissing {
			value = float64(l.pieces) * l.unitCost
		}
		targetPieces += l.pieces
		targetValue += value
		var leafCases float64
		if l.info.upc > 0 {
			leafCases = float64(l.pieces) / float64(l.info.upc)
			targetCases += leafCases
			casesKnown = true
		}
		s := getSKU(l.info.identity, l.skuKey, l.skuName, l.info.brand)
		if s.name == "" {
			s.name = l.skuName
		}
		s.category = l.category
		s.itemCode, s.barcode = l.info.itemCode, l.info.barcode
		s.upc = l.info.upc
		s.pieces += l.pieces
		s.value += value
		s.unitCost = l.unitCost
		s.costMissing = l.costMissing
		bg := getBrand(l.info.brand)
		bg.pieces += l.pieces
		bg.value += value
		bg.skus[l.info.identity] = true
		if !l.unallocated {
			if l.info.upc <= 0 {
				packMissing[l.info.identity] = true
			}
			if l.costMissing {
				costMissing[l.info.identity] = true
			}
		}
		if l.branchKey == "" {
			continue
		}
		b := branches[l.branchKey]
		if b == nil {
			b = &derivedBranchAgg{key: l.branchKey, name: l.branchName, skus: map[string]*derivedSKUAgg{}}
			branches[l.branchKey] = b
			branchOrder = append(branchOrder, l.branchKey)
		}
		b.pieces += l.pieces
		b.value += value
		if l.info.upc > 0 {
			b.cases += leafCases
			b.casesKnown = true
		}
		bs := b.skus[l.info.identity]
		if bs == nil {
			bs = &derivedSKUAgg{identity: l.info.identity, key: l.skuKey, name: l.skuName, brand: l.info.brand,
				itemCode: l.info.itemCode, barcode: l.info.barcode, upc: l.info.upc, category: l.category, unitCost: l.unitCost, costMissing: l.costMissing}
			b.skus[l.info.identity] = bs
			b.skuOrder = append(b.skuOrder, l.info.identity)
		}
		bs.pieces += l.pieces
		bs.value += value
	}

	if targetPieces == 0 && len(brands) > 0 {
		return nil // nothing of this Sell-Out target belongs to the selected brands
	}

	// Actuals: header = every in-scope Sell-In row of the selected brands; SKU / branch rows best-effort.
	var actPieces, actCases, actValue, actTons float64
	var actRows int
	assign := map[string]int{}
	branchList := make([]*derivedBranchAgg, 0, len(branchOrder))
	for _, k := range branchOrder {
		branchList = append(branchList, branches[k])
	}
	branchOf := func(r *derivedSellInRow) int {
		key := r.customerCode + "|" + r.customerName
		if idx, ok := assign[key]; ok {
			return idx
		}
		idx := -1
		for i, b := range branchList {
			if r.customerCode != "" && strings.EqualFold(r.customerCode, strings.TrimSpace(b.key)) {
				idx = i
				break
			}
		}
		if idx < 0 && r.customerName != "" {
			for i, b := range branchList {
				bn := strings.ToLower(strings.TrimSpace(b.name))
				if bn != "" && (strings.Contains(r.customerName, bn) || strings.Contains(bn, r.customerName)) {
					idx = i
					break
				}
			}
		}
		assign[key] = idx
		return idx
	}
	for _, r := range dt.rows {
		if !derivedBrandSelected(r.brand, brands) {
			continue
		}
		actRows++
		actPieces += r.pieces
		actCases += r.cases
		actValue += r.value
		actTons += r.tons
		s := getSKU(r.identity, "", r.name, r.brand)
		s.actualPieces += r.pieces
		s.actualCases += r.cases
		s.actualValue += r.value
		s.actualTons += r.tons
		bg := getBrand(r.brand)
		bg.actualPieces += r.pieces
		bg.actualValue += r.value
		if idx := branchOf(r); idx >= 0 {
			b := branchList[idx]
			b.actualPieces += r.pieces
			b.actualCases += r.cases
			b.actualValue += r.value
			b.actualTons += r.tons
			if bs := b.skus[r.identity]; bs != nil {
				bs.actualPieces += r.pieces
				bs.actualCases += r.cases
				bs.actualValue += r.value
			}
		}
	}

	hasActuals := actRows > 0
	chainDisp := t.ChainDisplayName
	if chainDisp == "" {
		if derivedChainKey(t.RetailerChain) == "" {
			chainDisp = "كل السلاسل (All Chains)"
		} else {
			chainDisp = getRetailChainDisplayName(t.RetailerChain)
		}
	}

	item := &domain.TargetComparisonItem{
		ID:                  DerivedSellInTargetID(t.ID),
		TenantID:            normTenant,
		TargetType:          "sell_in",
		RetailerChain:       t.RetailerChain,
		ChainDisplayName:    chainDisp,
		Year:                t.Year,
		Month:               t.Month,
		MonthLabel:          formatTargetMonthLabel(t.Year, t.Month),
		BranchName:          t.BranchName,
		Category:            t.Category,
		TargetUnits:         float64(targetPieces),
		TargetRevenueEGP:    round2(targetValue),
		ActualUnits:         round2(actPieces),
		ActualRevenueEGP:    round2(actValue),
		ActualWeightTons:    round2(actTons),
		HasActuals:          hasActuals,
		Notes:               t.Notes,
		UpdatedAt:           t.UpdatedAt,
		Origin:              t.Origin,
		Derived:             true,
		SourceTargetID:      t.ID,
		PackSizeMissingSKUs: len(packMissing),
		CostMissingSKUs:     len(costMissing),
		ExcludedFromTotals:  dt.excluded,
		ExcludedReason:      dt.reason,
		SalesRepQuotas:      []domain.TargetSalesRepQuota{},
		MonthlyPhasing:      []domain.TargetMonthBreakdown{},
	}
	if casesKnown {
		item.TargetCases = floatPtr(targetCases)
	}
	if hasActuals {
		item.ActualCases = floatPtr(actCases)
		item.VarianceUnits = round2(actPieces - float64(targetPieces))
		item.VarianceRevenueEGP = round2(actValue - targetValue)
		item.AchievementUnitsPct = derivedPct(actPieces, float64(targetPieces))
		item.AchievementRevPct = derivedPct(actValue, targetValue)
	}
	if targetCases > 0 && targetValue > 0 {
		item.AvgCasePriceEGP = round2(targetValue / targetCases)
	}
	item.Status, item.StatusAr = derivedStatus(hasActuals, item.AchievementUnitsPct, item.AchievementRevPct, float64(targetPieces))

	// Chain-wide SKU totals (quantity first).
	chainSKUs := make([]domain.TargetSKUBreakdown, 0, len(skuOrder))
	for _, id := range skuOrder {
		s := skus[id]
		chainSKUs = append(chainSKUs, derivedSKURow(s, t, hasActuals))
	}
	sort.SliceStable(chainSKUs, func(i, j int) bool {
		if chainSKUs[i].TargetUnits != chainSKUs[j].TargetUnits {
			return chainSKUs[i].TargetUnits > chainSKUs[j].TargetUnits
		}
		return chainSKUs[i].SKUName < chainSKUs[j].SKUName
	})
	item.ChainSKUTotals = chainSKUs
	item.ActiveSKUsCount = 0
	for _, s := range chainSKUs {
		if s.TargetUnits > 0 && s.SKUName != derivedUnallocatedSKUName {
			item.ActiveSKUsCount++
		}
	}

	// Branches.
	item.Branches = make([]domain.TargetBranchBreakdown, 0, len(branchList))
	for _, b := range branchList {
		br := domain.TargetBranchBreakdown{
			BranchCode:       b.key,
			BranchName:       b.name,
			ActiveSKUsCount:  len(b.skuOrder),
			TargetUnits:      float64(b.pieces),
			TargetRevenueEGP: round2(b.value),
			ActualUnits:      round2(b.actualPieces),
			ActualRevenueEGP: round2(b.actualValue),
			ActualWeightTons: round2(b.actualTons),
			SKUs:             make([]domain.TargetSKUBreakdown, 0, len(b.skuOrder)),
		}
		if targetPieces > 0 {
			br.ShareOfChainPct = math.Round(float64(b.pieces)/float64(targetPieces)*10000) / 100
		}
		if b.casesKnown {
			br.TargetCases = floatPtr(b.cases)
		}
		branchHasActual := b.actualPieces != 0 || b.actualValue != 0
		if branchHasActual {
			br.ActualCases = floatPtr(b.actualCases)
			br.VarianceUnits = round2(b.actualPieces - float64(b.pieces))
			br.VarianceRevenueEGP = round2(b.actualValue - b.value)
			br.AchievementUnitsPct = derivedPct(b.actualPieces, float64(b.pieces))
			br.AchievementRevPct = derivedPct(b.actualValue, b.value)
		}
		br.Status, br.StatusAr = derivedStatus(branchHasActual, br.AchievementUnitsPct, br.AchievementRevPct, float64(b.pieces))
		for _, id := range b.skuOrder {
			br.SKUs = append(br.SKUs, derivedSKURow(b.skus[id], t, branchHasActual))
		}
		sort.SliceStable(br.SKUs, func(i, j int) bool {
			if br.SKUs[i].TargetUnits != br.SKUs[j].TargetUnits {
				return br.SKUs[i].TargetUnits > br.SKUs[j].TargetUnits
			}
			return br.SKUs[i].SKUName < br.SKUs[j].SKUName
		})
		item.Branches = append(item.Branches, br)
	}
	sort.SliceStable(item.Branches, func(i, j int) bool {
		if item.Branches[i].TargetUnits != item.Branches[j].TargetUnits {
			return item.Branches[i].TargetUnits > item.Branches[j].TargetUnits
		}
		return item.Branches[i].BranchName < item.Branches[j].BranchName
	})
	item.BranchesCount = len(item.Branches)

	// Brands (Product Master brand; «بدون براند» when missing).
	item.Brands = make([]domain.TargetBrandBreakdown, 0, len(brandAggs))
	for _, bg := range brandAggs {
		row := domain.TargetBrandBreakdown{
			Brand:            bg.brand,
			ActiveSKUsCount:  len(bg.skus),
			TargetUnits:      float64(bg.pieces),
			TargetRevenueEGP: round2(bg.value),
			ActualUnits:      round2(bg.actualPieces),
			ActualRevenueEGP: round2(bg.actualValue),
		}
		if targetPieces > 0 {
			row.SharePct = math.Round(float64(bg.pieces)/float64(targetPieces)*10000) / 100
		}
		if hasActuals {
			row.VarianceUnits = round2(bg.actualPieces - float64(bg.pieces))
			row.VarianceRevenueEGP = round2(bg.actualValue - bg.value)
			if bg.pieces > 0 {
				row.AchievementPct = derivedPct(bg.actualPieces, float64(bg.pieces))
			} else {
				row.AchievementPct = derivedPct(bg.actualValue, bg.value)
			}
		}
		item.Brands = append(item.Brands, row)
	}
	sort.SliceStable(item.Brands, func(i, j int) bool {
		if item.Brands[i].TargetUnits != item.Brands[j].TargetUnits {
			return item.Brands[i].TargetUnits > item.Brands[j].TargetUnits
		}
		return item.Brands[i].Brand < item.Brands[j].Brand
	})
	return item
}

func derivedSKURow(s *derivedSKUAgg, t domain.TargetRecord, hasActuals bool) domain.TargetSKUBreakdown {
	row := domain.TargetSKUBreakdown{
		ItemCode:         s.itemCode,
		Barcode:          s.barcode,
		UnitsPerCarton:   s.upc,
		SKUName:          s.name,
		Brand:            s.brand,
		SubCategory:      s.category,
		TargetPieces:     int(s.pieces),
		TargetUnits:      float64(s.pieces),
		TargetRevenueEGP: round2(s.value),
		UnitCostEGP:      round2(s.unitCost),
		CostMissing:      s.costMissing && s.pieces > 0 && s.identity != derivedUnallocatedIdentity,
		PackSizeMissing:  s.upc <= 0 && s.pieces > 0 && s.identity != derivedUnallocatedIdentity,
		ActualPieces:     int(math.Round(s.actualPieces)),
		ActualUnits:      round2(s.actualPieces),
		ActualRevenueEGP: round2(s.actualValue),
		ActualWeightTons: round2(s.actualTons),
	}
	if s.upc > 0 {
		row.TargetCases = floatPtr(float64(s.pieces) / float64(s.upc))
	}
	if hasActuals {
		row.ActualCases = floatPtr(s.actualCases)
		row.VarianceUnits = round2(s.actualPieces - float64(s.pieces))
		row.VarianceRevenueEGP = round2(s.actualValue - s.value)
		if s.pieces > 0 {
			row.AchievementPct = derivedPct(s.actualPieces, float64(s.pieces))
		} else {
			row.AchievementPct = derivedPct(s.actualValue, s.value)
		}
	}
	if s.pieces > 0 && s.value > 0 && s.upc > 0 {
		row.CasePriceEGP = round2(s.value / (float64(s.pieces) / float64(s.upc)))
	}
	return row
}

// derivedStatus classifies achievement on quantity first, then on value.
func derivedStatus(hasActuals bool, achUnits, achRev, targetUnits float64) (string, string) {
	if !hasActuals {
		return "no_data", "لا توجد مبيعات بعد"
	}
	pct := achUnits
	if targetUnits <= 0 {
		pct = achRev
	}
	return classifyTargetStatus(pct)
}

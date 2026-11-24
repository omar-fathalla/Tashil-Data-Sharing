package bigquery

import (
	"context"
	"errors"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sync/errgroup"
	"golang.org/x/sync/singleflight"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// Sell-In targets are never entered: the server materializes one derived Sell-In target per Sell-Out target.
//
//   - Quantity (pieces) is the primary metric: derived pieces = the Sell-Out target pieces, 1:1, split over
//     the same chain / branch / SKU / period. Only these pieces are stored (TargetRecord.DerivedLines).
//   - Value is secondary and computed on read: pieces x the current Product Master cost price (or the
//     Sell-Out target's explicit unit price). Cases = pieces / the current Product Master pack size.
//   - Achievement compares the actual Sell-In quantity first, then the actual Sell-In value. Sell-In rows
//     are matched to the Product Master once, when they are loaded; reads only look item codes up.
//
// Saving a Sell-Out target replaces its derived record in the same write and deleting it removes it. A
// Sell-Out target without a current derived record (older data, bulk imports) is materialized once on the
// next read. Legacy manually-entered sell_in records stay in the tenant JSON untouched but are ignored.

const (
	// derivedSellInFormatVersion is bumped when the materialized shape changes; older records are rebuilt.
	derivedSellInFormatVersion  = 1
	derivedBreakdownParallelism = 4
	derivedBackfillTimeout      = 2 * time.Minute
	derivedSummaryCacheMax      = 64
)

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

func derivedRawIdentity(code, barcode, name string) string {
	raw := strings.TrimSpace(code)
	if raw == "" {
		raw = strings.TrimSpace(barcode)
	}
	if raw == "" {
		raw = strings.TrimSpace(name)
	}
	return "raw:" + strings.ToLower(raw)
}

// derivedSKUInfoFromPM takes brand, pack size and cost from a Product Master item (ok=false: unmatched).
func derivedSKUInfoFromPM(pm domain.ProductMasterItem, ok bool, rawIdentity string) derivedSKUInfo {
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
		info.identity = rawIdentity
	}
	cost, _, _ := resolveRealFactoryUnitCost(0, pm, ok)
	if cost > 0 {
		info.unitCost = cost
	} else {
		info.costMissing = true
	}
	return info
}

// derivedRowSKUInfoLocked resolves a Sell-In row by the item code its load-time enrichment assigned
// (enrichSellInRecordLocked). No name matching happens here: a row unmatched at load stays unmatched.
func (c *Client) derivedRowSKUInfoLocked(normTenant string, rec *domain.SellInRecord, cache map[string]derivedSKUInfo) derivedSKUInfo {
	ck := "row\x1f" + rec.ItemCode + "\x1f" + rec.Barcode + "\x1f" + rec.ItemName
	if v, ok := cache[ck]; ok {
		return v
	}
	pm, ok := c.productMasterByCode[normTenant][domain.NormalizeItemCode(rec.ItemCode)]
	info := derivedSKUInfoFromPM(pm, ok, derivedRawIdentity(rec.ItemCode, rec.Barcode, rec.ItemName))
	cache[ck] = info
	return info
}

// derivedLineSKUInfoLocked resolves a materialized line by the Product Master item matched when it was
// written, else by exact code / barcode / name (a later Product Master may know it). No fuzzy matching.
func (c *Client) derivedLineSKUInfoLocked(normTenant string, l domain.DerivedSellInLine, cache map[string]derivedSKUInfo) derivedSKUInfo {
	ck := "line\x1f" + l.ItemCode + "\x1f" + l.SKUKey + "\x1f" + l.SKUName
	if v, ok := cache[ck]; ok {
		return v
	}
	var pm domain.ProductMasterItem
	ok := false
	if code := domain.NormalizeItemCode(l.ItemCode); code != "" {
		pm, ok = c.productMasterByCode[normTenant][code]
	}
	if !ok {
		if code := domain.NormalizeItemCode(l.SKUKey); code != "" {
			pm, ok = c.productMasterByCode[normTenant][code]
		}
	}
	if !ok {
		if bc := domain.CleanBarcode(l.SKUKey); bc != "" {
			pm, ok = c.productMasterByBarcode[normTenant][bc]
		}
	}
	if !ok {
		if nk := normalizeArabicNameForLookup(l.SKUName); nk != "" {
			pm, ok = c.productMasterByName[normTenant][nk]
		}
	}
	info := derivedSKUInfoFromPM(pm, ok, derivedRawIdentity(l.SKUKey, l.SKUKey, l.SKUName))
	cache[ck] = info
	return info
}

// derivedSellInRowsLocked copies the tenant's (load-time enriched) Sell-In records that keep accepts into
// comparable rows. Caller holds c.mu (read).
func (c *Client) derivedSellInRowsLocked(ctx context.Context, normTenant string, keep func(chain string, year int) bool, cache map[string]derivedSKUInfo) ([]*derivedSellInRow, error) {
	raw := c.sellInRecords[normTenant]
	var slab []derivedSellInRow
	for i := range raw {
		if i&4095 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		rec := &raw[i]
		chain := strings.ToLower(strings.TrimSpace(rec.RetailerChain))
		if chain == "" {
			chain = "fathalla"
		}
		if !keep(chain, rec.Year) {
			continue
		}
		info := c.derivedRowSKUInfoLocked(normTenant, rec, cache)
		upc := rec.UnitsPerCarton
		if upc <= 0 {
			upc = 12
		}
		slab = append(slab, derivedSellInRow{
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
	rows := make([]*derivedSellInRow, len(slab))
	for i := range slab {
		rows[i] = &slab[i]
	}
	return rows, nil
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

// derivedSellInState holds the Sell-Out allocation provider and the derived summary cache.
type derivedSellInState struct {
	mu       sync.Mutex
	provider func(tenantID string) DerivedBreakdownFunc
	cache    map[string]derivedSummaryCacheEntry
	flight   singleflight.Group
}

type derivedSummaryCacheEntry struct {
	version string
	sum     *domain.TargetsSummaryResponse
}

// SetDerivedSellInBreakdown sets where Sell-Out allocations come from when Sell-In targets are
// materialized (e.g. BigQuery). nil = the in-memory Sell-Out records.
func (c *Client) SetDerivedSellInBreakdown(p func(tenantID string) DerivedBreakdownFunc) {
	c.derivedSI.mu.Lock()
	c.derivedSI.provider = p
	c.derivedSI.mu.Unlock()
}

func (c *Client) derivedBreakdownFor(normTenant string) DerivedBreakdownFunc {
	c.derivedSI.mu.Lock()
	p := c.derivedSI.provider
	c.derivedSI.mu.Unlock()
	if p == nil {
		return nil
	}
	return p(normTenant)
}

// derivedSummaryVersionLocked changes with every source write (bumpSourceVersion: Sell-In / Sell-Out
// uploads, targets) and every Product Master or in-place Sell-In enrichment change.
func (c *Client) derivedSummaryVersionLocked() string {
	return strconv.FormatInt(c.precompute.sourceVersion.Load(), 10) + "." + strconv.FormatUint(c.chainDisc.dataGen.Load(), 10)
}

func (s *derivedSellInState) cached(key, version string) (*domain.TargetsSummaryResponse, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.cache[key]
	if !ok || e.version != version {
		return nil, false
	}
	cp := *e.sum
	return &cp, true
}

func (s *derivedSellInState) store(key, version string, sum *domain.TargetsSummaryResponse) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cache == nil {
		s.cache = make(map[string]derivedSummaryCacheEntry)
	}
	if len(s.cache) >= derivedSummaryCacheMax {
		for k, e := range s.cache {
			if e.version != version {
				delete(s.cache, k)
			}
		}
		if len(s.cache) >= derivedSummaryCacheMax {
			s.cache = make(map[string]derivedSummaryCacheEntry)
		}
	}
	s.cache[key] = derivedSummaryCacheEntry{version: version, sum: sum}
}

type deferDerivedSellInKey struct{}

// WithDeferredSellInMaterialization marks bulk Sell-Out target writes: UpsertTarget saves the target and
// drops its outdated derived Sell-In record, and the caller materializes them all at once afterwards
// (MaterializeDerivedSellInTargets) instead of computing one allocation per row.
func WithDeferredSellInMaterialization(ctx context.Context) context.Context {
	return context.WithValue(ctx, deferDerivedSellInKey{}, true)
}

func deferredSellInMaterialization(ctx context.Context) bool {
	v, _ := ctx.Value(deferDerivedSellInKey{}).(bool)
	return v
}

func isDerivedSellInRecord(t domain.TargetRecord) bool {
	return t.TargetType == "sell_in" && t.Derived && IsDerivedSellInTargetID(t.ID)
}

func derivedRecordCurrent(d, source domain.TargetRecord) bool {
	return d.SourceUpdatedAt == source.UpdatedAt && d.DerivedVersion == derivedSellInFormatVersion
}

func derivedTargetInScope(t domain.TargetRecord, chainFilter string, year int) bool {
	ch := derivedChainKey(t.RetailerChain)
	if chainFilter != "" && ch != "" && !strings.EqualFold(ch, chainFilter) {
		return false
	}
	return year <= 0 || t.Year == year
}

// derivedWorkLocked prepares a Sell-Out target for allocation: its quantity (and value, used as the
// weight when no unit history exists) inferred from the chain's average price when missing.
func (c *Client) derivedWorkLocked(normTenant string, t domain.TargetRecord) (domain.TargetRecord, int64) {
	units := t.TargetUnits
	ch := derivedChainKey(t.RetailerChain)
	if units <= 0 && t.TargetRevenueEGP > 0 {
		if avg, _ := c.inferChainUnitPriceAndTonsLocked(normTenant, "sell_out", ch); avg > 0 {
			units = math.Round(t.TargetRevenueEGP / avg)
		}
	}
	pieces := int64(math.Round(units))
	allocRev := t.TargetRevenueEGP
	if allocRev <= 0 && pieces > 0 {
		if avg, _ := c.inferChainUnitPriceAndTonsLocked(normTenant, "sell_out", ch); avg > 0 {
			allocRev = math.Round(float64(pieces) * avg)
		}
	}
	work := t
	work.TargetUnits = float64(pieces)
	work.TargetRevenueEGP = allocRev
	return work, pieces
}

// derivedBreakdowns fetches the Sell-Out branch/SKU allocation of each work target (index-aligned) with
// bounded parallelism. bd (e.g. BigQuery) is tried first; the in-memory Sell-Out records are the fallback.
func (c *Client) derivedBreakdowns(ctx context.Context, normTenant string, works []domain.TargetRecord, bd DerivedBreakdownFunc) ([]domain.TargetBreakdownResponse, error) {
	out := make([]domain.TargetBreakdownResponse, len(works))
	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(derivedBreakdownParallelism)
	for i := range works {
		g.Go(func() error {
			if err := gctx.Err(); err != nil {
				return err
			}
			var resp domain.TargetBreakdownResponse
			found := false
			if bd != nil {
				resp, found = bd(gctx, works[i])
			}
			// A cancelled request must not persist the fallback allocation in place of the real one.
			if err := gctx.Err(); err != nil {
				return err
			}
			if !found {
				src := c.TargetBreakdownSource(normTenant, targetalloc.ChainFilter(works[i].RetailerChain))
				if r, ok, err := targetalloc.ComputeFiltered(gctx, src, works[i], "memory", targetalloc.Filters{}); err == nil && ok {
					resp = r
				}
			}
			out[i] = resp
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return nil, err
	}
	return out, nil
}

// materializeDerivedSellIn computes the derived Sell-In record of each Sell-Out target (index-aligned).
// It takes c.mu itself; the caller must not hold it.
func (c *Client) materializeDerivedSellIn(ctx context.Context, normTenant string, sources []domain.TargetRecord, bd DerivedBreakdownFunc) ([]domain.TargetRecord, error) {
	if len(sources) == 0 {
		return nil, nil
	}
	works := make([]domain.TargetRecord, len(sources))
	pieces := make([]int64, len(sources))
	c.mu.RLock()
	for i, t := range sources {
		works[i], pieces[i] = c.derivedWorkLocked(normTenant, t)
	}
	c.mu.RUnlock()

	breakdowns, err := c.derivedBreakdowns(ctx, normTenant, works, bd)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC().Format(time.RFC3339)
	memo := map[string]string{}
	out := make([]domain.TargetRecord, len(sources))
	c.mu.RLock()
	defer c.mu.RUnlock()
	for i, t := range sources {
		out[i] = domain.TargetRecord{
			ID:               DerivedSellInTargetID(t.ID),
			TenantID:         normTenant,
			TargetType:       "sell_in",
			RetailerChain:    t.RetailerChain,
			ChainDisplayName: t.ChainDisplayName,
			Year:             t.Year,
			Month:            t.Month,
			MonthLabel:       t.MonthLabel,
			BranchName:       t.BranchName,
			Category:         t.Category,
			TargetUnits:      float64(pieces[i]),
			UpdatedAt:        now,
			Origin:           t.Origin,
			Derived:          true,
			SourceTargetID:   t.ID,
			SourceUpdatedAt:  t.UpdatedAt,
			DerivedVersion:   derivedSellInFormatVersion,
			DerivedLines:     c.derivedLinesLocked(normTenant, pieces[i], breakdowns[i], memo),
		}
	}
	return out, nil
}

// putDerivedSellInLocked stores rec in place of its previous version, but only while its Sell-Out target
// is still the version it was computed from. Reports whether the list changed. Caller holds c.mu (write).
func (c *Client) putDerivedSellInLocked(normTenant string, rec domain.TargetRecord) bool {
	list := c.targets[normTenant]
	current := false
	for _, t := range list {
		if t.TargetType != "sell_in" && t.ID == rec.SourceTargetID && t.UpdatedAt == rec.SourceUpdatedAt {
			current = true
			break
		}
	}
	if !current {
		return false
	}
	for i := range list {
		if list[i].ID == rec.ID {
			if !isDerivedSellInRecord(list[i]) {
				return false
			}
			list[i] = rec
			return true
		}
	}
	c.targets[normTenant] = append(list, rec)
	return true
}

// dropDerivedSellInLocked removes the derived record of a Sell-Out target. Caller holds c.mu (write).
func (c *Client) dropDerivedSellInLocked(normTenant, sourceID string) bool {
	id := DerivedSellInTargetID(sourceID)
	list := c.targets[normTenant]
	kept := list[:0:0]
	for _, t := range list {
		if t.ID == id && isDerivedSellInRecord(t) {
			continue
		}
		kept = append(kept, t)
	}
	if len(kept) == len(list) {
		return false
	}
	c.targets[normTenant] = kept
	return true
}

// dropOrphanDerivedSellInLocked removes derived records whose Sell-Out target no longer exists.
func (c *Client) dropOrphanDerivedSellInLocked(normTenant string) bool {
	list := c.targets[normTenant]
	sources := map[string]bool{}
	for _, t := range list {
		if t.TargetType != "sell_in" {
			sources[t.ID] = true
		}
	}
	kept := list[:0:0]
	for _, t := range list {
		if isDerivedSellInRecord(t) && !sources[t.SourceTargetID] {
			continue
		}
		kept = append(kept, t)
	}
	if len(kept) == len(list) {
		return false
	}
	c.targets[normTenant] = kept
	return true
}

// derivedSellInPendingLocked lists the in-scope Sell-Out targets whose derived record is missing or
// outdated, and whether orphaned derived records exist.
func (c *Client) derivedSellInPendingLocked(normTenant, chainFilter string, year int) (todo []domain.TargetRecord, orphans bool) {
	list := c.targets[normTenant]
	derived := map[string]domain.TargetRecord{}
	sources := map[string]bool{}
	for _, t := range list {
		if isDerivedSellInRecord(t) {
			derived[t.SourceTargetID] = t
		} else if t.TargetType != "sell_in" {
			sources[t.ID] = true
		}
	}
	for _, t := range list {
		if t.TargetType == "sell_in" || !derivedTargetInScope(t, chainFilter, year) {
			continue
		}
		if d, ok := derived[t.ID]; !ok || !derivedRecordCurrent(d, t) {
			todo = append(todo, t)
		}
	}
	for src := range derived {
		if !sources[src] {
			orphans = true
			break
		}
	}
	return todo, orphans
}

// ensureDerivedSellIn is the idempotent lazy backfill: Sell-Out targets in scope without a current
// derived record are materialized and saved once. Concurrent reads of the same scope share one run, which
// is not cancelled when the first reader goes away.
func (c *Client) ensureDerivedSellIn(ctx context.Context, normTenant, chainFilter string, year int, bd DerivedBreakdownFunc) error {
	c.mu.RLock()
	todo, orphans := c.derivedSellInPendingLocked(normTenant, chainFilter, year)
	c.mu.RUnlock()
	if len(todo) == 0 && !orphans {
		return nil
	}
	key := normTenant + "|" + chainFilter + "|" + strconv.Itoa(year)
	ch := c.derivedSI.flight.DoChan(key, func() (interface{}, error) {
		bctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), derivedBackfillTimeout)
		defer cancel()
		return nil, c.backfillDerivedSellIn(bctx, normTenant, chainFilter, year, bd)
	})
	select {
	case <-ctx.Done():
		return ctx.Err()
	case r := <-ch:
		return r.Err
	}
}

func (c *Client) backfillDerivedSellIn(ctx context.Context, normTenant, chainFilter string, year int, bd DerivedBreakdownFunc) error {
	c.mu.RLock()
	todo, orphans := c.derivedSellInPendingLocked(normTenant, chainFilter, year)
	c.mu.RUnlock()
	if len(todo) == 0 && !orphans {
		return nil
	}
	recs, err := c.materializeDerivedSellIn(ctx, normTenant, todo, bd)
	if err != nil {
		return err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	changed := false
	for _, r := range recs {
		if c.putDerivedSellInLocked(normTenant, r) {
			changed = true
		}
	}
	if c.dropOrphanDerivedSellInLocked(normTenant) {
		changed = true
	}
	if changed {
		c.bumpSourceVersion()
		c.persistTenantTargetsLocked(normTenant)
	}
	return nil
}

// MaterializeDerivedSellInTargets saves the derived Sell-In record of every Sell-Out target of a tenant
// that has none or an outdated one (idempotent). Used after bulk target imports.
func (c *Client) MaterializeDerivedSellInTargets(ctx context.Context, tenantID string) error {
	normTenant := normalizeTenantKey(tenantID)
	return c.ensureDerivedSellIn(ctx, normTenant, "", 0, c.derivedBreakdownFor(normTenant))
}

// GetDerivedSellInTargetsSummary reads the tenant's materialized Sell-In targets (backfilling any missing
// one first) with their actual Sell-In achievement. Results are cached per tenant / chain / year / brands
// until the next source or Product Master change.
func (c *Client) GetDerivedSellInTargetsSummary(ctx context.Context, tenantID string, opts DerivedSellInOptions) (*domain.TargetsSummaryResponse, error) {
	normTenant := normalizeTenantKey(tenantID)
	chainFilter := derivedChainKey(opts.Chain)
	bd := opts.Breakdown
	if bd == nil {
		bd = c.derivedBreakdownFor(normTenant)
	}
	if err := c.ensureDerivedSellIn(ctx, normTenant, chainFilter, opts.Year, bd); err != nil {
		return nil, err
	}

	key := normTenant + "|" + chainFilter + "|" + strconv.Itoa(opts.Year) + "|" + strings.Join(opts.Brands, "\x1f")
	c.mu.RLock()
	version := c.derivedSummaryVersionLocked()
	if sum, ok := c.derivedSI.cached(key, version); ok {
		c.mu.RUnlock()
		return sum, nil
	}
	targets, rows, err := c.derivedSnapshotLocked(ctx, normTenant, chainFilter, opts.Year)
	c.mu.RUnlock()
	if err != nil {
		return nil, err
	}

	sum, err := c.buildDerivedSummary(ctx, normTenant, targets, rows, opts)
	if err != nil {
		return nil, err
	}
	c.derivedSI.store(key, version, sum)
	cp := *sum
	return &cp, nil
}

// derivedSnapshotLocked copies what the summary needs out of the store: the Sell-Out targets in scope with
// their materialized pieces (valued with the current Product Master) and the Sell-In rows they can match.
// Caller holds c.mu (read); the aggregation then runs without the lock.
func (c *Client) derivedSnapshotLocked(ctx context.Context, normTenant, chainFilter string, year int) ([]*derivedTarget, []*derivedSellInRow, error) {
	var all []domain.TargetRecord
	derived := map[string]domain.TargetRecord{}
	for _, t := range c.targets[normTenant] {
		if t.TargetType == "sell_in" {
			if isDerivedSellInRecord(t) {
				derived[t.SourceTargetID] = t
			}
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

	infoCache := map[string]derivedSKUInfo{}
	var targets []*derivedTarget
	chains := map[string]bool{}
	years := map[int]bool{}
	allChains, allYears := false, false
	for _, t := range all {
		if !derivedTargetInScope(t, chainFilter, year) {
			continue
		}
		dt := &derivedTarget{t: t}
		var lines []domain.DerivedSellInLine
		if d, ok := derived[t.ID]; ok {
			dt.units = int64(math.Round(d.TargetUnits))
			lines = d.DerivedLines
		} else {
			// Only when the backfill could not save it (the target changed meanwhile): keep the quantity.
			dt.units = int64(math.Round(t.TargetUnits))
			lines = []domain.DerivedSellInLine{{SKUName: derivedUnallocatedSKUName, Pieces: dt.units, Unallocated: true}}
		}
		dt.leaves = c.derivedLeavesLocked(normTenant, t, lines, infoCache)
		// Avoid double counting: an annual target is superseded by monthly targets of the same scope.
		if t.Month == 0 && monthlyScopes[derivedScopeKey(t)] {
			dt.excluded = true
			dt.reason = derivedExcludedSupersededByMonthly
		}
		targets = append(targets, dt)
		if ch := derivedChainKey(t.RetailerChain); ch == "" {
			allChains = true
		} else {
			chains[ch] = true
		}
		if t.Year <= 0 {
			allYears = true
		} else {
			years[t.Year] = true
		}
	}
	if len(targets) == 0 {
		return targets, nil, nil
	}
	rows, err := c.derivedSellInRowsLocked(ctx, normTenant, func(chain string, y int) bool {
		return (allChains || chains[chain]) && (allYears || years[y])
	}, infoCache)
	if err != nil {
		return nil, nil, err
	}
	return targets, rows, nil
}

// buildDerivedSummary matches the Sell-In rows to each target's scope and aggregates the response.
func (c *Client) buildDerivedSummary(ctx context.Context, normTenant string, targets []*derivedTarget, rows []*derivedSellInRow, opts DerivedSellInOptions) (*domain.TargetsSummaryResponse, error) {
	byPeriod := map[int][]*derivedSellInRow{}
	for _, r := range rows {
		k := r.year*100 + r.month
		byPeriod[k] = append(byPeriod[k], r)
	}
	brandSet := map[string]bool{}
	for _, dt := range targets {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		ch := derivedChainKey(dt.t.RetailerChain)
		br := normalizeScopeLabel(dt.t.BranchName, "كل الفروع")
		cat := normalizeScopeLabel(dt.t.Category, "كل الفئات")
		candidates := rows
		if dt.t.Year > 0 && dt.t.Month > 0 {
			candidates = byPeriod[dt.t.Year*100+dt.t.Month]
		}
		for _, r := range candidates {
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

// derivedLinesLocked splits the Sell-Out target pieces over the Sell-Out branch x SKU allocation and
// matches each SKU to the Product Master once (the stored item code). The pieces always add up to the
// Sell-Out target quantity exactly (largest-remainder apportionment). Caller holds c.mu (read).
func (c *Client) derivedLinesLocked(normTenant string, units int64, bd domain.TargetBreakdownResponse, memo map[string]string) []domain.DerivedSellInLine {
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
	pieces := targetalloc.Apportion(units, weights)

	var lines []domain.DerivedSellInLine
	var placed int64
	for i, rf := range refs {
		if pieces[i] <= 0 {
			continue
		}
		placed += pieces[i]
		lines = append(lines, domain.DerivedSellInLine{
			BranchKey: rf.b.BranchKey, BranchName: rf.b.BranchName,
			SKUKey: rf.s.SKUKey, SKUName: rf.s.SKUName, Category: rf.s.Category,
			ItemCode: c.derivedMatchItemCodeLocked(normTenant, rf.s.SKUKey, rf.s.SKUName, memo),
			Pieces:   pieces[i],
		})
	}
	if placed < units {
		// No allocation history (or nothing to weight by): keep the full Sell-Out quantity, unallocated.
		lines = append(lines, domain.DerivedSellInLine{SKUName: derivedUnallocatedSKUName, Pieces: units - placed, Unallocated: true})
	}
	return lines
}

func (c *Client) derivedMatchItemCodeLocked(normTenant, skuKey, skuName string, memo map[string]string) string {
	ck := skuKey + "\x1f" + skuName
	if v, ok := memo[ck]; ok {
		return v
	}
	code := ""
	if pm, ok := c.lookupProductMasterLocked(normTenant, skuKey, skuKey, skuName); ok {
		code = pm.ItemCode
	}
	memo[ck] = code
	return code
}

// derivedLeavesLocked turns the stored pieces of a target into valued leaves: brand, pack size and cost
// come from the current Product Master (or the Sell-Out target's explicit unit price).
func (c *Client) derivedLeavesLocked(normTenant string, t domain.TargetRecord, lines []domain.DerivedSellInLine, cache map[string]derivedSKUInfo) []derivedLeaf {
	leaves := make([]derivedLeaf, 0, len(lines))
	for _, l := range lines {
		if l.Pieces <= 0 {
			continue
		}
		info := derivedSKUInfo{identity: derivedUnallocatedIdentity, brand: NoBrandLabelAr, costMissing: true}
		if !l.Unallocated {
			info = c.derivedLineSKUInfoLocked(normTenant, l, cache)
		}
		leaves = append(leaves, c.newDerivedLeaf(t, derivedLeaf{
			branchKey: l.BranchKey, branchName: l.BranchName,
			skuKey: l.SKUKey, skuName: l.SKUName, category: l.Category,
			info: info, pieces: l.Pieces, unallocated: l.Unallocated,
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

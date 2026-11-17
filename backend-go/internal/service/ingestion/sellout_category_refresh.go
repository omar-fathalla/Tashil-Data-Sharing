package ingestion

import (
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// Sell-Out category refresh planning (read-only).
//
// sell_out_facts keeps the category each row had at upload time. This file compares those stored
// rows with the same rows re-parsed from the archived sheets and proposes a category-only change.
// Nothing here writes to BigQuery or Firestore: the plan, its report and the mapping CSV are inputs
// for an owner-approved step (see docs/SELLOUT_CATEGORY_REFRESH_PLAN.md).

// sellOutRevenueTolerance is the per-row net revenue difference still treated as the same value.
const sellOutRevenueTolerance = 0.005

// SellOutCategoryChange is one stored row whose category differs from the re-parsed sheet.
type SellOutCategoryChange struct {
	RecordID    string
	BatchID     string
	Chain       string
	Supplier    string
	IsOwnBrand  bool
	OldCategory string
	NewCategory string
	Quantity    int
	NetRevenue  float64
}

// SellOutCategoryBlock is a stored row the plan refuses to touch, with the reason.
type SellOutCategoryBlock struct {
	RecordID string
	Chain    string
	Reason   string
}

// SellOutCategoryTotal sums one (chain, category, own brand) bucket.
// Year is 0 on the all-years totals and the transaction year on the by-year totals.
type SellOutCategoryTotal struct {
	Chain      string
	Category   string
	IsOwnBrand bool
	Year       int
	Rows       int
	Quantity   int64
	NetRevenue float64
}

// SellOutCategoryRefreshPlan is the read-only result of PlanSellOutCategoryRefresh.
type SellOutCategoryRefreshPlan struct {
	TenantID     string
	StoredRows   int
	ReplayRows   int
	Matched      int
	Unchanged    int
	OnlyStored   int
	OnlyReplay   int
	DuplicateIDs int
	Changes      []SellOutCategoryChange
	Blocked      []SellOutCategoryBlock
	Before       []SellOutCategoryTotal
	After        []SellOutCategoryTotal
	// BeforeByYear / AfterByYear split the same rows by transaction year for Excel checks.
	// Before / After stay the all-years totals the safety checks use.
	BeforeByYear   []SellOutCategoryTotal
	AfterByYear    []SellOutCategoryTotal
	BeforeQuantity int64
	AfterQuantity  int64
	BeforeRevenue  float64
	AfterRevenue   float64
	AfterRows      int
}

func sameSellOutIdentity(stored, replay domain.SellOutFact) string {
	switch {
	case !strings.EqualFold(strings.TrimSpace(stored.RetailerChain), strings.TrimSpace(replay.RetailerChain)):
		return fmt.Sprintf("chain %q != %q", stored.RetailerChain, replay.RetailerChain)
	case strings.TrimSpace(stored.StoreID) != strings.TrimSpace(replay.StoreID):
		return fmt.Sprintf("store %q != %q", stored.StoreID, replay.StoreID)
	case strings.TrimSpace(stored.Supplier) != strings.TrimSpace(replay.Supplier):
		return fmt.Sprintf("supplier %q != %q", stored.Supplier, replay.Supplier)
	case stored.IsOwnBrand != replay.IsOwnBrand:
		return "own-brand flag differs"
	case strings.TrimSpace(stored.Barcode) != strings.TrimSpace(replay.Barcode):
		return fmt.Sprintf("barcode %q != %q", stored.Barcode, replay.Barcode)
	case strings.TrimSpace(stored.TransactionDate) != strings.TrimSpace(replay.TransactionDate):
		return fmt.Sprintf("date %q != %q", stored.TransactionDate, replay.TransactionDate)
	case stored.QuantitySold != replay.QuantitySold:
		return fmt.Sprintf("quantity %d != %d", stored.QuantitySold, replay.QuantitySold)
	case math.Abs(stored.NetRevenue-replay.NetRevenue) > sellOutRevenueTolerance:
		return fmt.Sprintf("net revenue %.2f != %.2f", stored.NetRevenue, replay.NetRevenue)
	}
	return ""
}

// sellOutRecordMatchKey folds the tenant segment of a sell-out record_id so a replay can meet the
// row BigQuery already stores.
//
// Ingest builds record_id as fact_{tenantID}_{chain}_{store}_{supplier}_{barcode}_{date}
// (processor.go) from the tenant string it was given, and the sink writes that string unchanged.
// Rows loaded before the archive tenant was canonical live as fact_adeco_…; a replay is handed the
// archive tenant and builds fact_tenant-adeco_…. The sink's NormalizeTenant strips exactly one
// leading "tenant-" or "tenant_" and lower-cases the slug. This applies that same strip to the
// segment after "fact_" only, so a later segment (a store id, a supplier) is never rewritten and a
// stacked prefix (tenant-tenant-adeco) cannot collapse onto adeco. The mapping CSV keeps the stored
// record_id; this key is for matching only.
func sellOutRecordMatchKey(recordID string) string {
	id := strings.TrimSpace(recordID)
	const prefix = "fact_"
	if len(id) < len(prefix) || !strings.EqualFold(id[:len(prefix)], prefix) {
		return id
	}
	rest := id[len(prefix):]
	tenant, tail := rest, ""
	if i := strings.IndexByte(rest, '_'); i >= 0 {
		tenant, tail = rest[:i], rest[i:]
	}
	tenant = strings.ToLower(tenant)
	switch {
	case strings.HasPrefix(tenant, "tenant-"):
		tenant = strings.TrimPrefix(tenant, "tenant-")
	case strings.HasPrefix(tenant, "tenant_"):
		tenant = strings.TrimPrefix(tenant, "tenant_")
	}
	if tenant == "" {
		tenant = "system"
	}
	return prefix + tenant + tail
}

func sellOutFactYear(f domain.SellOutFact) int {
	d := strings.TrimSpace(f.TransactionDate)
	if len(d) < 4 {
		return 0
	}
	y, err := strconv.Atoi(d[:4])
	if err != nil || y < 2000 || y > 2100 {
		return 0
	}
	return y
}

// PlanSellOutCategoryRefresh compares stored facts (the BigQuery read view) with facts re-parsed from
// the archive and proposes category-only changes keyed by record_id + ingestion batch.
//
// A row changes only when its match key (see sellOutRecordMatchKey) is unique on both sides,
// chain/store/supplier/own-brand/barcode/date and quantity/revenue all match, and the re-parsed
// category is non-empty. Stored rows without a re-parsed twin keep their category; re-parsed rows
// absent from BigQuery are reported, never added. The change list carries the stored record_id.
func PlanSellOutCategoryRefresh(tenantID string, stored, replayed []domain.SellOutFact) *SellOutCategoryRefreshPlan {
	tenant := bqsink.NormalizeTenant(tenantID)
	inTenant := func(f domain.SellOutFact) bool { return bqsink.NormalizeTenant(f.TenantID) == tenant }
	plan := &SellOutCategoryRefreshPlan{TenantID: tenant}

	replayByID := map[string]domain.SellOutFact{}
	replayDup := map[string]bool{}
	for _, f := range replayed {
		if !inTenant(f) {
			continue
		}
		plan.ReplayRows++
		id := sellOutRecordMatchKey(f.RecordID)
		if _, ok := replayByID[id]; ok {
			replayDup[id] = true
		}
		replayByID[id] = f
	}
	storedCount := map[string]int{}
	for _, f := range stored {
		if inTenant(f) {
			storedCount[sellOutRecordMatchKey(f.RecordID)]++
		}
	}

	before := map[string]*SellOutCategoryTotal{}
	after := map[string]*SellOutCategoryTotal{}
	beforeYear := map[string]*SellOutCategoryTotal{}
	afterYear := map[string]*SellOutCategoryTotal{}
	add := func(m map[string]*SellOutCategoryTotal, f domain.SellOutFact, category string, year int) {
		k := strings.ToLower(strings.TrimSpace(f.RetailerChain)) + "|" + category + "|" + strconv.FormatBool(f.IsOwnBrand) + "|" + strconv.Itoa(year)
		t := m[k]
		if t == nil {
			t = &SellOutCategoryTotal{Chain: strings.ToLower(strings.TrimSpace(f.RetailerChain)), Category: category, IsOwnBrand: f.IsOwnBrand, Year: year}
			m[k] = t
		}
		t.Rows++
		t.Quantity += int64(f.QuantitySold)
		t.NetRevenue += f.NetRevenue
	}

	seenReplay := map[string]bool{}
	for _, s := range stored {
		if !inTenant(s) {
			continue
		}
		plan.StoredRows++
		plan.BeforeQuantity += int64(s.QuantitySold)
		plan.BeforeRevenue += s.NetRevenue
		oldCat := strings.TrimSpace(s.Category)
		year := sellOutFactYear(s)
		add(before, s, oldCat, 0)
		add(beforeYear, s, oldCat, year)
		newCat := oldCat

		id := strings.TrimSpace(s.RecordID)
		key := sellOutRecordMatchKey(id)
		r, ok := replayByID[key]
		block := func(reason string) {
			plan.Blocked = append(plan.Blocked, SellOutCategoryBlock{RecordID: id, Chain: s.RetailerChain, Reason: reason})
		}
		switch {
		case id == "":
			block("empty record_id")
		case !ok:
			plan.OnlyStored++
		case replayDup[key] || storedCount[key] > 1:
			seenReplay[key] = true
			plan.DuplicateIDs++
			block("record_id not unique")
		default:
			seenReplay[key] = true
			plan.Matched++
			replayCat := strings.TrimSpace(r.Category)
			if reason := sameSellOutIdentity(s, r); reason != "" {
				block(reason)
			} else if replayCat == "" {
				block("re-parsed category is empty")
			} else if replayCat == oldCat {
				plan.Unchanged++
			} else {
				newCat = replayCat
				plan.Changes = append(plan.Changes, SellOutCategoryChange{
					RecordID: id, BatchID: strings.TrimSpace(s.IngestionBatchID), Chain: s.RetailerChain,
					Supplier: s.Supplier, IsOwnBrand: s.IsOwnBrand, OldCategory: oldCat, NewCategory: replayCat,
					Quantity: s.QuantitySold, NetRevenue: s.NetRevenue,
				})
			}
		}
		plan.AfterRows++
		plan.AfterQuantity += int64(s.QuantitySold)
		plan.AfterRevenue += s.NetRevenue
		add(after, s, newCat, 0)
		add(afterYear, s, newCat, year)
	}
	for id := range replayByID {
		if !seenReplay[id] {
			plan.OnlyReplay++
		}
	}
	plan.Before = sortedCategoryTotals(before)
	plan.After = sortedCategoryTotals(after)
	plan.BeforeByYear = sortedCategoryTotals(beforeYear)
	plan.AfterByYear = sortedCategoryTotals(afterYear)
	sort.Slice(plan.Changes, func(i, j int) bool { return plan.Changes[i].RecordID < plan.Changes[j].RecordID })
	sort.Slice(plan.Blocked, func(i, j int) bool { return plan.Blocked[i].RecordID < plan.Blocked[j].RecordID })
	return plan
}

func sortedCategoryTotals(m map[string]*SellOutCategoryTotal) []SellOutCategoryTotal {
	out := make([]SellOutCategoryTotal, 0, len(m))
	for _, t := range m {
		out = append(out, *t)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Chain != out[j].Chain {
			return out[i].Chain < out[j].Chain
		}
		if out[i].Year != out[j].Year {
			return out[i].Year < out[j].Year
		}
		if out[i].IsOwnBrand != out[j].IsOwnBrand {
			return out[i].IsOwnBrand
		}
		return out[i].Category < out[j].Category
	})
	return out
}

// Violations lists broken safety invariants. A plan with violations must not be executed.
func (p *SellOutCategoryRefreshPlan) Violations() []string {
	var v []string
	if p.AfterRows != p.StoredRows {
		v = append(v, fmt.Sprintf("row count changes: %d -> %d", p.StoredRows, p.AfterRows))
	}
	if p.AfterQuantity != p.BeforeQuantity {
		v = append(v, fmt.Sprintf("quantity SUM changes: %d -> %d", p.BeforeQuantity, p.AfterQuantity))
	}
	if math.Abs(p.AfterRevenue-p.BeforeRevenue) > 0.005 {
		v = append(v, fmt.Sprintf("net revenue SUM changes: %.2f -> %.2f", p.BeforeRevenue, p.AfterRevenue))
	}
	blocked := map[string]bool{}
	for _, b := range p.Blocked {
		blocked[b.RecordID] = true
	}
	seen := map[string]bool{}
	for _, c := range p.Changes {
		key := c.RecordID + "\x00" + c.BatchID
		switch {
		case blocked[c.RecordID]:
			v = append(v, "change on blocked record "+c.RecordID)
		case seen[key]:
			v = append(v, "duplicate change for "+c.RecordID)
		case c.NewCategory == "" || c.NewCategory == c.OldCategory:
			v = append(v, "no-op or empty category change for "+c.RecordID)
		}
		seen[key] = true
	}
	return v
}

// ExpectedCategoryTotal is one reference figure from the client's Excel (kept outside the repo).
// Year 0 means every year. Scope is own (Adeco), competitor, or all.
type ExpectedCategoryTotal struct {
	Chain      string
	Category   string
	Scope      string
	Year       int
	NetRevenue float64
}

func isExpectedHeader(row []string) bool {
	for _, c := range row {
		switch strings.ToLower(strings.TrimSpace(c)) {
		case "chain", "category", "scope", "year", "net_revenue":
			return true
		}
	}
	return false
}

func csvCell(row []string, col map[string]int, name string) string {
	i, ok := col[name]
	if !ok || i >= len(row) {
		return ""
	}
	return row[i]
}

func parseCategoryScope(raw string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "own", "own-brand", "own_brand":
		return "own", nil
	case "competitor", "competitors":
		return "competitor", nil
	case "all":
		return "all", nil
	default:
		return "", fmt.Errorf("scope %q must be own, competitor, or all", raw)
	}
}

func parseCategoryYear(raw string) (int, error) {
	s := strings.ToLower(strings.TrimSpace(raw))
	if s == "" || s == "*" || s == "all" {
		return 0, nil
	}
	y, err := strconv.Atoi(s)
	if err != nil || y < 2000 || y > 2100 {
		return 0, fmt.Errorf("year %q", raw)
	}
	return y, nil
}

// ParseExpectedCategoryCSV reads a reconciliation file.
//
// With a header, columns are named (any order): chain, category, scope, net_revenue, and optional
// year. Without a header, four columns are chain,category,scope,net_revenue (every year) and five
// are chain,category,scope,year,net_revenue. scope is own (Adeco), competitor, or all. year empty,
// * or all means every year. Thousands separators in net_revenue are ignored.
func ParseExpectedCategoryCSV(r io.Reader) ([]ExpectedCategoryTotal, error) {
	cr := csv.NewReader(r)
	cr.TrimLeadingSpace = true
	cr.FieldsPerRecord = -1
	rows, err := cr.ReadAll()
	if err != nil {
		return nil, err
	}
	start := 0
	col := map[string]int{}
	if len(rows) > 0 && isExpectedHeader(rows[0]) {
		for i, h := range rows[0] {
			col[strings.ToLower(strings.TrimSpace(h))] = i
		}
		for _, need := range []string{"chain", "category", "scope", "net_revenue"} {
			if _, ok := col[need]; !ok {
				return nil, fmt.Errorf("header missing %s", need)
			}
		}
		start = 1
	}
	var out []ExpectedCategoryTotal
	for i := start; i < len(rows); i++ {
		row := rows[i]
		if strings.TrimSpace(strings.Join(row, "")) == "" {
			continue
		}
		var chain, category, scopeRaw, yearRaw, revRaw string
		if len(col) > 0 {
			chain, category = csvCell(row, col, "chain"), csvCell(row, col, "category")
			scopeRaw, yearRaw, revRaw = csvCell(row, col, "scope"), csvCell(row, col, "year"), csvCell(row, col, "net_revenue")
		} else {
			if len(row) < 4 {
				return nil, fmt.Errorf("line %d: want chain,category,scope,net_revenue or chain,category,scope,year,net_revenue", i+1)
			}
			chain, category, scopeRaw = row[0], row[1], row[2]
			if len(row) >= 5 {
				yearRaw, revRaw = row[3], row[4]
			} else {
				revRaw = row[3]
			}
		}
		scope, err := parseCategoryScope(scopeRaw)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", i+1, err)
		}
		year, err := parseCategoryYear(yearRaw)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", i+1, err)
		}
		rev, err := strconv.ParseFloat(strings.ReplaceAll(strings.TrimSpace(revRaw), ",", ""), 64)
		if err != nil {
			return nil, fmt.Errorf("line %d: net_revenue %q: %w", i+1, revRaw, err)
		}
		out = append(out, ExpectedCategoryTotal{
			Chain: strings.ToLower(strings.TrimSpace(chain)), Category: strings.TrimSpace(category),
			Scope: scope, Year: year, NetRevenue: rev,
		})
	}
	return out, nil
}

// CategoryReconciliation compares one expected figure with the stored (before) and planned (after) sums.
type CategoryReconciliation struct {
	Expected ExpectedCategoryTotal
	Before   float64
	After    float64
}

// Delta is after minus expected.
func (c CategoryReconciliation) Delta() float64 { return c.After - c.Expected.NetRevenue }

func sumCategory(totals []SellOutCategoryTotal, e ExpectedCategoryTotal) float64 {
	want := domain.NormalizeProductCategory(e.Category)
	var s float64
	for _, t := range totals {
		if e.Year > 0 && t.Year != e.Year {
			continue
		}
		if e.Chain != "" && e.Chain != "*" && t.Chain != e.Chain {
			continue
		}
		switch e.Scope {
		case "own":
			if !t.IsOwnBrand {
				continue
			}
		case "competitor":
			if t.IsOwnBrand {
				continue
			}
		}
		if domain.NormalizeProductCategory(t.Category) == want {
			s += t.NetRevenue
		}
	}
	return s
}

// ReconcileExpected matches expected figures by chain ("*" = all chains), year (0 = every year),
// scope (own / competitor / all) and spelling-normalized category.
func ReconcileExpected(p *SellOutCategoryRefreshPlan, expected []ExpectedCategoryTotal) []CategoryReconciliation {
	out := make([]CategoryReconciliation, 0, len(expected))
	for _, e := range expected {
		before, after := p.Before, p.After
		if e.Year > 0 {
			before, after = p.BeforeByYear, p.AfterByYear
		}
		out = append(out, CategoryReconciliation{Expected: e, Before: sumCategory(before, e), After: sumCategory(after, e)})
	}
	return out
}

// WriteSellOutCategoryMappingCSV writes record_id,ingestion_batch_id,old_category,new_category for the
// approved load step. It holds no quantities or revenue.
func WriteSellOutCategoryMappingCSV(w io.Writer, p *SellOutCategoryRefreshPlan) error {
	cw := csv.NewWriter(w)
	if err := cw.Write([]string{"record_id", "ingestion_batch_id", "old_category", "new_category"}); err != nil {
		return err
	}
	for _, c := range p.Changes {
		if err := cw.Write([]string{c.RecordID, c.BatchID, c.OldCategory, c.NewCategory}); err != nil {
			return err
		}
	}
	cw.Flush()
	return cw.Error()
}

// SellOutCategoryUpdateSQL renders (never runs) the category-only UPDATE for an approved run. Both refs
// are already back-quoted. The old_category guard makes a re-run, or a row changed since the dry run,
// a no-op instead of an overwrite.
func SellOutCategoryUpdateSQL(tableRef, mappingRef string) string {
	return "UPDATE " + tableRef + " t SET category = m.new_category FROM " + mappingRef + " m" +
		" WHERE t.tenant_id = @tenant_id AND t.record_id = m.record_id" +
		" AND IFNULL(t.ingestion_batch_id, '') = m.ingestion_batch_id" +
		" AND IFNULL(t.category, '') = m.old_category"
}

// SellOutCategoryRollbackSQL renders (never runs) the reverse of SellOutCategoryUpdateSQL.
func SellOutCategoryRollbackSQL(tableRef, mappingRef string) string {
	return "UPDATE " + tableRef + " t SET category = m.old_category FROM " + mappingRef + " m" +
		" WHERE t.tenant_id = @tenant_id AND t.record_id = m.record_id" +
		" AND IFNULL(t.ingestion_batch_id, '') = m.ingestion_batch_id" +
		" AND IFNULL(t.category, '') = m.new_category"
}

func sellOutCategoryFocus(category string, focus []string) bool {
	if len(focus) == 0 {
		return true
	}
	c := domain.NormalizeProductCategory(category)
	for _, f := range focus {
		if f = domain.NormalizeProductCategory(f); f != "" && strings.Contains(c, f) {
			return true
		}
	}
	return false
}

// FormatSellOutCategoryRefreshPlan renders the dry-run report. focus limits the per-category tables to
// categories containing one of the given words (spelling-normalized); empty shows all.
func FormatSellOutCategoryRefreshPlan(p *SellOutCategoryRefreshPlan, focus []string, rec []CategoryReconciliation) string {
	var b strings.Builder
	fmt.Fprintf(&b, "=== Sell-Out category refresh DRY RUN tenant=%s (no writes) ===\n", p.TenantID)
	fmt.Fprintf(&b, "stored rows (BigQuery view) %d | re-parsed rows %d | matched %d | unchanged %d | to change %d | blocked %d | only stored %d | only re-parsed %d | duplicate ids %d\n",
		p.StoredRows, p.ReplayRows, p.Matched, p.Unchanged, len(p.Changes), len(p.Blocked), p.OnlyStored, p.OnlyReplay, p.DuplicateIDs)
	fmt.Fprintf(&b, "rows        before %d after %d\n", p.StoredRows, p.AfterRows)
	fmt.Fprintf(&b, "quantity    before %d after %d\n", p.BeforeQuantity, p.AfterQuantity)
	fmt.Fprintf(&b, "net revenue before %.2f after %.2f\n", p.BeforeRevenue, p.AfterRevenue)

	type move struct {
		chain, from, to string
		own             bool
		rows            int
		rev             float64
	}
	moves := map[string]*move{}
	for _, c := range p.Changes {
		if !sellOutCategoryFocus(c.OldCategory, focus) && !sellOutCategoryFocus(c.NewCategory, focus) {
			continue
		}
		k := strings.ToLower(c.Chain) + "|" + c.OldCategory + "|" + c.NewCategory + "|" + strconv.FormatBool(c.IsOwnBrand)
		m := moves[k]
		if m == nil {
			m = &move{chain: strings.ToLower(c.Chain), from: c.OldCategory, to: c.NewCategory, own: c.IsOwnBrand}
			moves[k] = m
		}
		m.rows++
		m.rev += c.NetRevenue
	}
	ml := make([]*move, 0, len(moves))
	for _, m := range moves {
		ml = append(ml, m)
	}
	sort.Slice(ml, func(i, j int) bool {
		if ml[i].chain != ml[j].chain {
			return ml[i].chain < ml[j].chain
		}
		return ml[i].rev > ml[j].rev
	})
	fmt.Fprintf(&b, "\n-- category moves (chain | own | from -> to | rows | net revenue)\n")
	for _, m := range ml {
		fmt.Fprintf(&b, "%-12s %-5v %s -> %s | %d | %.2f\n", m.chain, m.own, m.from, m.to, m.rows, m.rev)
	}

	type pair struct{ before, after SellOutCategoryTotal }
	pairs := map[string]*pair{}
	key := func(t SellOutCategoryTotal) string {
		return t.Chain + "|" + t.Category + "|" + strconv.FormatBool(t.IsOwnBrand)
	}
	for _, t := range p.Before {
		if sellOutCategoryFocus(t.Category, focus) {
			pairs[key(t)] = &pair{before: t, after: SellOutCategoryTotal{Chain: t.Chain, Category: t.Category, IsOwnBrand: t.IsOwnBrand}}
		}
	}
	for _, t := range p.After {
		if !sellOutCategoryFocus(t.Category, focus) {
			continue
		}
		if pr, ok := pairs[key(t)]; ok {
			pr.after = t
		} else {
			pairs[key(t)] = &pair{before: SellOutCategoryTotal{Chain: t.Chain, Category: t.Category, IsOwnBrand: t.IsOwnBrand}, after: t}
		}
	}
	keys := make([]string, 0, len(pairs))
	for k := range pairs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	fmt.Fprintf(&b, "\n-- category totals (chain | own | category | rows before/after | net revenue before/after)\n")
	for _, k := range keys {
		pr := pairs[k]
		fmt.Fprintf(&b, "%-12s %-5v %s | %d / %d | %.2f / %.2f\n", pr.before.Chain, pr.before.IsOwnBrand, pr.before.Category,
			pr.before.Rows, pr.after.Rows, pr.before.NetRevenue, pr.after.NetRevenue)
	}

	if len(rec) > 0 {
		fmt.Fprintf(&b, "\n-- Excel reconciliation (chain | year | scope | category | expected | before | after | after-expected)\n")
		for _, r := range rec {
			year := "*"
			if r.Expected.Year > 0 {
				year = strconv.Itoa(r.Expected.Year)
			}
			fmt.Fprintf(&b, "%-12s %-4s %-10s %s | %.2f | %.2f | %.2f | %+.2f\n", r.Expected.Chain, year, r.Expected.Scope, r.Expected.Category,
				r.Expected.NetRevenue, r.Before, r.After, r.Delta())
		}
	}

	if len(p.Blocked) > 0 {
		reasons := map[string]int{}
		for _, bl := range p.Blocked {
			r := bl.Reason
			if i := strings.IndexAny(r, "\"0123456789"); i > 0 {
				r = strings.TrimSpace(r[:i])
			}
			reasons[r]++
		}
		rk := make([]string, 0, len(reasons))
		for r := range reasons {
			rk = append(rk, r)
		}
		sort.Strings(rk)
		fmt.Fprintf(&b, "\n-- blocked rows by reason (kept as stored)\n")
		for _, r := range rk {
			fmt.Fprintf(&b, "%s: %d\n", r, reasons[r])
		}
	}

	if v := p.Violations(); len(v) > 0 {
		fmt.Fprintf(&b, "\nRESULT: UNSAFE (%d invariant violation(s))\n", len(v))
		for _, s := range v {
			fmt.Fprintf(&b, "  %s\n", s)
		}
	} else {
		fmt.Fprintf(&b, "\nRESULT: SAFE (row count, quantity and net revenue unchanged; category column only)\n")
	}
	return b.String()
}

// SelectSellOutArchivesForCategoryReplay keeps Product Master catalogs (blank-cell fallback) and the
// Sell-Out archives BigQuery stores rows for (by archive id, or by file name for legacy rows). Files
// deleted by a user have no stored rows, so a replay without the Firestore tombstones still skips them.
func SelectSellOutArchivesForCategoryReplay(all []*ArchivedFile, tenantID string, stored []bqsink.ArchiveRows) []*ArchivedFile {
	tenant := normalizeArchiveTenantID(tenantID)
	ids := map[string]bool{}
	files := map[string]bool{}
	for _, s := range stored {
		if s.Kind != bqsink.KindSellOut || s.Rows == 0 {
			continue
		}
		if s.ArchiveID != "" {
			ids[s.ArchiveID] = true
		} else if s.SourceFile != "" {
			files[strings.ToLower(s.SourceFile)] = true
		}
	}
	var out []*ArchivedFile
	for _, e := range all {
		if e == nil || e.TenantID != tenant {
			continue
		}
		switch {
		case isProductMasterArchiveEntry(e):
			out = append(out, e)
		case isSellInArchiveEntry(e):
		case ids[e.ID] || files[strings.ToLower(e.FileName)]:
			out = append(out, e)
		}
	}
	sortArchiveReplayOrder(out)
	return out
}

// ReplaySellOutArchivesForCategoryPlan re-parses the selected archives into this processor's in-memory
// stores only (replay mode: no sink writes, no Gemini). Use a processor built on mock Firestore and an
// in-memory BigQuery client with no sink attached.
func (p *Processor) ReplaySellOutArchivesForCategoryPlan(ctx context.Context, tenantID string, stored []bqsink.ArchiveRows) []*ArchivedFile {
	p.replaying.Store(true)
	defer p.replaying.Store(false)
	p.archiveMu.Lock()
	p.loadDiskArchiveLocked()
	all := make([]*ArchivedFile, 0, len(p.archivedFiles))
	for _, e := range p.archivedFiles {
		all = append(all, e)
	}
	p.archiveMu.Unlock()
	files := SelectSellOutArchivesForCategoryReplay(all, tenantID, stored)
	p.replayFiles(ctx, files, false)
	return files
}

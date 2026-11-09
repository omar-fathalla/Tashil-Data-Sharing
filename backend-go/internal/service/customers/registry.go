// Package customers keeps the Sell-In customer registry.
//
// TOP RULE: one customer's data is never attributed to another customer. A Sell-In row is counted
// only when its customer name matches, after deterministic normalization, a name that is already
// approved (seeded from the data served before this registry existed, or approved by an admin).
// Anything else is quarantined: excluded from every total, kept recoverable in the archived file,
// and listed as pending with a suggested match. Suggestions (similar names, same family prefix) are
// only shown to the admin; they never attach rows by themselves.
package customers

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

const (
	StatusApproved = "approved"
	StatusPending  = "pending"
	StatusRejected = "rejected"
)

//go:embed seed_customers.json
var seedJSON []byte

// seed_aliases.json maps a customer name as written by the gp_sop_export branch-label fix (new) to
// the approved seed name already stored in BigQuery (old), e.g. "زهران - البيطاش" ->
// "فرع فتح الله - زهران - البيطاش". Exact (normalized) match only; generated from ITEM7_84.csv.
//
//go:embed seed_aliases.json
var seedAliasesJSON []byte

// MonthStat is the quarantined share of one file in one month.
type MonthStat struct {
	Rows  int     `json:"rows" firestore:"rows"`
	Value float64 `json:"value" firestore:"value"`
}

// Supersession records that a later upload replaced one month of a quarantined file (kept for
// traceability; never deleted, so it can be restored).
type Supersession struct {
	Month string    `json:"month" firestore:"month"`
	By    string    `json:"superseded_by" firestore:"superseded_by"`
	At    time.Time `json:"superseded_at" firestore:"superseded_at"`
}

// FileStat is the quarantined share of one uploaded file for one customer name.
type FileStat struct {
	File       string               `json:"file" firestore:"file"`
	Chain      string               `json:"chain,omitempty" firestore:"chain"` // stored chain of the rows at upload time
	Rows       int                  `json:"rows" firestore:"rows"`
	Value      float64              `json:"value" firestore:"value"`
	Units      float64              `json:"units" firestore:"units"`
	Months     []string             `json:"months" firestore:"months"`
	ByMonth    map[string]MonthStat `json:"by_month,omitempty" firestore:"by_month"`
	Superseded []Supersession       `json:"superseded,omitempty" firestore:"superseded"`
	SeenAt     time.Time            `json:"seen_at" firestore:"seen_at"`
}

// IsSuperseded reports whether month m of this file was replaced by a later confirmed upload.
func (f FileStat) IsSuperseded(m string) bool {
	for _, s := range f.Superseded {
		if s.Month == m {
			return true
		}
	}
	return false
}

// Live is false when every month of the file was superseded (the file must not be re-applied).
func (f FileStat) Live() bool {
	for _, m := range f.Months {
		if !f.IsSuperseded(m) {
			return true
		}
	}
	return len(f.Months) == 0
}

// Entry is one customer name known to the registry.
type Entry struct {
	Name             string     `json:"name" firestore:"name"`
	Key              string     `json:"key" firestore:"key"`
	Status           string     `json:"status" firestore:"status"`
	Chain            string     `json:"chain,omitempty" firestore:"chain"` // explicit chain chosen on approval ("" = upload chain + chain rules)
	AliasOf          string     `json:"alias_of,omitempty" firestore:"alias_of"`
	Seeded           bool       `json:"seeded,omitempty" firestore:"seeded"`
	SuggestedName    string     `json:"suggested_name,omitempty" firestore:"suggested_name"`
	SuggestedChain   string     `json:"suggested_chain,omitempty" firestore:"suggested_chain"`
	SuggestionReason string     `json:"suggestion_reason,omitempty" firestore:"suggestion_reason"`
	ParentCustomer   string     `json:"parent_customer,omitempty" firestore:"parent_customer"`
	BranchCode       string     `json:"branch_code,omitempty" firestore:"branch_code"`
	UploadChain      string     `json:"upload_chain,omitempty" firestore:"upload_chain"`
	FirstSeenFile    string     `json:"first_seen_file,omitempty" firestore:"first_seen_file"`
	Quarantine       []FileStat `json:"quarantine,omitempty" firestore:"quarantine"`
	FirstSeenAt      time.Time  `json:"first_seen_at" firestore:"first_seen_at"`
	UpdatedAt        time.Time  `json:"updated_at" firestore:"updated_at"`
	DecidedBy        string     `json:"decided_by,omitempty" firestore:"decided_by"`
	DecidedAt        *time.Time `json:"decided_at,omitempty" firestore:"decided_at"`
}

// QuarantinedRows / Value / Units / Months summarize the entry's quarantine across files.
func (e Entry) Totals() (rows int, value, units float64, months []string, files []string) {
	ms := map[string]bool{}
	for _, f := range e.Quarantine {
		rows += f.Rows
		value += f.Value
		units += f.Units
		files = append(files, f.File)
		for _, m := range f.Months {
			ms[m] = true
		}
	}
	for m := range ms {
		months = append(months, m)
	}
	sort.Strings(months)
	return
}

// State is the persisted registry of one tenant (seed names are not stored; they are embedded).
type State struct {
	TenantID  string    `json:"tenant_id" firestore:"tenant_id"`
	Entries   []Entry   `json:"entries" firestore:"entries"`
	UpdatedAt time.Time `json:"updated_at" firestore:"updated_at"`
}

// Store persists the registry (Firestore in production, in-memory otherwise).
type Store interface {
	GetCustomerRegistry(ctx context.Context, tenantID string) (*State, error)
	SaveCustomerRegistry(ctx context.Context, s *State) error
}

// MemoryStore is the fallback store.
type MemoryStore struct {
	mu sync.Mutex
	m  map[string]State
}

func (m *MemoryStore) GetCustomerRegistry(_ context.Context, tenantID string) (*State, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.m[tenantID]
	if !ok {
		return &State{TenantID: tenantID}, nil
	}
	cp := s
	cp.Entries = append([]Entry(nil), s.Entries...)
	return &cp, nil
}

func (m *MemoryStore) SaveCustomerRegistry(_ context.Context, s *State) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.m == nil {
		m.m = map[string]State{}
	}
	cp := *s
	cp.Entries = append([]Entry(nil), s.Entries...)
	m.m[s.TenantID] = cp
	return nil
}

// NormalizeName is the only transformation allowed before an exact match: Arabic letter variants
// (أ إ آ → ا, ة → ه, ى → ي), tatweel, Arabic/Latin digits, dash spacing and repeated spaces.
func NormalizeName(s string) string {
	s = strings.NewReplacer("أ", "ا", "إ", "ا", "آ", "ا", "ة", "ه", "ى", "ي", "ـ", "", "–", "-", "—", "-").Replace(s)
	var b strings.Builder
	for _, r := range s {
		if r >= '٠' && r <= '٩' {
			r = '0' + (r - '٠')
		}
		b.WriteRune(unicode.ToLower(r))
	}
	s = strings.ReplaceAll(b.String(), "-", " - ")
	return strings.Join(strings.Fields(s), " ")
}

// Registry resolves customer names to approved entries.
type Registry struct {
	mu    sync.Mutex
	store Store
	ttl   time.Duration
	seed  map[string]string // key -> seed name
	alias map[string]string // key of a new spelling -> seed name it permanently maps to
	cache map[string]*tenantCache
	now   func() time.Time
	// SeedTenants are the tenants whose served data the embedded seed describes.
	SeedTenants map[string]bool
	// ChainOf returns the chain a row is stored under (set by the ingestion processor); nil = RetailerChain.
	ChainOf func(domain.SellInRecord) string
}

// ChainOfName is the stored chain of a row with this customer name uploaded under chain.
func (r *Registry) ChainOfName(name, chain string) string {
	return r.chainOf(domain.SellInRecord{CustomerName: name, RetailerChain: chain})
}

func (r *Registry) chainOf(rec domain.SellInRecord) string {
	if r.ChainOf != nil {
		return r.ChainOf(rec)
	}
	return strings.ToLower(strings.TrimSpace(rec.RetailerChain))
}

type tenantCache struct {
	loaded time.Time
	state  *State
}

// New returns a registry backed by store (nil → in-memory).
func New(store Store) *Registry {
	if store == nil {
		store = &MemoryStore{}
	}
	r := &Registry{store: store, ttl: time.Minute, seed: map[string]string{}, cache: map[string]*tenantCache{}, now: time.Now,
		SeedTenants: map[string]bool{"tenant-adeco": true}}
	var names []string
	_ = json.Unmarshal(seedJSON, &names)
	for _, n := range names {
		r.seed[NormalizeName(n)] = n
	}
	var aliases map[string]string
	_ = json.Unmarshal(seedAliasesJSON, &aliases)
	r.alias = make(map[string]string, len(aliases))
	for from, to := range aliases {
		if _, ok := r.seed[NormalizeName(to)]; ok {
			r.alias[NormalizeName(from)] = to
		}
	}
	return r
}

// SeedCustomerNames returns the embedded Adeco Sell-In seed customer names (read-only).
func SeedCustomerNames() []string {
	var names []string
	_ = json.Unmarshal(seedJSON, &names)
	return names
}

// SeedAliasPairs returns embedded permanent alias from→to spellings (read-only).
func SeedAliasPairs() map[string]string {
	var aliases map[string]string
	_ = json.Unmarshal(seedAliasesJSON, &aliases)
	if aliases == nil {
		return map[string]string{}
	}
	return aliases
}

// AliasCount is the number of embedded permanent aliases.
func (r *Registry) AliasCount() int { return len(r.alias) }

// SeedCount is the number of embedded approved names.
func (r *Registry) SeedCount() int { return len(r.seed) }

func (r *Registry) stateLocked(ctx context.Context, tenantID string) *State {
	if c, ok := r.cache[tenantID]; ok && r.now().Sub(c.loaded) < r.ttl {
		return c.state
	}
	st, err := r.store.GetCustomerRegistry(ctx, tenantID)
	if err != nil || st == nil {
		if c, ok := r.cache[tenantID]; ok {
			return c.state // keep the last good copy; seed names still apply
		}
		st = &State{TenantID: tenantID}
	}
	st.TenantID = tenantID
	r.cache[tenantID] = &tenantCache{loaded: r.now(), state: st}
	return st
}

func findEntry(st *State, key string) int {
	for i := range st.Entries {
		if st.Entries[i].Key == key {
			return i
		}
	}
	return -1
}

// resolveLocked: (entry, approved). Stored decisions win over the seed (so a seeded name can be unmerged).
func (r *Registry) resolveLocked(st *State, tenantID, key string) (*Entry, bool) {
	if i := findEntry(st, key); i >= 0 {
		e := &st.Entries[i]
		return e, e.Status == StatusApproved
	}
	if r.seedApplies(tenantID) {
		if n, ok := r.seed[key]; ok {
			return &Entry{Name: n, Key: key, Status: StatusApproved, Seeded: true}, true
		}
	}
	return nil, false
}

// QuarantinedCustomer is reported to the uploader.
type QuarantinedCustomer struct {
	Name             string   `json:"name"`
	Rows             int      `json:"rows"`
	Value            float64  `json:"value"`
	Units            float64  `json:"units"`
	Months           []string `json:"months"`
	Status           string   `json:"status"`
	SuggestedName    string   `json:"suggested_name,omitempty"`
	SuggestedChain   string   `json:"suggested_chain,omitempty"`
	SuggestionReason string   `json:"suggestion_reason,omitempty"`
}

// Partition splits Sell-In records into counted rows and quarantined rows. Rows without a customer
// name keep the upload chain (there is nothing to attribute). Approved entries with an explicit chain
// move the row to that chain. Unknown names become pending entries; persist=false (dry run) reports
// without saving.
func (r *Registry) Partition(ctx context.Context, tenantID, filename, uploadChain string, records []domain.SellInRecord, persist bool) ([]domain.SellInRecord, []QuarantinedCustomer) {
	return r.PartitionLayout(ctx, tenantID, filename, uploadChain, "", records, persist)
}

// AliasLayout is the only parse layout whose customer names may be mapped by seed_aliases.json.
const AliasLayout = "gp_sop_export"

// AliasChain is the only upload chain whose rows may be mapped by seed_aliases.json.
const AliasChain = "fathalla"

// aliasApplies: the item-7 aliases rename «زهران - …» / «كيه اتش …» rows to the Fathalla distributor's
// «فرع فتح الله - …» customer, so they apply ONLY to a fathalla upload parsed as gp_sop_export (where
// those names are Fathalla's own branch labels). A Zahran or Gomla upload with the same name is never
// aliased and goes through the normal approval check (TOP RULE: never attribute one customer's data to another).
//
// The raw upload chain is NOT compared: the parser normalizes it ("", "all", «فتح الله», "Fathalla
// Market" -> fathalla), so the gate is the row's normalized RetailerChain, checked per row.
func (r *Registry) aliasApplies(tenantID, layout string) bool {
	return layout == AliasLayout && r.seedApplies(tenantID)
}

// PartitionLayout is Partition with the parse layout of the file (needed for the item-7 aliases;
// "" = no aliases).
func (r *Registry) PartitionLayout(ctx context.Context, tenantID, filename, uploadChain, layout string, records []domain.SellInRecord, persist bool) ([]domain.SellInRecord, []QuarantinedCustomer) {
	r.mu.Lock()
	defer r.mu.Unlock()
	st := r.stateLocked(ctx, tenantID)
	kept := records[:0:0]
	type agg struct {
		q      QuarantinedCustomer
		months map[string]bool
		by     map[string]MonthStat
		chain  string
		parent string
		branch string
	}
	held := map[string]*agg{}
	var order []string
	useAlias := r.aliasApplies(tenantID, layout)
	for _, rec := range records {
		name := strings.TrimSpace(rec.CustomerName)
		if name == "" {
			kept = append(kept, rec)
			continue
		}
		key := NormalizeName(name)
		if old, ok := r.alias[key]; ok && useAlias && strings.EqualFold(strings.TrimSpace(rec.RetailerChain), AliasChain) {
			// Permanent alias: the row keeps the stored seed name, and any decision on that name wins.
			name, key = old, NormalizeName(old)
			rec.CustomerName = old
		}
		e, ok := r.resolveLocked(st, tenantID, key)
		if ok {
			if e.Chain != "" {
				rec.RetailerChain = e.Chain
			}
			kept = append(kept, rec)
			continue
		}
		a := held[key]
		if a == nil {
			a = &agg{q: QuarantinedCustomer{Name: name, Status: StatusPending}, months: map[string]bool{}, by: map[string]MonthStat{},
				chain: r.chainOf(rec), parent: rec.ParentCustomer, branch: rec.CustomerBranchCode}
			if e != nil {
				a.q.Status = e.Status
			}
			held[key] = a
			order = append(order, key)
		}
		a.q.Rows++
		a.q.Value += rec.NetValueEGP
		a.q.Units += rec.NetQtyCases
		mk := fmt.Sprintf("%04d-%02d", rec.Year, rec.MonthNum)
		a.months[mk] = true
		ms := a.by[mk]
		ms.Rows++
		ms.Value = round2(ms.Value + rec.NetValueEGP)
		a.by[mk] = ms
	}
	if len(held) == 0 {
		// A file whose names are now all approved clears its old quarantine stats.
		if persist && clearFileLocked(st, filename) {
			r.saveLocked(ctx, st)
		}
		return kept, nil
	}
	now := r.now().UTC()
	approved := r.approvedNamesLocked(st, tenantID)
	out := make([]QuarantinedCustomer, 0, len(held))
	changed := clearFileLocked(st, filename)
	for _, key := range order {
		a := held[key]
		for m := range a.months {
			a.q.Months = append(a.q.Months, m)
		}
		sort.Strings(a.q.Months)
		sug := Suggest(a.q.Name, bigquery.ResolveSellInChain(a.q.Name, uploadChain), approved)
		a.q.SuggestedName, a.q.SuggestedChain, a.q.SuggestionReason = sug.Name, sug.Chain, sug.Reason
		a.q.Value = round2(a.q.Value)
		a.q.Units = round2(a.q.Units)
		out = append(out, a.q)
		i := findEntry(st, key)
		if i < 0 {
			st.Entries = append(st.Entries, Entry{Name: a.q.Name, Key: key, Status: StatusPending, FirstSeenFile: filename, FirstSeenAt: now,
				ParentCustomer: a.parent, BranchCode: a.branch, UploadChain: uploadChain})
			i = len(st.Entries) - 1
		}
		e := &st.Entries[i]
		e.SuggestedName, e.SuggestedChain, e.SuggestionReason = sug.Name, sug.Chain, sug.Reason
		e.Quarantine = append(e.Quarantine, FileStat{File: filename, Chain: a.chain, Rows: a.q.Rows, Value: a.q.Value, Units: a.q.Units, Months: a.q.Months, ByMonth: a.by, SeenAt: now})
		e.UpdatedAt = now
		changed = true
	}
	if persist && changed {
		r.saveLocked(ctx, st)
	} else if !persist {
		delete(r.cache, tenantID) // a dry run must not leave pending entries behind
	}
	return kept, out
}

func clearFileLocked(st *State, filename string) bool {
	changed := false
	for i := range st.Entries {
		q := st.Entries[i].Quarantine[:0]
		for _, f := range st.Entries[i].Quarantine {
			if f.File == filename {
				changed = true
				continue
			}
			q = append(q, f)
		}
		st.Entries[i].Quarantine = q
	}
	return changed
}

// QuarantinedByChainMonth sums the live quarantined rows of pending/approved names per
// "chain|YYYY-MM", excluding one file (the file being uploaded) and superseded months.
func (r *Registry) QuarantinedByChainMonth(ctx context.Context, tenantID, excludeFile string) map[string]MonthStat {
	r.mu.Lock()
	defer r.mu.Unlock()
	st := r.stateLocked(ctx, tenantID)
	out := map[string]MonthStat{}
	for _, e := range st.Entries {
		if e.Status != StatusPending && e.Status != StatusApproved {
			continue
		}
		for _, f := range e.Quarantine {
			if strings.EqualFold(strings.TrimSpace(f.File), strings.TrimSpace(excludeFile)) || f.Chain == "" {
				continue
			}
			for m, ms := range f.ByMonth {
				if f.IsSuperseded(m) {
					continue
				}
				k := f.Chain + "|" + m
				cur := out[k]
				cur.Rows += ms.Rows
				cur.Value = round2(cur.Value + ms.Value)
				out[k] = cur
			}
		}
	}
	return out
}

// SupersedeMonths marks the quarantine stats of other files on the given "chain|YYYY-MM" keys as
// superseded by byFile (the user confirmed the replacement). Nothing is deleted. Returns the count.
func (r *Registry) SupersedeMonths(ctx context.Context, tenantID, byFile string, keys map[string]bool) int {
	if len(keys) == 0 {
		return 0
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	st := r.stateLocked(ctx, tenantID)
	n := clearFileMonthsLocked(st, byFile, keys, r.now().UTC())
	if n > 0 {
		r.saveLocked(ctx, st)
	}
	return n
}

// clearFileMonthsLocked marks (never removes) the replaced months of other files' quarantine stats.
func clearFileMonthsLocked(st *State, byFile string, keys map[string]bool, at time.Time) int {
	n := 0
	for i := range st.Entries {
		for j := range st.Entries[i].Quarantine {
			f := &st.Entries[i].Quarantine[j]
			if strings.EqualFold(strings.TrimSpace(f.File), strings.TrimSpace(byFile)) {
				continue
			}
			for _, m := range f.Months {
				if keys[f.Chain+"|"+m] && !f.IsSuperseded(m) {
					f.Superseded = append(f.Superseded, Supersession{Month: m, By: byFile, At: at})
					n++
				}
			}
		}
	}
	return n
}

func (r *Registry) saveLocked(ctx context.Context, st *State) {
	st.UpdatedAt = r.now().UTC()
	_ = r.store.SaveCustomerRegistry(ctx, st)
}

func (r *Registry) approvedNamesLocked(st *State, tenantID string) []Entry {
	var out []Entry
	seen := map[string]bool{}
	for _, e := range st.Entries {
		seen[e.Key] = true
		if e.Status == StatusApproved {
			out = append(out, e)
		}
	}
	if r.seedApplies(tenantID) {
		for k, n := range r.seed {
			if !seen[k] {
				out = append(out, Entry{Name: n, Key: k, Status: StatusApproved, Seeded: true})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key < out[j].Key })
	return out
}

// List returns stored entries (pending, approved by admin, rejected) plus, when includeSeed, the seed.
func (r *Registry) List(ctx context.Context, tenantID, status string, includeSeed bool) []Entry {
	r.mu.Lock()
	defer r.mu.Unlock()
	st := r.stateLocked(ctx, tenantID)
	var out []Entry
	for _, e := range st.Entries {
		if status == "" || e.Status == status {
			out = append(out, e)
		}
	}
	if includeSeed && (status == "" || status == StatusApproved) && r.seedApplies(tenantID) {
		for k, n := range r.seed {
			if findEntry(st, k) < 0 {
				out = append(out, Entry{Name: n, Key: k, Status: StatusApproved, Seeded: true})
			}
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Status != out[j].Status {
			return out[i].Status == StatusPending
		}
		return out[i].Name < out[j].Name
	})
	return out
}

// Decide sets the status of a name. For approval, chain may be "" (keep upload chain and chain
// rules) and aliasOf may name the approved customer this spelling belongs to (logged, reversible).
func (r *Registry) Decide(ctx context.Context, tenantID, name, status, chain, aliasOf, by string) (*Entry, error) {
	if status != StatusApproved && status != StatusRejected && status != StatusPending {
		return nil, fmt.Errorf("invalid status %q", status)
	}
	key := NormalizeName(name)
	if key == "" {
		return nil, fmt.Errorf("اسم العميل فاضي")
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.cache, tenantID) // always decide on the freshest copy
	st := r.stateLocked(ctx, tenantID)
	i := findEntry(st, key)
	if i < 0 {
		e := Entry{Name: strings.TrimSpace(name), Key: key, FirstSeenAt: r.now().UTC()}
		if n, ok := r.seed[key]; ok && r.seedApplies(tenantID) {
			e.Name, e.Seeded = n, true
		}
		st.Entries = append(st.Entries, e)
		i = len(st.Entries) - 1
	}
	now := r.now().UTC()
	e := &st.Entries[i]
	e.Status = status
	e.Chain = strings.ToLower(strings.TrimSpace(chain))
	e.AliasOf = strings.TrimSpace(aliasOf)
	if status != StatusApproved {
		e.Chain, e.AliasOf = "", ""
	}
	e.DecidedBy, e.DecidedAt, e.UpdatedAt = by, &now, now
	cp := *e
	st.UpdatedAt = now
	if err := r.store.SaveCustomerRegistry(ctx, st); err != nil {
		delete(r.cache, tenantID)
		return nil, err
	}
	return &cp, nil
}

func round2(f float64) float64 {
	if f < 0 {
		return -float64(int64(-f*100+0.5)) / 100
	}
	return float64(int64(f*100+0.5)) / 100
}

// seedApplies reports whether the embedded seed describes this tenant ("adeco", "tenant-adeco", "tenant_adeco" are one tenant).
func (r *Registry) seedApplies(tenantID string) bool {
	slug := strings.ToLower(strings.TrimSpace(tenantID))
	slug = strings.TrimPrefix(strings.TrimPrefix(slug, "tenant-"), "tenant_")
	for t := range r.SeedTenants {
		s := strings.TrimPrefix(strings.TrimPrefix(strings.ToLower(t), "tenant-"), "tenant_")
		if s == slug && s != "" {
			return true
		}
	}
	return false
}

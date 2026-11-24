package bigquery

import (
	"strings"
	"unicode"

	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Derived Sell-In target branches are Sell-Out stores (store_id such as fat_smouha, display name
// «فرع فتح الله - سموحة»). Sell-In rows almost never carry that id: supplier plan files invoice the
// chain's legal entity with the chain's ERP branch code (311350147, ALX-04058-0044 # 1) or the regional
// bucket «مجمع الإقليم (Regional)», and GP SOP files carry a store id built from the customer name.
// Branch actuals are therefore attributed in two steps:
//
//  1. direct: the row's customer code / name resolves to the branch's canonical store id (same id, the
//     chain branch catalog's ERP code, or the branch label of the customer name);
//  2. allocated: every other row is split over the target's branches of the row's region (all branches
//     when the region has none), weighted by each branch's target pieces of the row's SKU, else by the
//     branch's total target pieces. Branch actuals then add up to the target's actuals.

const derivedBranchSlugCacheMax = 8192

// derivedBranchSlug is the canonical store id of a branch label (gemini.BuildBranchStoreMetadata, the
// same id Sell-Out uploads give the store). Memoized: labels repeat across rows, targets and reads.
func (c *Client) derivedBranchSlug(chain, label string) string {
	label = strings.TrimSpace(label)
	if label == "" {
		return ""
	}
	key := chain + "\x1f" + label
	c.derivedSI.mu.Lock()
	if v, ok := c.derivedSI.slugs[key]; ok {
		c.derivedSI.mu.Unlock()
		return v
	}
	c.derivedSI.mu.Unlock()
	id := strings.ToLower(gemini.BuildBranchStoreMetadata(chain, label).ID)
	c.derivedSI.mu.Lock()
	if c.derivedSI.slugs == nil || len(c.derivedSI.slugs) >= derivedBranchSlugCacheMax {
		c.derivedSI.slugs = make(map[string]string)
	}
	c.derivedSI.slugs[key] = id
	c.derivedSI.mu.Unlock()
	return id
}

// derivedKnownBranchGovernorate is the governorate of a branch label known to the store catalog
// (empty for auto-created stores, whose governorate is only a default).
func derivedKnownBranchGovernorate(chain, label string) string {
	label = strings.TrimSpace(label)
	if label == "" {
		return ""
	}
	st := gemini.BuildBranchStoreMetadata(chain, label)
	if strings.Contains(st.ID, "_auto_") {
		return ""
	}
	return st.Governorate
}

// derivedChainCatalog returns the chain's ERP branch catalog (codes used by Sell-In plan files).
func derivedChainCatalog(chain string) []chainBranchTemplate {
	switch strings.ToLower(strings.TrimSpace(chain)) {
	case "fathalla", "gomla", "beet-elgomla", "beet_elgomla", "chain-1080314":
		return defaultChainBranchCatalog(chain)
	}
	return nil
}

// derivedBranchCodeKeys normalizes a branch code: lower-cased, without a "# n" suffix, plus the bare
// number of a region-prefixed code (ALX-311350894 → 311350894).
func derivedBranchCodeKeys(code string) []string {
	s := strings.ToLower(strings.TrimSpace(code))
	if i := strings.Index(s, "#"); i >= 0 {
		s = strings.TrimSpace(s[:i])
	}
	if s == "" {
		return nil
	}
	keys := []string{"code:" + s}
	if i := strings.Index(s, "-"); i > 0 {
		rest := s[i+1:]
		if rest != "" && strings.IndexFunc(rest, func(r rune) bool { return !unicode.IsDigit(r) }) < 0 {
			keys = append(keys, "code:"+rest)
		}
	}
	return keys
}

func derivedRegionKey(region, governorate string) string {
	if r := strings.ToUpper(strings.TrimSpace(region)); r != "" {
		return r
	}
	if g := normalizeArabicNameForLookup(governorate); g != "" {
		return "gov:" + g
	}
	return ""
}

// derivedBranchAttr attributes the Sell-In rows of one derived target to its branches.
type derivedBranchAttr struct {
	c        *Client
	chain    string
	branches []*derivedBranchAgg
	ids      map[string]int // canonical store id / catalog code → branch index
	region   []string       // branch index → region key ("" = unknown)
	byRegion map[string][]int
	all      []int
	direct   map[string]int // row chain|code|name → branch index (-1 = none)
	weights  map[string][]float64
}

func (c *Client) newDerivedBranchAttr(chain string, branches []*derivedBranchAgg, rows []*derivedSellInRow) *derivedBranchAttr {
	a := &derivedBranchAttr{
		c: c, chain: chain, branches: branches,
		ids:      map[string]int{},
		region:   make([]string, len(branches)),
		byRegion: map[string][]int{},
		direct:   map[string]int{},
		weights:  map[string][]float64{},
	}
	if len(branches) == 0 {
		return a
	}
	slugChain := chain
	if slugChain == "" {
		slugChain = "fathalla"
	}
	put := func(id string, idx int) {
		if id == "" {
			return
		}
		if _, taken := a.ids[id]; !taken {
			a.ids[id] = idx
		}
	}
	for i, b := range branches {
		a.all = append(a.all, i)
		put("id:"+strings.ToLower(strings.TrimSpace(b.key)), i)
		put("id:"+c.derivedBranchSlug(slugChain, b.name), i)
	}
	for _, e := range derivedChainCatalog(chain) {
		idx, ok := a.ids["id:"+c.derivedBranchSlug(slugChain, e.Name)]
		if !ok {
			continue
		}
		for _, k := range derivedBranchCodeKeys(e.Code) {
			put(k, idx)
		}
		if a.region[idx] == "" {
			a.region[idx] = derivedRegionKey(e.RegionCode, e.Governorate)
		}
	}

	// Branches the catalog does not place take the region of their direct rows, else the region the
	// Sell-In rows use for the branch's known governorate.
	regionVotes := make([]map[string]int, len(branches))
	govVotes := map[string]map[string]int{}
	for _, r := range rows {
		rk := derivedRegionKey(r.region, r.governorate)
		if g := normalizeArabicNameForLookup(r.governorate); g != "" && rk != "" {
			if govVotes[g] == nil {
				govVotes[g] = map[string]int{}
			}
			govVotes[g][rk]++
		}
		if idx := a.directIndex(r); idx >= 0 && rk != "" && a.region[idx] == "" {
			if regionVotes[idx] == nil {
				regionVotes[idx] = map[string]int{}
			}
			regionVotes[idx][rk]++
		}
	}
	for i, b := range branches {
		if a.region[i] != "" {
			continue
		}
		if rk := topVote(regionVotes[i]); rk != "" {
			a.region[i] = rk
			continue
		}
		if g := normalizeArabicNameForLookup(derivedKnownBranchGovernorate(slugChain, b.name)); g != "" {
			if rk := topVote(govVotes[g]); rk != "" {
				a.region[i] = rk
			}
		}
	}
	for i, rk := range a.region {
		if rk != "" {
			a.byRegion[rk] = append(a.byRegion[rk], i)
		}
	}
	return a
}

func topVote(votes map[string]int) string {
	best, n := "", 0
	for k, v := range votes {
		if v > n || (v == n && k < best) {
			best, n = k, v
		}
	}
	return best
}

// regionCode is the region code of a branch ("" when unknown or only a governorate).
func (a *derivedBranchAttr) regionCode(i int) string {
	if i < 0 || i >= len(a.region) || strings.HasPrefix(a.region[i], "gov:") {
		return ""
	}
	return a.region[i]
}

// rowIDs lists the canonical ids a Sell-In row may name its branch by.
func (a *derivedBranchAttr) rowIDs(r *derivedSellInRow) []string {
	chain := r.chain
	if chain == "" {
		chain = a.chain
	}
	var ids []string
	if code := strings.TrimSpace(r.customerCode); code != "" {
		ids = append(ids, "id:"+code)
		ids = append(ids, derivedBranchCodeKeys(code)...)
		ids = append(ids, "id:"+a.c.derivedBranchSlug(chain, code))
	}
	if name := strings.TrimSpace(r.customerName); name != "" {
		ids = append(ids, "id:"+a.c.derivedBranchSlug(chain, name))
		if _, branch := gemini.ParseChainBranchCell(name); branch != "" && branch != name {
			ids = append(ids, "id:"+a.c.derivedBranchSlug(chain, branch))
		}
	}
	return ids
}

// directIndex returns the branch a row names directly, or -1.
func (a *derivedBranchAttr) directIndex(r *derivedSellInRow) int {
	if len(a.branches) == 0 {
		return -1
	}
	key := r.chain + "\x1f" + r.customerCode + "\x1f" + r.customerName
	if idx, ok := a.direct[key]; ok {
		return idx
	}
	idx := -1
	for _, id := range a.rowIDs(r) {
		if i, ok := a.ids[id]; ok {
			idx = i
			break
		}
	}
	a.direct[key] = idx
	return idx
}

// shares splits a row that names no branch over the branches of its region (all branches when the
// region has none) by target pieces of the row's SKU, else by total target pieces. nil = no branch.
func (a *derivedBranchAttr) shares(r *derivedSellInRow) []float64 {
	rk := derivedRegionKey(r.region, r.governorate)
	key := rk + "\x1f" + r.identity
	if w, ok := a.weights[key]; ok {
		return w
	}
	pool := a.byRegion[rk]
	if len(pool) == 0 {
		pool = a.all
	}
	w := make([]float64, len(a.branches))
	var sum float64
	for _, i := range pool {
		if s := a.branches[i].skus[r.identity]; s != nil && s.pieces > 0 {
			w[i] = float64(s.pieces)
			sum += w[i]
		}
	}
	if sum == 0 {
		for _, i := range pool {
			w[i] = float64(a.branches[i].pieces)
			sum += w[i]
		}
	}
	if sum == 0 {
		w = nil
	} else {
		for i := range w {
			w[i] /= sum
		}
	}
	a.weights[key] = w
	return w
}

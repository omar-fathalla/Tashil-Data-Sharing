package bigquery

import (
	"strings"
	"unicode"

	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Derived Sell-In target branches are Sell-Out stores (store_id such as fat_smouha, display name
// «فرع فتح الله - سموحة»). A Sell-In row counts for a branch only through an exact key:
//
//   - its customer branch code is the store id, or the chain's ERP branch code of the store;
//   - its customer name, or the branch part of «<customer> - <branch>» (GP SOP Customer Name),
//     canonicalizes to the store id with gemini.BuildBranchStoreMetadata — the dictionary Sell-Out
//     uploads use to name stores (exact / alias / abbreviation, never fuzzy).
//
// A row that names a known store without a target becomes its own branch line (target 0). A row with
// no branch — an empty code, the legacy «مجمع الإقليم (Regional)» placeholder, or a label that is not
// a known store — is reported under «غير محدد الفرع» and never distributed over the branches.

const (
	derivedBranchSlugCacheMax = 8192

	DerivedUnassignedBranchCode = "__unassigned__"
	DerivedUnassignedBranchName = "غير محدد الفرع"
)

// derivedBranchSlug is the canonical store id of a branch label (gemini.BuildBranchStoreMetadata, the
// same id Sell-Out uploads give the store) and its display name. Memoized: labels repeat across rows,
// targets and reads.
func (c *Client) derivedBranchSlug(chain, label string) (string, string) {
	label = strings.TrimSpace(label)
	if label == "" {
		return "", ""
	}
	key := chain + "\x1f" + label
	c.derivedSI.mu.Lock()
	if v, ok := c.derivedSI.slugs[key]; ok {
		c.derivedSI.mu.Unlock()
		return v[0], v[1]
	}
	c.derivedSI.mu.Unlock()
	st := gemini.BuildBranchStoreMetadata(chain, label)
	v := [2]string{strings.ToLower(st.ID), st.BranchName}
	c.derivedSI.mu.Lock()
	if c.derivedSI.slugs == nil || len(c.derivedSI.slugs) >= derivedBranchSlugCacheMax {
		c.derivedSI.slugs = make(map[string][2]string)
	}
	c.derivedSI.slugs[key] = v
	c.derivedSI.mu.Unlock()
	return v[0], v[1]
}

// derivedKnownStoreID reports whether id names a store of the branch dictionary (not an id hashed from
// an unknown label, not the Sell-Out «غير موزع على فرع» bucket).
func derivedKnownStoreID(id string) bool {
	return id != "" && !strings.Contains(id, "_auto_") && !strings.HasSuffix(id, "_unallocated")
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
	keys := []string{s}
	if i := strings.Index(s, "-"); i > 0 {
		rest := s[i+1:]
		if rest != "" && strings.IndexFunc(rest, func(r rune) bool { return !unicode.IsDigit(r) }) < 0 {
			keys = append(keys, rest)
		}
	}
	return keys
}

type derivedBranchRef struct {
	key  string // target branch key, or the canonical store id of a branch without a target
	name string
}

// derivedBranchAttr resolves the Sell-In rows of one derived target to branches.
type derivedBranchAttr struct {
	c        *Client
	chain    string
	byID     map[string]derivedBranchRef // target branch key / canonical store id → branch
	catalog  map[string]derivedBranchRef // ERP branch code → branch
	resolved map[string]*derivedBranchRef
}

func (c *Client) newDerivedBranchAttr(chain string, branches []*derivedBranchAgg) *derivedBranchAttr {
	slugChain := chain
	if slugChain == "" {
		slugChain = "fathalla"
	}
	a := &derivedBranchAttr{
		c: c, chain: slugChain,
		byID:     map[string]derivedBranchRef{},
		catalog:  map[string]derivedBranchRef{},
		resolved: map[string]*derivedBranchRef{},
	}
	put := func(m map[string]derivedBranchRef, k string, ref derivedBranchRef) {
		if _, taken := m[k]; k != "" && !taken {
			m[k] = ref
		}
	}
	for _, b := range branches {
		ref := derivedBranchRef{key: b.key, name: b.name}
		put(a.byID, strings.ToLower(strings.TrimSpace(b.key)), ref)
		if id, _ := c.derivedBranchSlug(slugChain, b.name); derivedKnownStoreID(id) {
			put(a.byID, id, ref)
		}
	}
	for _, e := range derivedChainCatalog(chain) {
		id, name := c.derivedBranchSlug(slugChain, e.Name)
		ref, ok := a.byID[id]
		if !ok {
			if !derivedKnownStoreID(id) {
				continue
			}
			ref = derivedBranchRef{key: id, name: name}
		}
		for _, k := range derivedBranchCodeKeys(e.Code) {
			put(a.catalog, k, ref)
		}
	}
	return a
}

// storeRef maps a canonical store id to the target branch holding it, else to its own branch line.
func (a *derivedBranchAttr) storeRef(id, name string) *derivedBranchRef {
	if ref, ok := a.byID[id]; ok {
		return &ref
	}
	if derivedKnownStoreID(id) {
		return &derivedBranchRef{key: id, name: name}
	}
	return nil
}

// resolve returns the branch a Sell-In row names, or nil when it names none (→ «غير محدد الفرع»).
func (a *derivedBranchAttr) resolve(r *derivedSellInRow) *derivedBranchRef {
	chain := r.chain
	if chain == "" {
		chain = a.chain
	}
	memo := chain + "\x1f" + r.customerCode + "\x1f" + r.customerName
	if ref, ok := a.resolved[memo]; ok {
		return ref
	}
	ref := a.resolveUncached(chain, r)
	a.resolved[memo] = ref
	return ref
}

func (a *derivedBranchAttr) resolveUncached(chain string, r *derivedSellInRow) *derivedBranchRef {
	if code := strings.TrimSpace(r.customerCode); code != "" && !gemini.IsSellInNoBranchPlaceholder(code) {
		if ref, ok := a.byID[code]; ok {
			return &ref
		}
		for _, k := range derivedBranchCodeKeys(code) {
			if ref, ok := a.catalog[k]; ok {
				return &ref
			}
		}
		if id, name := a.c.derivedBranchSlug(chain, code); derivedKnownStoreID(id) {
			return a.storeRef(id, name)
		}
	}
	name := strings.TrimSpace(r.customerName)
	if name == "" {
		return nil
	}
	if _, branch := gemini.ParseChainBranchCell(name); branch != "" && branch != name {
		if id, label := a.c.derivedBranchSlug(chain, branch); derivedKnownStoreID(id) {
			return a.storeRef(id, label)
		}
	}
	if id, label := a.c.derivedBranchSlug(chain, name); derivedKnownStoreID(id) {
		return a.storeRef(id, label)
	}
	return nil
}

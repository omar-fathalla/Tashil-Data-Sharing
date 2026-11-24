package bigquery

import (
	"strconv"
	"sync"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// pmItemTokens is the tokenized form of one Product Master item used by the fuzzy name scoring.
type pmItemTokens struct {
	name, brandField string
	brand            string
	tokenSet         map[string]bool
	measures, nums   []string
}

// pmTokenCache keeps the tokenized Product Master per tenant so fuzzy matching does not re-tokenize
// every item for every lookup. Own lock; never taken while waiting for c.mu.
type pmTokenCache struct {
	mu       sync.Mutex
	byTenant map[string][]pmItemTokens
}

// productMasterItemTokens returns the tokens of items (index-aligned). An entry is reused only while
// the item's name and brand are unchanged, so in-place Product Master edits are picked up.
func (c *Client) productMasterItemTokens(normTenant string, items []domain.ProductMasterItem) []pmItemTokens {
	c.pmTok.mu.Lock()
	cached := c.pmTok.byTenant[normTenant]
	c.pmTok.mu.Unlock()
	if len(cached) == len(items) {
		valid := true
		for i := range items {
			if cached[i].name != items[i].OfficialName || cached[i].brandField != items[i].Brand {
				valid = false
				break
			}
		}
		if valid {
			return cached
		}
	}
	out := make([]pmItemTokens, len(items))
	for i := range items {
		toks := normalizeArabicFMCGTokens(items[i].OfficialName)
		set := make(map[string]bool, len(toks))
		for _, t := range toks {
			set[t] = true
		}
		measures, nums := extractNormalizedMeasures(toks)
		out[i] = pmItemTokens{
			name:       items[i].OfficialName,
			brandField: items[i].Brand,
			brand:      extractCanonicalBrand(items[i].Brand, toks),
			tokenSet:   set,
			measures:   measures,
			nums:       nums,
		}
	}
	c.pmTok.mu.Lock()
	if c.pmTok.byTenant == nil {
		c.pmTok.byTenant = make(map[string][]pmItemTokens)
	}
	c.pmTok.byTenant[normTenant] = out
	c.pmTok.mu.Unlock()
	return out
}

type sellInMatch struct {
	pm domain.ProductMasterItem
	ok bool
}

// sellInMatchMemo memoizes Product Master matches by their full input within one enrichment batch.
// A nil memo performs every lookup.
type sellInMatchMemo map[string]sellInMatch

func (m sellInMatchMemo) lookup(c *Client, tenantID, itemCode, barcode, name, promo string, casePrice float64) (domain.ProductMasterItem, bool) {
	if m == nil {
		return c.lookupProductMasterWithPriceLocked(tenantID, itemCode, barcode, name, promo, casePrice)
	}
	key := tenantID + "\x1f" + itemCode + "\x1f" + barcode + "\x1f" + name + "\x1f" + promo + "\x1f" + strconv.FormatFloat(casePrice, 'g', -1, 64)
	if v, ok := m[key]; ok {
		return v.pm, v.ok
	}
	pm, ok := c.lookupProductMasterWithPriceLocked(tenantID, itemCode, barcode, name, promo, casePrice)
	m[key] = sellInMatch{pm: pm, ok: ok}
	return pm, ok
}

// Package matcher resolves Sell-In / Sell-Out product rows against the Product Master
// catalog with an explicit confidence score and Arabic reason. Uncertain rows go to a
// review queue. Barcodes are never invented — only cleaned input barcodes or barcodes
// that already exist on a matched Product Master SKU are returned.
package matcher

import (
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Decision is the match outcome for one query row.
type Decision string

const (
	DecisionExact     Decision = "exact"     // barcode or item code exact hit
	DecisionHigh      Decision = "high"      // strong name / fuzzy hit (auto-safe)
	DecisionUncertain Decision = "uncertain" // needs human review
	DecisionNone      Decision = "none"      // no plausible candidate
)

// Confidence thresholds (0–1). Uncertain band feeds the review queue.
const (
	HighConfidenceMin      = 0.85
	UncertainConfidenceMin = 0.50
)

// Query is one product row to resolve against Product Master.
type Query struct {
	ItemCode   string  `json:"item_code,omitempty" firestore:"item_code,omitempty"`
	Barcode    string  `json:"barcode,omitempty" firestore:"barcode,omitempty"`
	SKUName    string  `json:"sku_name,omitempty" firestore:"sku_name,omitempty"`
	SourceFile string  `json:"source_file,omitempty" firestore:"source_file,omitempty"`
	Rows       int     `json:"rows,omitempty" firestore:"rows,omitempty"`
	Value      float64 `json:"value,omitempty" firestore:"value,omitempty"`
}

// Candidate is a ranked Product Master suggestion shown in the review UI.
type Candidate struct {
	ItemCode     string  `json:"item_code" firestore:"item_code"`
	Barcode      string  `json:"barcode,omitempty" firestore:"barcode,omitempty"`
	OfficialName string  `json:"official_name" firestore:"official_name"`
	Brand        string  `json:"brand,omitempty" firestore:"brand,omitempty"`
	ItemType     string  `json:"item_type,omitempty" firestore:"item_type,omitempty"`
	Confidence   float64 `json:"confidence" firestore:"confidence"`
	ReasonAR     string  `json:"reason_ar" firestore:"reason_ar"`
}

// Result is the matcher outcome. SuggestedBarcode is only filled from Product Master
// (or preserved from input) — never synthesized.
type Result struct {
	Decision         Decision    `json:"decision" firestore:"decision"`
	Confidence       float64     `json:"confidence" firestore:"confidence"`
	ReasonAR         string      `json:"reason_ar" firestore:"reason_ar"`
	ReasonEN         string      `json:"reason_en,omitempty" firestore:"reason_en,omitempty"`
	MatchedItemCode  string      `json:"matched_item_code,omitempty" firestore:"matched_item_code,omitempty"`
	MatchedName      string      `json:"matched_name,omitempty" firestore:"matched_name,omitempty"`
	MatchedBrand     string      `json:"matched_brand,omitempty" firestore:"matched_brand,omitempty"`
	InputBarcode     string      `json:"input_barcode,omitempty" firestore:"input_barcode,omitempty"`
	SuggestedBarcode string      `json:"suggested_barcode,omitempty" firestore:"suggested_barcode,omitempty"`
	BarcodePolicy    string      `json:"barcode_policy" firestore:"barcode_policy"`
	Candidates       []Candidate `json:"candidates,omitempty" firestore:"candidates,omitempty"`
}

// Catalog indexes Product Master items for matching.
type Catalog struct {
	items     []domain.ProductMasterItem
	byCode    map[string]domain.ProductMasterItem
	byBarcode map[string][]domain.ProductMasterItem
	byName    map[string]domain.ProductMasterItem
}

// NewCatalog builds lookup indexes from Product Master items.
func NewCatalog(items []domain.ProductMasterItem) *Catalog {
	c := &Catalog{
		items:     append([]domain.ProductMasterItem(nil), items...),
		byCode:    make(map[string]domain.ProductMasterItem, len(items)),
		byBarcode: make(map[string][]domain.ProductMasterItem, len(items)),
		byName:    make(map[string]domain.ProductMasterItem, len(items)),
	}
	for _, it := range items {
		if code := normalizeItemCode(it.ItemCode); code != "" {
			if _, exists := c.byCode[code]; !exists || it.IsPrimaryForBarcode {
				c.byCode[code] = it
			}
		}
		if bc := cleanBarcode(it.Barcode); bc != "" {
			c.byBarcode[bc] = append(c.byBarcode[bc], it)
		}
		if nk := normalizeArabicName(it.OfficialName); nk != "" {
			if _, exists := c.byName[nk]; !exists || it.IsPrimaryForBarcode {
				c.byName[nk] = it
			}
		}
	}
	return c
}

// Len returns the number of Product Master SKUs in the catalog.
func (c *Catalog) Len() int {
	if c == nil {
		return 0
	}
	return len(c.items)
}

// Match resolves one query against the catalog. It never invents a barcode.
func (c *Catalog) Match(q Query) Result {
	if c == nil || len(c.items) == 0 {
		return Result{
			Decision:      DecisionNone,
			Confidence:    0,
			ReasonAR:      "كارتة الأصناف غير محمّلة لهذا المستأجر",
			ReasonEN:      "product master catalog empty",
			InputBarcode:  cleanBarcode(q.Barcode),
			BarcodePolicy: barcodePolicy(cleanBarcode(q.Barcode), "", DecisionNone, false),
		}
	}

	inputBC := cleanBarcode(q.Barcode)
	code := normalizeItemCode(q.ItemCode)
	nameKey := normalizeArabicName(q.SKUName)

	// 1) Exact item code
	if code != "" {
		if it, ok := c.byCode[code]; ok {
			return c.finish(q, it, DecisionExact, 0.98,
				"تطابق كود الصنف حرفياً مع كارتة الأصناف",
				"exact item code match", nil, false)
		}
	}

	// 2) Exact barcode (possibly multiple candidates sharing GTIN)
	if inputBC != "" {
		if cands := c.byBarcode[inputBC]; len(cands) == 1 {
			return c.finish(q, cands[0], DecisionExact, 1.0,
				"تطابق الباركود حرفياً مع كارتة الأصناف",
				"exact barcode match", nil, false)
		} else if len(cands) > 1 {
			best, conf, reasonAR, ranked := disambiguateBarcodeCands(q.SKUName, cands)
			dec := DecisionHigh
			if conf < HighConfidenceMin {
				dec = DecisionUncertain
			}
			return c.finish(q, best, dec, conf, reasonAR, "shared barcode disambiguation", ranked, false)
		}
		// Foreign / unknown barcode: never re-label via name match.
		fuzzy := c.rankByName(q.SKUName, 3)
		return Result{
			Decision:         DecisionNone,
			Confidence:       0,
			ReasonAR:         fmt.Sprintf("الباركود %s غير موجود في كارتة الأصناف — لن نغيّره باسم مشابه", inputBC),
			ReasonEN:         "foreign barcode; refuse name-based reassignment",
			InputBarcode:     inputBC,
			SuggestedBarcode: "", // never invent / never replace
			BarcodePolicy:    "preserved_input",
			Candidates:       fuzzy, // hints only
		}
	}

	// 3) Exact normalized official name
	if nameKey != "" {
		if it, ok := c.byName[nameKey]; ok {
			return c.finish(q, it, DecisionHigh, 0.95,
				"تطابق اسم الصنف بعد توحيد العربية",
				"exact normalized name match", nil, true)
		}
	}

	// 4) Fuzzy name ranking
	ranked := c.rankByName(q.SKUName, 5)
	if len(ranked) == 0 {
		return Result{
			Decision:      DecisionNone,
			Confidence:    0,
			ReasonAR:      "لا يوجد مرشح مناسب في كارتة الأصناف",
			ReasonEN:      "no candidate",
			InputBarcode:  inputBC,
			BarcodePolicy: "empty",
		}
	}
	top := ranked[0]
	it := c.byCode[normalizeItemCode(top.ItemCode)]
	if top.ItemCode == "" {
		it = domain.ProductMasterItem{}
	}
	dec := DecisionNone
	switch {
	case top.Confidence >= HighConfidenceMin:
		dec = DecisionHigh
	case top.Confidence >= UncertainConfidenceMin:
		dec = DecisionUncertain
	default:
		dec = DecisionNone
	}
	return c.finish(q, it, dec, top.Confidence, top.ReasonAR, "fuzzy name match", ranked, true)
}

func (c *Catalog) finish(q Query, it domain.ProductMasterItem, dec Decision, conf float64, reasonAR, reasonEN string, cands []Candidate, allowMasterBarcode bool) Result {
	inputBC := cleanBarcode(q.Barcode)
	suggested := ""
	conflict := false
	switch {
	case inputBC != "":
		suggested = inputBC // preserve input; never invent a different code
		if mb := cleanBarcode(it.Barcode); mb != "" && mb != inputBC {
			conflict = true
			dec = DecisionUncertain
			reasonAR = "باركود الملف يختلف عن باركود كارتة الأصناف — يحتاج مراجعة"
			reasonEN = "input barcode conflicts with matched master barcode"
		}
	case allowMasterBarcode && cleanBarcode(it.Barcode) != "" && (dec == DecisionExact || dec == DecisionHigh):
		suggested = cleanBarcode(it.Barcode) // from master only, high confidence
	case allowMasterBarcode && cleanBarcode(it.Barcode) != "" && dec == DecisionUncertain:
		// Suggest for review UI but do not treat as applied.
		suggested = cleanBarcode(it.Barcode)
	}
	if conf < 0 {
		conf = 0
	}
	if conf > 1 {
		conf = 1
	}
	conf = math.Round(conf*1000) / 1000
	res := Result{
		Decision:         dec,
		Confidence:       conf,
		ReasonAR:         reasonAR,
		ReasonEN:         reasonEN,
		MatchedItemCode:  it.ItemCode,
		MatchedName:      it.OfficialName,
		MatchedBrand:     it.Brand,
		InputBarcode:     inputBC,
		SuggestedBarcode: suggested,
		BarcodePolicy:    barcodePolicy(inputBC, suggested, dec, conflict),
		Candidates:       cands,
	}
	return res
}

func barcodePolicy(input, suggested string, dec Decision, conflict bool) string {
	if conflict {
		return "conflict_review"
	}
	if input != "" {
		return "preserved_input"
	}
	if suggested != "" && (dec == DecisionExact || dec == DecisionHigh) {
		return "from_master"
	}
	if suggested != "" {
		return "from_master_pending_review"
	}
	return "empty"
}

func disambiguateBarcodeCands(skuName string, cands []domain.ProductMasterItem) (domain.ProductMasterItem, float64, string, []Candidate) {
	qTokens := coreTokens(tokenizeArabic(skuName))
	ranked := make([]Candidate, 0, len(cands))
	best := cands[0]
	bestScore := -1.0
	for _, cand := range cands {
		ct := coreTokens(tokenizeArabic(cand.OfficialName))
		score := jaccard(qTokens, ct)
		if cand.IsPrimaryForBarcode {
			score += 0.05
		}
		if skuName == "" {
			score = 0.55 // shared barcode, no name → uncertain band
		}
		if score > 1 {
			score = 1
		}
		ranked = append(ranked, Candidate{
			ItemCode:     cand.ItemCode,
			Barcode:      cleanBarcode(cand.Barcode),
			OfficialName: cand.OfficialName,
			Brand:        cand.Brand,
			ItemType:     cand.ItemType,
			Confidence:   math.Round(score*1000) / 1000,
			ReasonAR:     "باركود مشترك بين أكثر من صنف — تمييز بالاسم",
		})
		if score > bestScore {
			bestScore = score
			best = cand
		}
	}
	sort.Slice(ranked, func(i, j int) bool { return ranked[i].Confidence > ranked[j].Confidence })
	reason := "باركود مشترك؛ تم اختيار أقرب اسم في كارتة الأصناف"
	if bestScore < HighConfidenceMin {
		reason = "باركود مشترك ويحتاج مراجعة لاختيار الصنف الصحيح"
	}
	return best, math.Round(bestScore*1000) / 1000, reason, ranked
}

func (c *Catalog) rankByName(skuName string, limit int) []Candidate {
	qTokens := coreTokens(tokenizeArabic(skuName))
	if len(qTokens) == 0 {
		return nil
	}
	type scored struct {
		it    domain.ProductMasterItem
		score float64
	}
	var ranked []scored
	for _, it := range c.items {
		itTokens := coreTokens(tokenizeArabic(it.OfficialName))
		score := jaccard(qTokens, itTokens)
		// Brand token boost when official name / brand field overlaps a query token.
		brandKey := normalizeArabicName(it.Brand)
		for _, qt := range qTokens {
			if brandKey != "" && strings.Contains(brandKey, qt) {
				score += 0.08
			}
		}
		if it.IsPrimaryForBarcode {
			score += 0.02
		}
		if score < UncertainConfidenceMin/2 {
			continue
		}
		if score > 1 {
			score = 1
		}
		ranked = append(ranked, scored{it: it, score: score})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].score == ranked[j].score {
			return ranked[i].it.ItemCode < ranked[j].it.ItemCode
		}
		return ranked[i].score > ranked[j].score
	})
	if limit > 0 && len(ranked) > limit {
		ranked = ranked[:limit]
	}
	out := make([]Candidate, 0, len(ranked))
	for _, s := range ranked {
		reason := "تشابه أسماء بعد توحيد العربية"
		switch {
		case s.score >= HighConfidenceMin:
			reason = "تشابه قوي في اسم الصنف مع كارتة الأصناف"
		case s.score >= UncertainConfidenceMin:
			reason = "تشابه متوسط — يحتاج مراجعة بشرية"
		default:
			reason = "تشابه ضعيف — غير موثوق"
		}
		out = append(out, Candidate{
			ItemCode:     s.it.ItemCode,
			Barcode:      cleanBarcode(s.it.Barcode),
			OfficialName: s.it.OfficialName,
			Brand:        s.it.Brand,
			ItemType:     s.it.ItemType,
			Confidence:   math.Round(s.score*1000) / 1000,
			ReasonAR:     reason,
		})
	}
	return out
}

// NeedsReview reports whether the decision should enter the human review queue.
func NeedsReview(r Result) bool {
	return r.Decision == DecisionUncertain || r.Decision == DecisionNone
}

// MatchBatch matches many queries. Does not persist; caller decides enqueue.
func (c *Catalog) MatchBatch(queries []Query) []Result {
	out := make([]Result, len(queries))
	for i, q := range queries {
		out[i] = c.Match(q)
	}
	return out
}

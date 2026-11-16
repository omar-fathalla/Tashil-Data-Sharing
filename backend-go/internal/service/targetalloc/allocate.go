package targetalloc

import (
	"math"
	"math/big"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Apportion splits total (integer units) over weights using the largest-remainder method, so the
// parts always add up to total exactly. Non-positive weights get 0. All math is exact (big integers).
func Apportion(total int64, weights []int64) []int64 {
	out := make([]int64, len(weights))
	sum := new(big.Int)
	positive := 0
	for _, w := range weights {
		if w > 0 {
			sum.Add(sum, big.NewInt(w))
			positive++
		}
	}
	if total <= 0 || positive == 0 {
		return out
	}
	type part struct {
		idx int
		rem *big.Int
	}
	parts := make([]part, 0, positive)
	var given int64
	bt := big.NewInt(total)
	for i, w := range weights {
		if w <= 0 {
			continue
		}
		prod := new(big.Int).Mul(bt, big.NewInt(w))
		q, r := new(big.Int).QuoRem(prod, sum, new(big.Int))
		out[i] = q.Int64()
		given += out[i]
		parts = append(parts, part{idx: i, rem: r})
	}
	left := total - given
	sort.SliceStable(parts, func(a, b int) bool {
		if c := parts[a].rem.Cmp(parts[b].rem); c != 0 {
			return c > 0
		}
		if weights[parts[a].idx] != weights[parts[b].idx] {
			return weights[parts[a].idx] > weights[parts[b].idx]
		}
		return parts[a].idx < parts[b].idx
	})
	for i := int64(0); i < left && int(i) < len(parts); i++ {
		out[parts[i].idx]++
	}
	return out
}

// InScope applies a target's branch/category scope exactly like the in-memory target actuals do
// (substring match, lower-cased). Empty filters match everything.
func InScope(r Row, branchFilter, categoryFilter string) bool {
	if branchFilter != "" &&
		!strings.Contains(strings.ToLower(r.StoreName), branchFilter) &&
		!strings.Contains(strings.ToLower(r.StoreID), branchFilter) {
		return false
	}
	if categoryFilter != "" {
		norm := strings.ToLower(domain.NormalizeProductCategory(r.Category))
		if !strings.Contains(norm, categoryFilter) &&
			!strings.Contains(strings.ToLower(r.Category), categoryFilter) &&
			!strings.Contains(strings.ToLower(r.SKUName), categoryFilter) {
			return false
		}
	}
	return true
}

// ScopeFilter turns a stored scope value ("كل الفروع", "all", "") into an empty (match-all) filter.
func ScopeFilter(raw string, allLabel string) string {
	v := strings.ToLower(strings.TrimSpace(raw))
	if v == "" || v == "all" || v == "الكل" || v == strings.ToLower(allLabel) {
		return ""
	}
	return v
}

// Input is everything Build needs.
type Input struct {
	Target       domain.TargetRecord
	Rows         []Row
	Baseline     Baseline
	ActualWindow Window
	Source       string
}

type skuAgg struct {
	key, name, category string
	upc                 int64
	baseRev, actRev     float64
	baseUnits, actUnits int64
	weight              float64
}

type branchAgg struct {
	key, name string
	skus      map[string]*skuAgg
	order     []string
	topRev    float64
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

func pct(num, den float64) *float64 {
	if den <= 0 {
		return nil
	}
	v := math.Round(num/den*1000) / 10
	return &v
}

func centsOf(v float64) int64 {
	c := int64(math.Round(v * 100))
	if c < 1 && v > 0 {
		return 1
	}
	return c
}

// Build allocates the target over branches and SKUs. See domain.TargetBreakdownResponse.
func Build(in Input) domain.TargetBreakdownResponse {
	t := in.Target
	resp := domain.TargetBreakdownResponse{
		TargetID: t.ID, TargetType: t.TargetType, RetailerChain: t.RetailerChain,
		ChainDisplayName: t.ChainDisplayName, Year: t.Year, Month: t.Month, MonthLabel: t.MonthLabel,
		BranchScope: t.BranchName, CategoryScope: t.Category,
		TargetRevenueEGP: t.TargetRevenueEGP, TargetUnits: t.TargetUnits,
		ActualStartDate: in.ActualWindow.Start, ActualEndDate: in.ActualWindow.End,
		Source:    in.Source,
		Branches:  []domain.TargetBreakdownBranch{},
		NoHistory: []domain.TargetBreakdownNoHistory{},
		Baseline: domain.TargetBreakdownBaseline{
			Kind: in.Baseline.Kind, Year: in.Baseline.Year,
			StartDate: in.Baseline.Window.Start, EndDate: in.Baseline.Window.End,
			MonthsCovered: in.Baseline.MonthsCovered, Partial: in.Baseline.Partial,
			FallbackUsed: in.Baseline.FallbackUsed, CaptionAr: in.Baseline.CaptionAr(),
		},
	}

	brFilter := ScopeFilter(t.BranchName, "كل الفروع")
	catFilter := ScopeFilter(t.Category, "كل الفئات")

	branches := map[string]*branchAgg{}
	var branchOrder []string
	chainSKU := map[string]*skuAgg{}
	for _, r := range in.Rows {
		if !InScope(r, brFilter, catFilter) {
			continue
		}
		if r.ActRows > 0 {
			resp.HasActuals = true
		}
		if strings.TrimSpace(r.StoreKey) == "" {
			resp.UnattributedActualEGP += r.ActRev
			continue
		}
		b := branches[r.StoreKey]
		if b == nil {
			b = &branchAgg{key: r.StoreKey, skus: map[string]*skuAgg{}}
			branches[r.StoreKey] = b
			branchOrder = append(branchOrder, r.StoreKey)
		}
		if mag := math.Abs(r.BaseRev) + math.Abs(r.ActRev); strings.TrimSpace(r.StoreName) != "" && (b.name == "" || mag > b.topRev) {
			b.name = strings.TrimSpace(r.StoreName)
			b.topRev = mag
		}
		skuKey := strings.TrimSpace(r.SKUKey)
		if skuKey == "" {
			skuKey = strings.TrimSpace(r.SKUName)
		}
		if skuKey == "" {
			skuKey = "—"
		}
		s := b.skus[skuKey]
		if s == nil {
			s = &skuAgg{key: skuKey}
			b.skus[skuKey] = s
			b.order = append(b.order, skuKey)
		}
		if mag := math.Abs(r.BaseRev) + math.Abs(r.ActRev); strings.TrimSpace(r.SKUName) != "" && (s.name == "" || mag > s.weight) {
			s.name = strings.TrimSpace(r.SKUName)
			s.category = strings.TrimSpace(r.Category)
			s.weight = mag
		}
		if r.UnitsPerCarton > s.upc {
			s.upc = r.UnitsPerCarton
		}
		s.baseRev += r.BaseRev
		s.baseUnits += r.BaseUnits
		s.actRev += r.ActRev
		s.actUnits += r.ActUnits

		c := chainSKU[skuKey]
		if c == nil {
			c = &skuAgg{key: skuKey}
			chainSKU[skuKey] = c
		}
		c.baseRev += r.BaseRev
		c.baseUnits += r.BaseUnits
	}

	type eligibleBranch struct {
		agg      *branchAgg
		baseline float64
	}
	var eligible []eligibleBranch
	var totalBaseline float64
	for _, key := range branchOrder {
		b := branches[key]
		if b.name == "" {
			b.name = b.key
		}
		var base, act float64
		var actUnits int64
		for _, s := range b.skus {
			if s.baseRev > 0 {
				base += s.baseRev
			}
			act += s.actRev
			actUnits += s.actUnits
		}
		if base <= 0 {
			if act != 0 || actUnits != 0 {
				resp.NoHistory = append(resp.NoHistory, domain.TargetBreakdownNoHistory{
					Kind: "branch", BranchKey: b.key, BranchName: b.name,
					ActualRevenueEGP: round2(act), ActualUnits: actUnits,
				})
				resp.NoHistoryActualEGP += act
				resp.ActualRevenueEGP += act
				resp.ActualUnits += actUnits
			}
			continue
		}
		eligible = append(eligible, eligibleBranch{agg: b, baseline: base})
		totalBaseline += base
	}

	granularity := 1.0
	if math.Abs(t.TargetRevenueEGP-math.Round(t.TargetRevenueEGP)) > 1e-9 {
		granularity = 0.01
	}
	resp.AllocationGranularityEG = granularity
	totalSteps := int64(math.Round(t.TargetRevenueEGP / granularity))

	branchWeights := make([]int64, len(eligible))
	for i, e := range eligible {
		branchWeights[i] = centsOf(e.baseline)
	}
	branchSteps := Apportion(totalSteps, branchWeights)

	var unitsTotal int64
	var cartonsTotal float64
	haveUnits, haveCartons := false, false

	for i, e := range eligible {
		b := e.agg
		out := domain.TargetBreakdownBranch{
			BranchKey: b.key, BranchName: b.name,
			BaselineRevenueEGP: round2(e.baseline),
			SharePct:           math.Round(e.baseline/totalBaseline*1e6) / 1e4,
			AllocatedTargetEGP: round2(float64(branchSteps[i]) * granularity),
			SKUs:               []domain.TargetBreakdownSKU{},
		}
		var skuIdx []*skuAgg
		var skuWeights []int64
		for _, k := range b.order {
			s := b.skus[k]
			if s.baseRev > 0 {
				skuIdx = append(skuIdx, s)
				skuWeights = append(skuWeights, centsOf(s.baseRev))
			} else if s.actRev != 0 || s.actUnits != 0 {
				resp.NoHistory = append(resp.NoHistory, domain.TargetBreakdownNoHistory{
					Kind: "sku", BranchKey: b.key, BranchName: b.name, SKUKey: s.key, SKUName: s.name,
					ActualRevenueEGP: round2(s.actRev), ActualUnits: s.actUnits,
				})
				resp.NoHistoryActualEGP += s.actRev
			}
			out.ActualRevenueEGP += s.actRev
			out.ActualUnits += s.actUnits
		}
		skuSteps := Apportion(branchSteps[i], skuWeights)
		var bUnits int64
		var bCartons float64
		bHaveUnits, bHaveCartons := false, false
		for j, s := range skuIdx {
			alloc := round2(float64(skuSteps[j]) * granularity)
			row := domain.TargetBreakdownSKU{
				SKUKey: s.key, SKUName: s.name, Category: s.category, UnitsPerCarton: int(s.upc),
				BaselineRevenueEGP: round2(s.baseRev), BaselineUnits: s.baseUnits,
				SharePct:           math.Round(s.baseRev/e.baseline*1e6) / 1e4,
				AllocatedTargetEGP: alloc,
				ActualRevenueEGP:   round2(s.actRev), ActualUnits: s.actUnits,
			}
			price := 0.0
			if s.baseUnits > 0 && s.baseRev > 0 {
				price = s.baseRev / float64(s.baseUnits)
			} else if c := chainSKU[s.key]; c != nil && c.baseUnits > 0 && c.baseRev > 0 {
				price = c.baseRev / float64(c.baseUnits)
			}
			if price > 0 {
				p := round2(price)
				row.AvgUnitPriceEGP = &p
				u := int64(math.Round(alloc / price))
				row.AllocatedUnits = &u
				bUnits += u
				bHaveUnits = true
				if s.upc > 0 {
					c := math.Round(float64(u)/float64(s.upc)*100) / 100
					row.AllocatedCartons = &c
					bCartons += c
					bHaveCartons = true
				}
			}
			if resp.HasActuals {
				row.AchievementPct = pct(s.actRev, alloc)
				row.GapEGP = round2(s.actRev - alloc)
			}
			out.SKUs = append(out.SKUs, row)
		}
		sort.SliceStable(out.SKUs, func(a, c int) bool {
			if out.SKUs[a].AllocatedTargetEGP != out.SKUs[c].AllocatedTargetEGP {
				return out.SKUs[a].AllocatedTargetEGP > out.SKUs[c].AllocatedTargetEGP
			}
			return out.SKUs[a].SKUName < out.SKUs[c].SKUName
		})
		if bHaveUnits {
			out.AllocatedUnits = &bUnits
			unitsTotal += bUnits
			haveUnits = true
		}
		if bHaveCartons {
			bCartons = math.Round(bCartons*100) / 100
			out.AllocatedCartons = &bCartons
			cartonsTotal += bCartons
			haveCartons = true
		}
		out.ActualRevenueEGP = round2(out.ActualRevenueEGP)
		if resp.HasActuals {
			out.AchievementPct = pct(out.ActualRevenueEGP, out.AllocatedTargetEGP)
			out.GapEGP = round2(out.ActualRevenueEGP - out.AllocatedTargetEGP)
		}
		resp.ActualRevenueEGP += out.ActualRevenueEGP
		resp.ActualUnits += out.ActualUnits
		resp.Baseline.TotalEGP += out.BaselineRevenueEGP
		resp.Branches = append(resp.Branches, out)
	}

	sort.SliceStable(resp.Branches, func(a, c int) bool {
		if resp.Branches[a].AllocatedTargetEGP != resp.Branches[c].AllocatedTargetEGP {
			return resp.Branches[a].AllocatedTargetEGP > resp.Branches[c].AllocatedTargetEGP
		}
		return resp.Branches[a].BranchName < resp.Branches[c].BranchName
	})
	sort.SliceStable(resp.NoHistory, func(a, c int) bool {
		if resp.NoHistory[a].ActualRevenueEGP != resp.NoHistory[c].ActualRevenueEGP {
			return resp.NoHistory[a].ActualRevenueEGP > resp.NoHistory[c].ActualRevenueEGP
		}
		return resp.NoHistory[a].BranchName < resp.NoHistory[c].BranchName
	})

	if haveUnits {
		resp.AllocatedUnitsTotal = &unitsTotal
	}
	if haveCartons {
		cartonsTotal = math.Round(cartonsTotal*100) / 100
		resp.AllocatedCartonsTotal = &cartonsTotal
	}
	resp.ActualRevenueEGP = round2(resp.ActualRevenueEGP)
	resp.NoHistoryActualEGP = round2(resp.NoHistoryActualEGP)
	resp.UnattributedActualEGP = round2(resp.UnattributedActualEGP)
	resp.Baseline.TotalEGP = round2(resp.Baseline.TotalEGP)
	if resp.HasActuals {
		resp.AchievementPct = pct(resp.ActualRevenueEGP, t.TargetRevenueEGP)
		resp.GapEGP = round2(resp.ActualRevenueEGP - t.TargetRevenueEGP)
	}
	return resp
}

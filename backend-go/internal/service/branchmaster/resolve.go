package branchmaster

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// Resolve maps one raw name against an in-memory State snapshot (read-only).
// It never mutates State — callers that auto-link must SaveAlias separately.
func Resolve(st *State, chainSlug, raw string) Resolution {
	raw = strings.TrimSpace(raw)
	key := Normalize(raw)
	res := Resolution{
		RawName:       raw,
		NormalizedKey: key,
		Kind:          KindIdentity,
		Confidence:    0,
		ReasonAR:      "لا توجد بيانات رئيسية للفروع بعد — العرض بالاسم الخام.",
	}
	if raw == "" {
		res.ReasonAR = "اسم الفرع فارغ."
		return res
	}
	if IsUnallocated(raw) {
		cc := ChainCodeForSlug(chainSlug)
		res.Kind = KindUnallocated
		res.BranchCode = UnallocatedCode(cc)
		res.DisplayName = UnallocatedBranchName
		res.ChainCode = cc
		res.Confidence = 1
		res.ReasonAR = "فرع «غير موزع على فرع» يبقى دلواً منفصلاً ولا يُربط تلقائياً."
		return res
	}
	if st == nil || (len(st.Branches) == 0 && len(st.Aliases) == 0) {
		return res
	}

	slug := strings.ToLower(strings.TrimSpace(chainSlug))
	if slug == "" {
		slug = InferChainSlug(raw)
	}
	chainCode := findChainCode(st, slug)

	// 1) Exact / normalized alias hit (instant, no AI).
	if a, br, ok := findAlias(st, key); ok {
		res.Kind = KindAlias
		if Normalize(a.RawName) == key && a.RawName == raw {
			res.Kind = KindExact
		} else if a.NormalizedKey == key {
			res.Kind = KindNormalized
		}
		res.BranchCode = br.Code
		res.DisplayName = br.DisplayName
		res.ChainCode = br.ChainCode
		res.Confidence = 1
		res.ReasonAR = fmt.Sprintf("مطابقة فورية عبر الاسم المستعار → %s (%s).", br.DisplayName, br.Code)
		return res
	}

	// 2) Exact display-name / normalized branch hit.
	if br, ok := findBranchByNorm(st, chainCode, key); ok {
		res.Kind = KindNormalized
		res.BranchCode = br.Code
		res.DisplayName = br.DisplayName
		res.ChainCode = br.ChainCode
		res.Confidence = 1
		res.ReasonAR = fmt.Sprintf("مطابقة بعد التوحيد → %s (%s).", br.DisplayName, br.Code)
		return res
	}

	// 3) Deterministic similarity (+ optional AI score injected by caller via RankCandidates).
	cands := RankCandidates(st, chainCode, raw)
	if len(cands) == 0 {
		res.Kind = KindNew
		res.Confidence = 0
		res.ReasonAR = "فرع جديد — لا يوجد مرشح قريب."
		return res
	}
	top := cands[0]
	var second *rankedCand
	if len(cands) > 1 {
		second = &cands[1]
	}

	if second != nil && (top.Score-second.Score) <= AmbiguousGapMax && second.Score >= LowConfidenceMin {
		res.Kind = KindAmbiguous
		res.BranchCode = top.Branch.Code
		res.DisplayName = top.Branch.DisplayName
		res.ChainCode = top.Branch.ChainCode
		res.Confidence = top.Score
		res.AltCode = second.Branch.Code
		res.AltName = second.Branch.DisplayName
		res.AltConfidence = second.Score
		res.ReasonAR = fmt.Sprintf(
			"التباس بين «%s» (%.0f%%) و«%s» (%.0f%%) — بانتظار تأكيد المالك.",
			top.Branch.DisplayName, top.Score*100, second.Branch.DisplayName, second.Score*100,
		)
		return res
	}
	if top.Score >= HighConfidenceMin {
		res.Kind = KindHigh
		res.BranchCode = top.Branch.Code
		res.DisplayName = top.Branch.DisplayName
		res.ChainCode = top.Branch.ChainCode
		res.Confidence = top.Score
		res.ReasonAR = fmt.Sprintf("ثقة عالية (%.0f%%) → ربط تلقائي بـ «%s».", top.Score*100, top.Branch.DisplayName)
		return res
	}
	if top.Score >= LowConfidenceMin {
		res.Kind = KindLow
		res.BranchCode = top.Branch.Code
		res.DisplayName = top.Branch.DisplayName
		res.ChainCode = top.Branch.ChainCode
		res.Confidence = top.Score
		res.ReasonAR = fmt.Sprintf("ثقة منخفضة (%.0f%%) تجاه «%s» — بانتظار تأكيد المالك.", top.Score*100, top.Branch.DisplayName)
		return res
	}
	res.Kind = KindNew
	res.Confidence = top.Score
	res.ReasonAR = "لا يوجد تطابق كافٍ — يُقترح فرع جديد."
	return res
}

type rankedCand struct {
	Branch Branch
	Score  float64
}

// RankCandidates scores active non-unallocated branches in the same chain.
func RankCandidates(st *State, chainCode, raw string) []rankedCand {
	if st == nil {
		return nil
	}
	var out []rankedCand
	for _, br := range st.Branches {
		if !br.Active || br.Unallocated {
			continue
		}
		if chainCode != "" && br.ChainCode != "" && !strings.EqualFold(br.ChainCode, chainCode) {
			continue
		}
		score := Similarity(raw, br.DisplayName) + ContainsBoost(raw, br.DisplayName)
		// Also compare against known aliases of this branch.
		for _, a := range st.Aliases {
			if a.BranchCode != br.Code {
				continue
			}
			s := Similarity(raw, a.RawName) + ContainsBoost(raw, a.RawName)
			if s > score {
				score = s
			}
		}
		if score > 1 {
			score = 1
		}
		if score >= LowConfidenceMin*0.8 {
			out = append(out, rankedCand{Branch: br, Score: score})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Score == out[j].Score {
			return out[i].Branch.Code < out[j].Branch.Code
		}
		return out[i].Score > out[j].Score
	})
	return out
}

func findChainCode(st *State, slug string) string {
	want := ChainCodeForSlug(slug)
	for _, c := range st.Chains {
		if strings.EqualFold(c.Slug, slug) || strings.EqualFold(c.Code, want) {
			return c.Code
		}
	}
	return want
}

func findAlias(st *State, key string) (Alias, Branch, bool) {
	for _, a := range st.Aliases {
		if a.NormalizedKey == key || Normalize(a.RawName) == key {
			if br, ok := findBranchByCode(st, a.BranchCode); ok {
				return a, br, true
			}
		}
	}
	return Alias{}, Branch{}, false
}

func findBranchByCode(st *State, code string) (Branch, bool) {
	for _, b := range st.Branches {
		if strings.EqualFold(b.Code, code) {
			return b, true
		}
	}
	return Branch{}, false
}

func findBranchByNorm(st *State, chainCode, key string) (Branch, bool) {
	for _, b := range st.Branches {
		if b.Unallocated {
			continue
		}
		if chainCode != "" && b.ChainCode != "" && !strings.EqualFold(b.ChainCode, chainCode) {
			continue
		}
		if Normalize(b.DisplayName) == key {
			return b, true
		}
	}
	return Branch{}, false
}

// EnsureUnallocatedBranch guarantees the synthetic bucket exists for a chain.
func EnsureUnallocatedBranch(st *State, chainSlug string, now time.Time) Branch {
	cc := ChainCodeForSlug(chainSlug)
	code := UnallocatedCode(cc)
	if br, ok := findBranchByCode(st, code); ok {
		return br
	}
	ensureChain(st, chainSlug, now)
	br := Branch{
		Code:        code,
		ChainCode:   cc,
		DisplayName: UnallocatedBranchName,
		Active:      true,
		Unallocated: true,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	st.Branches = append(st.Branches, br)
	return br
}

func ensureChain(st *State, slug string, now time.Time) Chain {
	slug = strings.ToLower(strings.TrimSpace(slug))
	if slug == "" {
		slug = "fathalla"
	}
	cc := ChainCodeForSlug(slug)
	for _, c := range st.Chains {
		if strings.EqualFold(c.Code, cc) || strings.EqualFold(c.Slug, slug) {
			return c
		}
	}
	ch := Chain{
		Code:      cc,
		Slug:      slug,
		NameAR:    ChainNameAR(slug),
		CreatedAt: now,
	}
	st.Chains = append(st.Chains, ch)
	return ch
}

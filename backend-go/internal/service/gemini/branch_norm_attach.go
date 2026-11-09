package gemini

import (
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/branchnorm"
)

// attachBranchNormSummary fills payload.BranchNorm from raw store names on records
// and discovered branch labels. Does not alter honesty thresholds or mapping_source.
func attachBranchNormSummary(payload *domain.NormalizedRetailIngestionPayload) {
	if payload == nil {
		return
	}
	raws := make([]string, 0, len(payload.NormalizedRecords)+len(payload.DiscoveredBranches))
	seen := map[string]struct{}{}
	add := func(s string) {
		s = strings.TrimSpace(s)
		if s == "" {
			return
		}
		// Dedupe exact labels only — keep "سموحة" and "فر. سموحة" as separate inputs
		// so abbrev/alias counters reflect what the sheet actually wrote.
		if _, ok := seen[s]; ok {
			return
		}
		seen[s] = struct{}{}
		raws = append(raws, s)
	}
	for _, rec := range payload.NormalizedRecords {
		add(rec.RawStoreName)
	}
	for _, b := range payload.DiscoveredBranches {
		add(b)
	}
	_, sum := branchnorm.ResolveMany(raws)
	payload.BranchNorm = toDomainBranchNorm(sum)
}

func toDomainBranchNorm(sum branchnorm.Summary) *domain.BranchNormSummary {
	out := &domain.BranchNormSummary{
		Total:       sum.Total,
		Exact:       sum.Exact,
		Alias:       sum.Alias,
		English:     sum.English,
		Abbrev:      sum.Abbrev,
		Unknown:     sum.Unknown,
		Changed:     sum.Changed,
		UniqueRaw:   sum.UniqueRaw,
		UniqueCanon: sum.UniqueCanon,
		SummaryAR:   sum.SummaryAR,
	}
	for _, s := range sum.Samples {
		out.Samples = append(out.Samples, domain.BranchNormSample{
			Raw:         s.Raw,
			CanonicalAR: s.CanonicalAR,
			MatchKind:   s.MatchKind,
			ReasonAR:    s.ReasonAR,
			Confidence:  s.Confidence,
		})
	}
	return out
}

// canonicalizeBranchForStore expands Arabic/English abbreviations before store-ID lookup.
// Returns the preferred Arabic short name and whether branchnorm knew the branch.
func canonicalizeBranchForStore(raw string) (canonical string, known bool, r branchnorm.Result) {
	r = branchnorm.Resolve(raw)
	if r.MatchKind == branchnorm.KindUnknown || r.CanonicalAR == "" {
		return strings.TrimSpace(raw), false, r
	}
	return r.CanonicalAR, true, r
}

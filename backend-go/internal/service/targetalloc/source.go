package targetalloc

import (
	"context"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Source supplies grouped Sell-Out aggregates for one tenant and chain (BigQuery or in-memory).
type Source interface {
	// Coverage lists the months that have Sell-Out rows for the chain.
	Coverage(ctx context.Context) ([]MonthCoverage, error)
	// Rows returns SUMs per (branch, SKU, category, SKU name) over the baseline and actual windows.
	Rows(ctx context.Context, baseline, actual Window) ([]Row, error)
}

// Filters are optional query-param scopes on the breakdown endpoint.
type Filters struct {
	BranchKey string // exact store key; empty = all branches
	Month     int    // 1..12; 0 = full year / target's own month
}

// Compute resolves the baseline, fetches the aggregates and allocates the target.
func Compute(ctx context.Context, src Source, target domain.TargetRecord, sourceName string) (domain.TargetBreakdownResponse, bool, error) {
	return ComputeFiltered(ctx, src, target, sourceName, Filters{})
}

// ComputeFiltered is Compute plus optional branch key and month filters.
// Month (when set on an annual target) narrows the actual window; the caller should
// already scale TargetRevenueEGP / TargetUnits to that month's seasonal slice.
func ComputeFiltered(ctx context.Context, src Source, target domain.TargetRecord, sourceName string, f Filters) (domain.TargetBreakdownResponse, bool, error) {
	cov, err := src.Coverage(ctx)
	if err != nil {
		return domain.TargetBreakdownResponse{}, false, err
	}
	if len(cov) == 0 {
		return domain.TargetBreakdownResponse{}, false, nil
	}
	year, month := target.Year, target.Month
	if f.Month >= 1 && f.Month <= 12 {
		month = f.Month
		target.Month = f.Month
		if target.MonthLabel == "" || target.Month == 0 {
			target.MonthLabel = MonthNameAr(f.Month)
		}
	}
	baseline := ResolveBaseline(year, month, cov)
	actual := ActualWindow(year, month)
	var rows []Row
	if baseline.Window.Valid() {
		rows, err = src.Rows(ctx, baseline.Window, actual)
	} else {
		rows, err = src.Rows(ctx, Window{Start: "9999-01-01", End: "9999-01-01"}, actual)
	}
	if err != nil {
		return domain.TargetBreakdownResponse{}, false, err
	}
	resp := Build(Input{Target: target, Rows: rows, Baseline: baseline, ActualWindow: actual, Source: sourceName})
	resp.AppliedMonth = f.Month
	resp.AppliedBranch = f.BranchKey
	if f.BranchKey != "" {
		resp = FilterToBranch(resp, f.BranchKey)
	}
	return resp, true, nil
}

// FilterToBranch keeps one branch's allocation and rewrites summary KPIs to that branch.
func FilterToBranch(resp domain.TargetBreakdownResponse, branchKey string) domain.TargetBreakdownResponse {
	key := strings.TrimSpace(branchKey)
	if key == "" {
		return resp
	}
	var kept []domain.TargetBreakdownBranch
	var noHist []domain.TargetBreakdownNoHistory
	for _, b := range resp.Branches {
		if strings.EqualFold(b.BranchKey, key) {
			kept = append(kept, b)
		}
	}
	for _, n := range resp.NoHistory {
		if strings.EqualFold(n.BranchKey, key) {
			noHist = append(noHist, n)
		}
	}
	resp.Branches = kept
	resp.NoHistory = noHist
	resp.AppliedBranch = key

	var actRev float64
	var actUnits int64
	var targetRev float64
	var base float64
	var gap float64
	has := false
	for _, b := range kept {
		actRev += b.ActualRevenueEGP
		actUnits += b.ActualUnits
		targetRev += b.AllocatedTargetEGP
		base += b.BaselineRevenueEGP
		gap += b.GapEGP
		if b.AchievementPct != nil || b.ActualRevenueEGP != 0 || b.ActualUnits != 0 {
			has = true
		}
	}
	for _, n := range noHist {
		actRev += n.ActualRevenueEGP
		actUnits += n.ActualUnits
		if n.ActualRevenueEGP != 0 || n.ActualUnits != 0 {
			has = true
		}
	}
	resp.TargetRevenueEGP = round2(targetRev)
	resp.ActualRevenueEGP = round2(actRev)
	resp.ActualUnits = actUnits
	resp.GapEGP = round2(gap)
	resp.Baseline.TotalEGP = round2(base)
	resp.HasActuals = has
	if resp.HasActuals && targetRev > 0 {
		resp.AchievementPct = pct(actRev, targetRev)
	} else if !resp.HasActuals {
		resp.AchievementPct = nil
	}
	if len(kept) == 1 {
		resp.AllocatedUnitsTotal = kept[0].AllocatedUnits
		resp.AllocatedCartonsTotal = kept[0].AllocatedCartons
		if kept[0].BranchName != "" {
			resp.BranchScope = kept[0].BranchName
		}
	}
	resp.NoHistoryActualEGP = 0
	for _, n := range noHist {
		resp.NoHistoryActualEGP += n.ActualRevenueEGP
	}
	resp.NoHistoryActualEGP = round2(resp.NoHistoryActualEGP)
	return resp
}

// ChainFilter turns a stored target chain ("all", "الكل", "") into an empty (all chains) filter.
func ChainFilter(raw string) string {
	v := strings.ToLower(strings.TrimSpace(raw))
	if v == "" || v == "all" || v == "الكل" {
		return ""
	}
	return v
}

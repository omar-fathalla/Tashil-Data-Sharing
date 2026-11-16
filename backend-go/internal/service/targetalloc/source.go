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

// Compute resolves the baseline, fetches the aggregates and allocates the target.
func Compute(ctx context.Context, src Source, target domain.TargetRecord, sourceName string) (domain.TargetBreakdownResponse, bool, error) {
	cov, err := src.Coverage(ctx)
	if err != nil {
		return domain.TargetBreakdownResponse{}, false, err
	}
	if len(cov) == 0 {
		return domain.TargetBreakdownResponse{}, false, nil
	}
	year, month := target.Year, target.Month
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
	return Build(Input{Target: target, Rows: rows, Baseline: baseline, ActualWindow: actual, Source: sourceName}), true, nil
}

// ChainFilter turns a stored target chain ("all", "الكل", "") into an empty (all chains) filter.
func ChainFilter(raw string) string {
	v := strings.ToLower(strings.TrimSpace(raw))
	if v == "" || v == "all" || v == "الكل" {
		return ""
	}
	return v
}

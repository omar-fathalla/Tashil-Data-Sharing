package ingestion

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// ReapplySellInFiles re-processes archived Sell-In files after a customer-registry decision, so
// an approved name's rows enter the totals (or an unmerged name's rows leave them) without a
// re-upload. files == nil means every archived Sell-In file of the tenant. Runs non-interactively
// (no confirmation guards), exactly like the startup archive replay.
func (p *Processor) ReapplySellInFiles(ctx context.Context, tenantID string, files []string) (applied []string, errs []string) {
	want := map[string]bool{}
	for _, f := range files {
		want[strings.TrimSpace(f)] = true
	}
	list := p.ListArchivedFiles(ctx, tenantID, "", "", "", "sell_in")
	if list == nil {
		return nil, nil
	}
	for _, f := range list.Files {
		if !isSellInArchiveEntry(f) || (files != nil && !want[f.FileName]) {
			continue
		}
		entry, raw, err := p.GetArchivedFile(ctx, tenantID, f.ID)
		if err != nil || len(raw) == 0 {
			errs = append(errs, fmt.Sprintf("%s: الملف مش موجود في الأرشيف", f.FileName))
			continue
		}
		if _, err := p.ProcessSellInPlan(ctx, tenantID, entry.FileName, raw, false, entry.RetailChain); err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", entry.FileName, err))
			continue
		}
		applied = append(applied, entry.FileName)
	}
	return applied, errs
}

// SellInYears returns the years that have Sell-In rows or archived Sell-In/Sell-Out files.
func (p *Processor) SellInYears(tenantID string) []int {
	set := map[int]bool{}
	if snap, ok := p.bqRepo.(sellInSnapshotter); ok && p.bqRepo != nil {
		for _, r := range snap.SellInRecordsSnapshot(tenantID) {
			if r.Year > 0 {
				set[r.Year] = true
			}
		}
	}
	if list := p.ListArchivedFiles(context.Background(), tenantID, "", "", "", "all"); list != nil {
		for _, f := range list.Files {
			if y, err := strconv.Atoi(strings.TrimSpace(f.TargetYear)); err == nil && y > 0 {
				set[y] = true
			}
		}
	}
	out := make([]int, 0, len(set))
	for y := range set {
		out = append(out, y)
	}
	sort.Ints(out)
	return out
}

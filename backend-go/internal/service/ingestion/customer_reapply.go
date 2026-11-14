package ingestion

import (
	"context"
	"fmt"
	"log"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
)

type reapplyCtxKey struct{}

type reapplyScope struct {
	chains map[string]bool
	notes  *[]string
}

// withReapplyChains marks a confirmation re-apply: ProcessSellInPlan keeps only rows of these chains.
func withReapplyChains(ctx context.Context, chains map[string]bool, notes *[]string) context.Context {
	return context.WithValue(ctx, reapplyCtxKey{}, reapplyScope{chains: chains, notes: notes})
}

func reapplyChainsFrom(ctx context.Context) (map[string]bool, bool) {
	s, ok := ctx.Value(reapplyCtxKey{}).(reapplyScope)
	if !ok || len(s.chains) == 0 {
		return nil, false
	}
	return s.chains, true
}

func filterSellInByChain(recs []domain.SellInRecord, chains map[string]bool) []domain.SellInRecord {
	out := recs[:0:0]
	for _, r := range recs {
		if chains[storedChain(r)] {
			out = append(out, r)
		}
	}
	return out
}

// checkReapplyOwnsMonths: a re-apply must never wipe another file's rows. A (chain, month) that
// already holds rows from other files while this file holds none there was never replaced by this
// file, so re-applying would delete the other file's data; such a month is refused (no guessing).
func (p *Processor) checkReapplyOwnsMonths(tenantID, filename string, recs []domain.SellInRecord) error {
	snap, ok := p.bqRepo.(sellInSnapshotter)
	if !ok || len(recs) == 0 {
		return nil
	}
	want := map[string]bool{}
	for _, r := range recs {
		want[storedChain(r)+"|"+periodKey(r.Year, r.MonthNum)] = true
	}
	mine, others := map[string]int{}, map[string]int{}
	for _, r := range snap.SellInRecordsSnapshot(tenantID) {
		ch := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if ch == "" {
			ch = "fathalla"
		}
		k := ch + "|" + periodKey(r.Year, r.MonthNum)
		if !want[k] {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(r.SourceFilename), strings.TrimSpace(filename)) {
			mine[k]++
		} else {
			others[k]++
		}
	}
	var bad []string
	for k := range want {
		if mine[k] == 0 && others[k] > 0 {
			bad = append(bad, fmt.Sprintf("%s (%d صف من ملفات تانية)", k, others[k]))
		}
	}
	if len(bad) == 0 {
		return nil
	}
	sort.Strings(bad)
	return fmt.Errorf("الملف %s مااتعادش: الشهور دي فيها بيانات من ملفات تانية والملف ده ماكانش استبدلها وقت الرفع، فإعادة تشغيله كانت هتمسحها: %s. ارفع الملف تاني وأكد الاستبدال لو ده المطلوب. مفيش حاجة اتغيرت",
		filename, strings.Join(bad, "، "))
}

// ReapplyResult describes one re-run file.
type ReapplyResult struct {
	File      string `json:"file"`
	ArchiveID string `json:"archive_id"`
	BatchID   string `json:"batch_id"`
	Rows      int    `json:"rows"`
}

// ReapplySellInFiles re-processes archived Sell-In files after a customer-registry decision, so
// an approved name's rows enter the totals (or an unmerged name's rows leave them) without a
// re-upload. files == nil means every archived Sell-In file of the tenant. Runs non-interactively
// (no confirmation guards), exactly like the startup archive replay.
//
// chains != nil (confirmation): only rows of those chains are rewritten, files run in original
// upload order, and every later Sell-In file whose months overlap on those chains is re-run after
// them, so the per-(chain, month) replacement stays as it was at upload time. A requested file
// that is missing from the archive is an error, never a silent no-op.
func (p *Processor) ReapplySellInFiles(ctx context.Context, tenantID string, files []string, chains []string) (applied []ReapplyResult, errs []string) {
	want := map[string]bool{}
	for _, f := range files {
		want[strings.TrimSpace(f)] = true
	}
	chainSet := map[string]bool{}
	for _, c := range chains {
		if c = strings.ToLower(strings.TrimSpace(c)); c != "" {
			chainSet[c] = true
		}
	}
	if len(chainSet) > 0 && p.sellIn != nil {
		// The ownership check needs the durable rows in memory; never re-apply against a partial copy.
		if _, err := p.SyncSellInFromStore(ctx, tenantID, false); err != nil {
			return nil, []string{"مقدرناش نقرا البيانات المحفوظة قبل إعادة التشغيل، فمفيش حاجة اتعادت: " + err.Error()}
		}
	}
	list := p.ListArchivedFiles(ctx, tenantID, "", "", "", "sell_in")
	var all []ArchivedFile
	if list != nil {
		for _, f := range list.Files {
			if isSellInArchiveEntry(f) {
				all = append(all, *f)
			}
		}
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].UploadedAt < all[j].UploadedAt })
	found := map[string]bool{}
	var run []ArchivedFile
	if files == nil {
		run = all
	} else {
		first := -1
		months := map[string]bool{}
		for i, f := range all {
			if want[f.FileName] && !found[f.FileName] {
				found[f.FileName] = true
				run = append(run, f)
				if first < 0 {
					first = i
				}
				for _, m := range archiveMonths(f) {
					months[m] = true
				}
			}
		}
		for f := range want {
			if !found[f] {
				errs = append(errs, fmt.Sprintf("%s: الملف مش موجود في الأرشيف، فصفوفه مادخلتش. ارفع الملف تاني", f))
			}
		}
		if len(chainSet) > 0 && first >= 0 {
			// Later uploads on the same chain(s) and overlapping months must win again, as at upload time.
			inRun := map[string]bool{}
			for _, f := range run {
				inRun[f.ID] = true
			}
			for _, f := range all[first+1:] {
				// Any upload chain: a row's stored chain can differ from the file's upload chain (chain
				// rules); the chain filter in ProcessSellInPlan keeps only the confirmed chain's rows.
				if inRun[f.ID] {
					continue
				}
				overlap := false
				for _, m := range archiveMonths(f) {
					overlap = overlap || months[m]
				}
				if overlap {
					run = append(run, f)
					inRun[f.ID] = true
				}
			}
			sort.SliceStable(run, func(i, j int) bool { return run[i].UploadedAt < run[j].UploadedAt })
		}
	}
	var notes []string
	rctx := ctx
	if len(chainSet) > 0 {
		rctx = withReapplyChains(ctx, chainSet, &notes)
	}
	for _, f := range run {
		entry, raw, err := p.GetArchivedFile(ctx, tenantID, f.ID)
		if err != nil || len(raw) == 0 {
			errs = append(errs, fmt.Sprintf("%s: الملف مش موجود في الأرشيف", f.FileName))
			continue
		}
		res, err := p.ProcessSellInPlan(rctx, tenantID, entry.FileName, raw, false, entry.RetailChain)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", entry.FileName, err))
			continue
		}
		ar := ReapplyResult{File: entry.FileName, ArchiveID: res.ArchiveID, BatchID: res.BatchID, Rows: res.ValidRows}
		applied = append(applied, ar)
		log.Printf("[customer-reapply] tenant=%s chains=%v file=%q archive=%s batch=%s rows=%d", tenantID, sortedKeys(chainSet), ar.File, ar.ArchiveID, ar.BatchID, ar.Rows)
	}
	errs = append(errs, notes...)
	if len(applied) > 0 {
		p.ScheduleSnapshot()
	}
	return applied, errs
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// archiveMonths expands an archive entry's target period ("2026", "07" or "08-09") to "YYYY-MM".
func archiveMonths(f ArchivedFile) []string {
	y, err := strconv.Atoi(strings.TrimSpace(f.TargetYear))
	if err != nil || y <= 0 {
		return nil
	}
	tm := strings.TrimSpace(f.TargetMonth)
	lo, hi := 1, 12
	if a, b, ok := strings.Cut(tm, "-"); ok {
		lo, _ = strconv.Atoi(a)
		hi, _ = strconv.Atoi(b)
	} else if m, err := strconv.Atoi(tm); err == nil {
		lo, hi = m, m
	}
	if lo < 1 || hi > 12 || lo > hi {
		lo, hi = 1, 12
	}
	var out []string
	for m := lo; m <= hi; m++ {
		out = append(out, periodKey(y, m))
	}
	return out
}

// SellOutMonths returns distinct Sell-Out calendar months (1..12) with facts for tenant/year.
// Used by GET /api/v1/sell-out/months so competitor comparison grows as uploads add months.
func (p *Processor) SellOutMonths(tenantID string, year int) []int {
	type sellOutMonthLister interface {
		SellOutMonths(tenantID string, year int) []int
	}
	if lister, ok := p.bqRepo.(sellOutMonthLister); ok && p.bqRepo != nil {
		return lister.SellOutMonths(tenantID, year)
	}
	return nil
}

// SellInYears returns the years that have counted Sell-In rows or archived files with counted rows.
// A file whose rows are all quarantined (rows_ingested = 0) adds no year.
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
			if isSellInArchiveEntry(f) && f.RowsIngested == 0 {
				continue
			}
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

type sellInEnricher interface {
	EnrichSellInRecords(tenantID string, recs []domain.SellInRecord) []domain.SellInRecord
}

// unknownBarcodesAll reports items missing from the Product Master over every row of the file,
// counted and quarantined (read-only enrichment; nothing is stored). Always enriches via
// EnrichSellInRecords so dry-run previews (which never call SetSellInRecords) still get accurate counts.
func (p *Processor) unknownBarcodesAll(tenantID string, kept, all []domain.SellInRecord) ([]UnknownBarcode, *UploadIssue) {
	source := all
	if len(source) == 0 {
		source = kept
	}
	en, ok := p.bqRepo.(sellInEnricher)
	if !ok {
		return unknownBarcodes(kept)
	}
	rows := en.EnrichSellInRecords(tenantID, source)
	u, issue := unknownBarcodes(rows)
	if issue != nil && len(all) != len(kept) {
		issue.MessageAR += " (جزء من الصفوف دي محجوز لعملاء مش متأكدين ومش داخل في الإجماليات)"
	}
	return u, issue
}

// CustomerLiveStat is the in-totals Sell-In footprint of one customer name.
type CustomerLiveStat struct {
	Name  string   `json:"name"`
	Chain string   `json:"chain"`
	Rows  int      `json:"rows"`
	Value float64  `json:"value"`
	Files []string `json:"files,omitempty"`
}

// SellInCustomerLiveStats sums counted Sell-In rows by normalized customer name.
func (p *Processor) SellInCustomerLiveStats(tenantID string) map[string]CustomerLiveStat {
	snap, ok := p.bqRepo.(sellInSnapshotter)
	if !ok || p.bqRepo == nil {
		return nil
	}
	out := map[string]CustomerLiveStat{}
	seenFile := map[string]map[string]bool{}
	for _, rec := range snap.SellInRecordsSnapshot(tenantID) {
		key := customers.NormalizeName(rec.CustomerName)
		if key == "" {
			continue
		}
		st := out[key]
		if st.Name == "" {
			st.Name = strings.TrimSpace(rec.CustomerName)
		}
		if st.Chain == "" {
			st.Chain = storedChain(rec)
		}
		st.Rows++
		st.Value += rec.NetValueEGP
		if fn := strings.TrimSpace(rec.SourceFilename); fn != "" {
			if seenFile[key] == nil {
				seenFile[key] = map[string]bool{}
			}
			if !seenFile[key][fn] {
				seenFile[key][fn] = true
				st.Files = append(st.Files, fn)
			}
		}
		out[key] = st
	}
	return out
}

package ingestion

import (
	"context"
	"log"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// AliasRemapResult summarizes one apply/restore pass.
type AliasRemapResult struct {
	Remapped  int      `json:"remapped"`
	Restored  int      `json:"restored"`
	Decisions int      `json:"decisions,omitempty"`
	Sources   []string `json:"sources,omitempty"`
	Errors    []string `json:"errors,omitempty"`
}

type sellInAttributionWriter interface {
	RemapSellInCustomer(ctx context.Context, tenantID, chain, fromName, toName, toBranch string) *bqsink.Result
	RemapSellInCustomerWithBranch(ctx context.Context, tenantID, chain, fromName, fromBranch, toName, toBranch string) *bqsink.Result
	RestoreSellInCustomerByIDs(ctx context.Context, tenantID, toName, toBranch string, recordIDs []string) *bqsink.Result
}

// ApplyCustomerAliasAttributions remaps in-memory (and durable) Sell-In rows for every
// exact recorded alias_of decision. Idempotent: rows already on the canonical name are
// left alone; only same-chain rows whose customer_name still matches the source spelling
// move. Never invents a merge — no alias_of means no remap.
func (p *Processor) ApplyCustomerAliasAttributions(ctx context.Context, tenantID string) AliasRemapResult {
	out := AliasRemapResult{}
	if p == nil || p.customers == nil {
		return out
	}
	if p.sellIn != nil {
		if _, err := p.SyncSellInFromStore(ctx, tenantID, false); err != nil {
			out.Errors = append(out.Errors, "مقدرناش نقرا البيانات المحفوظة قبل دمج العملاء: "+err.Error())
			return out
		}
	}
	snap, ok := p.bqRepo.(sellInSnapshotter)
	repl, replOK := p.bqRepo.(sellInReplacer)
	if !ok || !replOK || p.bqRepo == nil {
		return out
	}
	decisions := p.aliasDecisions(ctx, tenantID)
	out.Decisions = len(decisions)
	if len(decisions) == 0 {
		return out
	}
	recs := snap.SellInRecordsSnapshot(tenantID)
	targetBranch := targetBranchCodes(recs, decisions)
	changed := false
	for _, d := range decisions {
		srcBranch := gemini.BuildBranchStoreMetadata(d.chain, d.sourceName).ID
		ids, fromBranch, fromNames, n := remapRecords(recs, d, srcBranch, targetBranch[d.canKey])
		if n == 0 {
			log.Printf("[customer-alias] decision present but no rows tenant=%s source=%q → %q branch=%s", tenantID, d.sourceName, d.canonicalName, srcBranch)
			continue
		}
		changed = true
		out.Remapped += n
		out.Sources = append(out.Sources, d.sourceName)
		if fromBranch == "" {
			fromBranch = srcBranch
		}
		if err := p.customers.SetAliasMergeMeta(ctx, tenantID, d.sourceName, ids, fromBranch); err != nil {
			out.Errors = append(out.Errors, err.Error())
		}
		if w, ok := p.sink.(sellInAttributionWriter); ok && p.sinkActive() {
			c, cancel := sinkCtx(ctx)
			// Branch-aware DML covers registry spelling + rows still on the source fat_auto code.
			res := w.RemapSellInCustomerWithBranch(c, tenantID, d.chain, d.sourceName, srcBranch, d.canonicalName, targetBranch[d.canKey])
			// Also remap every distinct live spelling NormalizeName equated to the source
			// (e.g. glued vs spaced digit) when it differs from the registry Name.
			for _, spell := range fromNames {
				if spell == "" || spell == d.sourceName {
					continue
				}
				r2 := w.RemapSellInCustomerWithBranch(c, tenantID, d.chain, spell, "", d.canonicalName, targetBranch[d.canKey])
				if r2 != nil && r2.Failed() {
					out.Errors = append(out.Errors, "BigQuery remap "+spell+": "+r2.Error)
				}
			}
			cancel()
			p.noteSellInWritten(ctx, tenantID, res)
			if res != nil && res.Failed() {
				out.Errors = append(out.Errors, "BigQuery remap "+d.sourceName+": "+res.Error)
			}
		}
		log.Printf("[customer-alias] apply tenant=%s source=%q → %q chain=%s rows=%d spellings=%v", tenantID, d.sourceName, d.canonicalName, d.chain, n, fromNames)
	}
	if changed {
		repl.ReplaceSellInRecords(tenantID, recs)
		p.ScheduleSnapshot()
	}
	return out
}

// RestoreCustomerAliasAttribution undoes one merge: rows tracked on the source entry's
// MergedRecordIDs return to the source name/branch. If no meta is stored (legacy decision
// that never remapped), this is a no-op and the caller may fall back to archive re-apply.
func (p *Processor) RestoreCustomerAliasAttribution(ctx context.Context, tenantID, sourceName string) AliasRemapResult {
	out := AliasRemapResult{}
	if p == nil || p.customers == nil {
		return out
	}
	key := customers.NormalizeName(sourceName)
	var meta customers.Entry
	found := false
	for _, e := range p.customers.List(ctx, tenantID, "", false) {
		if e.Key == key {
			meta, found = e, true
			break
		}
	}
	if !found || len(meta.MergedRecordIDs) == 0 {
		return out
	}
	if p.sellIn != nil {
		if _, err := p.SyncSellInFromStore(ctx, tenantID, false); err != nil {
			out.Errors = append(out.Errors, "مقدرناش نقرا البيانات المحفوظة قبل التراجع عن الدمج: "+err.Error())
			return out
		}
	}
	snap, ok := p.bqRepo.(sellInSnapshotter)
	repl, replOK := p.bqRepo.(sellInReplacer)
	if !ok || !replOK || p.bqRepo == nil {
		return out
	}
	want := map[string]bool{}
	for _, id := range meta.MergedRecordIDs {
		if id = strings.TrimSpace(id); id != "" {
			want[id] = true
		}
	}
	recs := snap.SellInRecordsSnapshot(tenantID)
	toName := meta.Name
	toBranch := strings.TrimSpace(meta.MergedFromBranch)
	n := 0
	for i := range recs {
		if !want[strings.TrimSpace(recs[i].RecordID)] {
			continue
		}
		recs[i].CustomerName = toName
		recs[i].CustomerBranchCode = toBranch
		if toBranch == "" {
			st := gemini.BuildBranchStoreMetadata(storedChain(recs[i]), toName)
			recs[i].CustomerBranchCode = st.ID
		}
		n++
	}
	if n == 0 {
		_ = p.customers.ClearAliasMergeMeta(ctx, tenantID, sourceName)
		return out
	}
	repl.ReplaceSellInRecords(tenantID, recs)
	out.Restored = n
	out.Sources = []string{toName}
	if w, ok := p.sink.(sellInAttributionWriter); ok && p.sinkActive() {
		c, cancel := sinkCtx(ctx)
		res := w.RestoreSellInCustomerByIDs(c, tenantID, toName, toBranch, meta.MergedRecordIDs)
		cancel()
		p.noteSellInWritten(ctx, tenantID, res)
		if res != nil && res.Failed() {
			out.Errors = append(out.Errors, "BigQuery restore "+toName+": "+res.Error)
		}
	}
	if err := p.customers.ClearAliasMergeMeta(ctx, tenantID, sourceName); err != nil {
		out.Errors = append(out.Errors, err.Error())
	}
	p.ScheduleSnapshot()
	log.Printf("[customer-alias] restore tenant=%s source=%q rows=%d", tenantID, toName, n)
	return out
}

type aliasDecision struct {
	sourceName    string
	sourceKey     string
	canonicalName string
	canKey        string
	chain         string
}

func (p *Processor) aliasDecisions(ctx context.Context, tenantID string) []aliasDecision {
	entries := p.customers.List(ctx, tenantID, "", false)
	byKey := map[string]customers.Entry{}
	for _, e := range entries {
		byKey[e.Key] = e
	}
	var out []aliasDecision
	for _, e := range entries {
		if e.Status != customers.StatusApproved {
			continue
		}
		can := strings.TrimSpace(e.AliasOf)
		if can == "" {
			continue
		}
		canKey := customers.NormalizeName(can)
		if canKey == "" || canKey == e.Key {
			continue
		}
		chain := p.customers.EntryChain(e)
		if chain == "" {
			chain = "fathalla"
		}
		canName := can
		if ce, ok := byKey[canKey]; ok && strings.TrimSpace(ce.Name) != "" {
			canName = ce.Name
		}
		out = append(out, aliasDecision{
			sourceName:    e.Name,
			sourceKey:     e.Key,
			canonicalName: canName,
			canKey:        canKey,
			chain:         chain,
		})
	}
	return out
}

func targetBranchCodes(recs []domain.SellInRecord, decisions []aliasDecision) map[string]string {
	out := map[string]string{}
	want := map[string]bool{}
	for _, d := range decisions {
		want[d.canKey] = true
	}
	for _, r := range recs {
		key := customers.NormalizeName(r.CustomerName)
		if !want[key] {
			continue
		}
		if code := strings.TrimSpace(r.CustomerBranchCode); code != "" {
			out[key] = code
		}
	}
	for _, d := range decisions {
		if out[d.canKey] != "" {
			continue
		}
		st := gemini.BuildBranchStoreMetadata(d.chain, d.canonicalName)
		out[d.canKey] = st.ID
	}
	return out
}

func remapRecords(recs []domain.SellInRecord, d aliasDecision, sourceBranch, toBranch string) (ids []string, fromBranch string, fromNames []string, n int) {
	seenName := map[string]bool{}
	for i := range recs {
		nameKey := customers.NormalizeName(recs[i].CustomerName)
		code := strings.TrimSpace(recs[i].CustomerBranchCode)
		byName := nameKey == d.sourceKey
		byCode := sourceBranch != "" && code == sourceBranch
		if !byName && !byCode {
			continue
		}
		ch := storedChain(recs[i])
		if ch != "" && d.chain != "" && ch != d.chain {
			continue // never cross-chain
		}
		if fromBranch == "" {
			fromBranch = code
		}
		if spell := strings.TrimSpace(recs[i].CustomerName); spell != "" && !seenName[spell] {
			seenName[spell] = true
			fromNames = append(fromNames, spell)
		}
		if id := strings.TrimSpace(recs[i].RecordID); id != "" {
			ids = append(ids, id)
		}
		recs[i].CustomerName = d.canonicalName
		recs[i].CustomerBranchCode = toBranch
		if toBranch == "" {
			st := gemini.BuildBranchStoreMetadata(d.chain, d.canonicalName)
			recs[i].CustomerBranchCode = st.ID
		}
		n++
	}
	return ids, fromBranch, fromNames, n
}

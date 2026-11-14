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
	Remapped int      `json:"remapped"`
	Restored int      `json:"restored"`
	Sources  []string `json:"sources,omitempty"`
	Errors   []string `json:"errors,omitempty"`
}

type sellInAttributionWriter interface {
	RemapSellInCustomer(ctx context.Context, tenantID, chain, fromName, toName, toBranch string) *bqsink.Result
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
	if len(decisions) == 0 {
		return out
	}
	recs := snap.SellInRecordsSnapshot(tenantID)
	targetBranch := targetBranchCodes(recs, decisions)
	changed := false
	for _, d := range decisions {
		ids, fromBranch, n := remapRecords(recs, d, targetBranch[d.canKey])
		if n == 0 {
			continue
		}
		changed = true
		out.Remapped += n
		out.Sources = append(out.Sources, d.sourceName)
		if err := p.customers.SetAliasMergeMeta(ctx, tenantID, d.sourceName, ids, fromBranch); err != nil {
			out.Errors = append(out.Errors, err.Error())
		}
		if w, ok := p.sink.(sellInAttributionWriter); ok && p.sinkActive() {
			c, cancel := sinkCtx(ctx)
			res := w.RemapSellInCustomer(c, tenantID, d.chain, d.sourceName, d.canonicalName, targetBranch[d.canKey])
			cancel()
			p.noteSellInWritten(ctx, tenantID, res)
			if res != nil && res.Failed() {
				out.Errors = append(out.Errors, "BigQuery remap "+d.sourceName+": "+res.Error)
			}
		}
		log.Printf("[customer-alias] apply tenant=%s source=%q → %q chain=%s rows=%d", tenantID, d.sourceName, d.canonicalName, d.chain, n)
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

func remapRecords(recs []domain.SellInRecord, d aliasDecision, toBranch string) (ids []string, fromBranch string, n int) {
	for i := range recs {
		if customers.NormalizeName(recs[i].CustomerName) != d.sourceKey {
			continue
		}
		ch := storedChain(recs[i])
		if ch != "" && d.chain != "" && ch != d.chain {
			continue // never cross-chain
		}
		if fromBranch == "" {
			fromBranch = strings.TrimSpace(recs[i].CustomerBranchCode)
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
	return ids, fromBranch, n
}

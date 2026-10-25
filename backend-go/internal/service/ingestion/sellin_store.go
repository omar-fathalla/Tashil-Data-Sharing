package ingestion

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// Durable source of truth (Sell-In and Sell-Out)
//
// Uploads write Sell-In / Sell-Out rows to BigQuery (tashil_analytics.sell_in_records / sell_out_facts)
// through the sink. This file closes the loop so BigQuery, not one instance's memory, is authoritative:
//   - after a successful durable write, delete or tenant purge, the writer bumps a shared version doc in
//     Firestore (data_versions/<tenant>__sell_in, data_versions/<tenant>__sell_out);
//   - every instance polls those docs (default every 30s) and, when one differs from the version it
//     applied, reloads that dataset for the tenant from BigQuery and swaps it into memory;
//   - on startup, after the archive replay / snapshot restore, each instance loads from BigQuery once.
//
// Safety: an empty BigQuery result never wipes non-empty memory unless a version was bumped (i.e. a
// real delete happened somewhere), and read errors never touch memory.

// Version kinds stored in data_versions.
const (
	SellInVersionKind  = "sell_in"
	SellOutVersionKind = "sell_out"
)

// DefaultSellInSyncInterval bounds how stale one instance can be after another one changes durable data.
const DefaultSellInSyncInterval = 30 * time.Second

// DefaultDurableSyncInterval is the poll interval for both Sell-In and Sell-Out.
const DefaultDurableSyncInterval = DefaultSellInSyncInterval

// SellInReader reads durable Sell-In rows (implemented by *bqsink.BigQuerySink).
type SellInReader interface {
	ReadSellIn(ctx context.Context, tenantID string) ([]domain.SellInRecord, error)
}

// SellOutReader reads durable Sell-Out rows (implemented by *bqsink.BigQuerySink).
type SellOutReader interface {
	ReadSellOut(ctx context.Context, tenantID string) ([]domain.SellOutFact, error)
}

// DataVersionStore is the shared version counter (implemented by *firestore.Client).
type DataVersionStore interface {
	GetDataVersion(ctx context.Context, tenantID, kind string) (string, error)
	BumpDataVersion(ctx context.Context, tenantID, kind string) (string, error)
}

// Implemented by *bigquery.Client.
type sellInReplacer interface {
	ReplaceSellInRecords(tenantID string, records []domain.SellInRecord)
}
type sellOutReplacer interface {
	ReplaceSellOutFacts(tenantID string, facts []domain.SellOutFact)
}

// durableSync tracks one dataset kind. read returns the row count and a function that swaps the rows in.
type durableSync struct {
	kind     string
	read     func(ctx context.Context, tenant string) (int, func(), error)
	versions DataVersionStore
	mu       sync.Mutex
	applied  map[string]string // tenant -> version applied on this instance
	loaded   map[string]bool   // tenant -> loaded from BigQuery at least once
	syncMu   sync.Mutex        // serialises reloads
}

func newDurableSync(kind string, versions DataVersionStore, read func(context.Context, string) (int, func(), error)) *durableSync {
	return &durableSync{kind: kind, read: read, versions: versions, applied: map[string]string{}, loaded: map[string]bool{}}
}

// WithSellInStore makes BigQuery the source of truth for Sell-In. versions may be nil (single instance).
func (p *Processor) WithSellInStore(reader SellInReader, versions DataVersionStore) *Processor {
	if reader == nil {
		p.sellIn = nil
		return p
	}
	p.sellIn = newDurableSync(SellInVersionKind, versions, func(ctx context.Context, tenant string) (int, func(), error) {
		repl, ok := p.bqRepo.(sellInReplacer)
		if !ok {
			return 0, nil, nil
		}
		recs, err := reader.ReadSellIn(ctx, tenant)
		if err != nil {
			return 0, nil, err
		}
		return len(recs), func() { repl.ReplaceSellInRecords(tenant, recs) }, nil
	})
	return p
}

// WithSellOutStore makes BigQuery the source of truth for Sell-Out. versions may be nil (single instance).
func (p *Processor) WithSellOutStore(reader SellOutReader, versions DataVersionStore) *Processor {
	if reader == nil {
		p.sellOut = nil
		return p
	}
	p.sellOut = newDurableSync(SellOutVersionKind, versions, func(ctx context.Context, tenant string) (int, func(), error) {
		repl, ok := p.bqRepo.(sellOutReplacer)
		if !ok {
			return 0, nil, nil
		}
		facts, err := reader.ReadSellOut(ctx, tenant)
		if err != nil {
			return 0, nil, err
		}
		return len(facts), func() { repl.ReplaceSellOutFacts(tenant, facts) }, nil
	})
	return p
}

// noteWritten bumps the shared version after a durable change made by this instance.
func (s *durableSync) noteWritten(ctx context.Context, tenantID string, res *bqsink.Result) {
	if s == nil || s.versions == nil || res == nil || res.Failed() || res.Status == bqsink.StatusDisabled || res.Status == bqsink.StatusSkipped {
		return
	}
	tenant := bqsink.NormalizeTenant(tenantID)
	c, cancel := sinkCtx(ctx)
	defer cancel()
	v, err := s.versions.BumpDataVersion(c, tenant, s.kind)
	if err != nil {
		log.Printf("WARN [durable-store] %s tenant=%s version bump failed (other instances converge on next restart): %v", s.kind, tenant, err)
		return
	}
	s.mu.Lock()
	s.applied[tenant] = v // this instance already holds the new data
	s.mu.Unlock()
}

func (p *Processor) noteSellInWritten(ctx context.Context, tenantID string, res *bqsink.Result) {
	p.sellIn.noteWritten(ctx, tenantID, res)
}

func (p *Processor) noteSellOutWritten(ctx context.Context, tenantID string, res *bqsink.Result) {
	p.sellOut.noteWritten(ctx, tenantID, res)
}

func (s *durableSync) sync(ctx context.Context, tenantID string, force bool) (bool, error) {
	if s == nil {
		return false, nil
	}
	tenant := bqsink.NormalizeTenant(tenantID)
	s.syncMu.Lock()
	defer s.syncMu.Unlock()

	remote := ""
	if s.versions != nil {
		v, err := s.versions.GetDataVersion(ctx, tenant, s.kind)
		if err != nil {
			return false, err
		}
		remote = v
	}
	s.mu.Lock()
	cur := s.applied[tenant]
	loaded := s.loaded[tenant]
	s.mu.Unlock()
	if !force && loaded && cur == remote {
		return false, nil
	}

	n, apply, err := s.read(ctx, tenant)
	if err != nil {
		return false, err
	}
	mark := func() {
		s.mu.Lock()
		s.loaded[tenant] = true
		s.applied[tenant] = remote
		s.mu.Unlock()
	}
	if apply == nil || (n == 0 && remote == "") {
		mark()
		if apply != nil {
			log.Printf("[durable-store] %s tenant=%s BigQuery has no rows and no version yet; keeping in-memory data", s.kind, tenant)
		}
		return false, nil
	}
	apply()
	mark()
	log.Printf("[durable-store] %s tenant=%s loaded %d row(s) from BigQuery (version %q)", s.kind, tenant, n, remote)
	return true, nil
}

// SyncSellInFromStore reloads a tenant's Sell-In from BigQuery when the shared version changed
// (or always when force). It returns true when memory was replaced.
func (p *Processor) SyncSellInFromStore(ctx context.Context, tenantID string, force bool) (bool, error) {
	return p.sellIn.sync(ctx, tenantID, force)
}

// SyncSellOutFromStore is the Sell-Out counterpart of SyncSellInFromStore.
func (p *Processor) SyncSellOutFromStore(ctx context.Context, tenantID string, force bool) (bool, error) {
	return p.sellOut.sync(ctx, tenantID, force)
}

// SyncDurableFromStore syncs every configured dataset for a tenant; errors are logged per kind.
func (p *Processor) SyncDurableFromStore(ctx context.Context, tenantID string, force bool) bool {
	changed := false
	for _, s := range []*durableSync{p.sellIn, p.sellOut} {
		if s == nil {
			continue
		}
		c, err := s.sync(ctx, tenantID, force)
		if err != nil {
			log.Printf("WARN [durable-store] %s tenant=%s sync failed; keeping in-memory data: %v", s.kind, tenantID, err)
		}
		changed = changed || c
	}
	return changed
}

// RunSellInSync polls the shared versions (Sell-In and Sell-Out) for the given tenants until ctx is done.
func (p *Processor) RunSellInSync(ctx context.Context, tenants []string, every time.Duration) {
	p.RunDurableSync(ctx, tenants, every)
}

// RunDurableSync polls the shared versions for the given tenants until ctx is done.
func (p *Processor) RunDurableSync(ctx context.Context, tenants []string, every time.Duration) {
	if (p.sellIn == nil && p.sellOut == nil) || every <= 0 {
		return
	}
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			for _, tenant := range tenants {
				c, cancel := context.WithTimeout(ctx, sinkTimeout)
				if p.SyncDurableFromStore(c, tenant, false) {
					p.ScheduleSnapshot()
				}
				cancel()
			}
		}
	}
}

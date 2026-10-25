package ingestion

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// Sell-In durable source of truth
//
// Uploads already write Sell-In rows to BigQuery (tashil_analytics.sell_in_records) through the sink.
// This file closes the loop so BigQuery, not one instance's memory, is authoritative:
//   - after a successful durable write or delete, the writer bumps a shared version doc in Firestore
//     (data_versions/<tenant>__sell_in);
//   - every instance polls that doc (default every 30s) and, when it differs from the version it
//     applied, reloads the tenant's Sell-In rows from BigQuery and swaps them into memory;
//   - on startup, after the archive replay / snapshot restore, each instance loads from BigQuery once.

// SellInVersionKind is the data_versions kind used for Sell-In.
const SellInVersionKind = "sell_in"

// DefaultSellInSyncInterval bounds how stale one instance can be after another one changes Sell-In.
const DefaultSellInSyncInterval = 30 * time.Second

// SellInReader reads durable Sell-In rows (implemented by *bqsink.BigQuerySink).
type SellInReader interface {
	ReadSellIn(ctx context.Context, tenantID string) ([]domain.SellInRecord, error)
}

// DataVersionStore is the shared version counter (implemented by *firestore.Client).
type DataVersionStore interface {
	GetDataVersion(ctx context.Context, tenantID, kind string) (string, error)
	BumpDataVersion(ctx context.Context, tenantID, kind string) (string, error)
}

// sellInReplacer is implemented by *bigquery.Client.
type sellInReplacer interface {
	ReplaceSellInRecords(tenantID string, records []domain.SellInRecord)
}

type sellInStore struct {
	reader   SellInReader
	versions DataVersionStore
	mu       sync.Mutex
	applied  map[string]string // tenant -> version applied on this instance
	loaded   map[string]bool   // tenant -> loaded from BigQuery at least once
	syncMu   sync.Mutex        // serialises reloads
}

// WithSellInStore makes BigQuery the source of truth for Sell-In. versions may be nil (single instance).
func (p *Processor) WithSellInStore(reader SellInReader, versions DataVersionStore) *Processor {
	if reader == nil {
		p.sellIn = nil
		return p
	}
	p.sellIn = &sellInStore{reader: reader, versions: versions, applied: map[string]string{}, loaded: map[string]bool{}}
	return p
}

// noteSellInWritten bumps the shared version after a durable Sell-In change made by this instance.
func (p *Processor) noteSellInWritten(ctx context.Context, tenantID string, res *bqsink.Result) {
	s := p.sellIn
	if s == nil || s.versions == nil || res == nil || res.Failed() || res.Status == bqsink.StatusDisabled {
		return
	}
	tenant := bqsink.NormalizeTenant(tenantID)
	c, cancel := sinkCtx(ctx)
	defer cancel()
	v, err := s.versions.BumpDataVersion(c, tenant, SellInVersionKind)
	if err != nil {
		log.Printf("WARN [sell-in-store] tenant=%s version bump failed (other instances converge on next restart): %v", tenant, err)
		return
	}
	s.mu.Lock()
	s.applied[tenant] = v // this instance already holds the new data
	s.mu.Unlock()
}

// SyncSellInFromStore reloads a tenant's Sell-In from BigQuery when the shared version changed
// (or always when force). It returns true when memory was replaced.
//
// Safety: an empty BigQuery result never wipes non-empty memory unless a version was bumped
// (i.e. a real delete happened somewhere), so a missing/empty table cannot erase replayed data.
func (p *Processor) SyncSellInFromStore(ctx context.Context, tenantID string, force bool) (bool, error) {
	s := p.sellIn
	if s == nil {
		return false, nil
	}
	repl, ok := p.bqRepo.(sellInReplacer)
	if !ok {
		return false, nil
	}
	tenant := bqsink.NormalizeTenant(tenantID)
	s.syncMu.Lock()
	defer s.syncMu.Unlock()

	remote := ""
	if s.versions != nil {
		v, err := s.versions.GetDataVersion(ctx, tenant, SellInVersionKind)
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

	recs, err := s.reader.ReadSellIn(ctx, tenant)
	if err != nil {
		return false, err
	}
	if len(recs) == 0 && remote == "" {
		s.mu.Lock()
		s.loaded[tenant] = true
		s.applied[tenant] = remote
		s.mu.Unlock()
		log.Printf("[sell-in-store] tenant=%s BigQuery has no Sell-In rows and no version yet; keeping in-memory data", tenant)
		return false, nil
	}
	repl.ReplaceSellInRecords(tenant, recs)
	s.mu.Lock()
	s.loaded[tenant] = true
	s.applied[tenant] = remote
	s.mu.Unlock()
	log.Printf("[sell-in-store] tenant=%s loaded %d Sell-In row(s) from BigQuery (version %q)", tenant, len(recs), remote)
	return true, nil
}

// RunSellInSync polls the shared version for the given tenants until ctx is done.
func (p *Processor) RunSellInSync(ctx context.Context, tenants []string, every time.Duration) {
	if p.sellIn == nil || every <= 0 {
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
				if changed, err := p.SyncSellInFromStore(c, tenant, false); err != nil {
					log.Printf("WARN [sell-in-store] tenant=%s sync failed: %v", tenant, err)
				} else if changed {
					p.ScheduleSnapshot()
				}
				cancel()
			}
		}
	}
}

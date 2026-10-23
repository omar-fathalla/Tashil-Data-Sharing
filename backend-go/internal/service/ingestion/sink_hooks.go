package ingestion

import (
	"context"
	"log"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// sinkTimeout bounds one durable BigQuery write so an upload request cannot hang indefinitely.
const sinkTimeout = 120 * time.Second

// WithSink attaches the durable BigQuery sink. A nil sink disables durable writes.
func (p *Processor) WithSink(s bqsink.Sink) *Processor {
	if s == nil {
		s = bqsink.Noop{}
	}
	p.sink = s
	return p
}

// sinkActive reports whether durable writes should happen now (never during startup archive replay,
// because the replayed files are already in BigQuery).
func (p *Processor) sinkActive() bool {
	return p.sink != nil && p.sink.Enabled() && !p.replaying.Load()
}

func sinkCtx(ctx context.Context) (context.Context, context.CancelFunc) {
	// Detach from request cancellation so a client disconnect cannot leave a half-finished write.
	return context.WithTimeout(context.WithoutCancel(ctx), sinkTimeout)
}

func logSinkFailure(kind string, meta bqsink.Meta, res *bqsink.Result) {
	if res.Failed() {
		log.Printf("ERROR [ingestion] %s upload %q (tenant=%s batch=%s) is live in the portal but NOT persisted to BigQuery: %s", kind, meta.SourceFile, meta.TenantID, meta.BatchID, res.Error)
	}
}

func (p *Processor) sinkSellOut(ctx context.Context, meta bqsink.Meta, facts []domain.SellOutFact, mode bqsink.SellOutMode) *bqsink.Result {
	if !p.sinkActive() {
		return nil
	}
	c, cancel := sinkCtx(ctx)
	defer cancel()
	res := p.sink.WriteSellOut(c, meta, facts, mode)
	logSinkFailure("sell-out", meta, res)
	return res
}

func (p *Processor) sinkSellIn(ctx context.Context, meta bqsink.Meta, records []domain.SellInRecord) *bqsink.Result {
	if !p.sinkActive() {
		return nil
	}
	c, cancel := sinkCtx(ctx)
	defer cancel()
	res := p.sink.WriteSellIn(c, meta, records)
	logSinkFailure("sell-in", meta, res)
	return res
}

func (p *Processor) sinkProductMaster(ctx context.Context, meta bqsink.Meta, summary *domain.ProductMasterSummaryResponse) *bqsink.Result {
	if !p.sinkActive() {
		return nil
	}
	c, cancel := sinkCtx(ctx)
	defer cancel()
	res := p.sink.WriteProductMaster(c, meta, summary)
	logSinkFailure("product-master", meta, res)
	return res
}

func (p *Processor) sinkDeleteArchived(ctx context.Context, entry *ArchivedFile) *bqsink.Result {
	if entry == nil || !p.sinkActive() {
		return nil
	}
	kind := bqsink.KindSellOut
	if isProductMasterArchiveEntry(entry) {
		kind = bqsink.KindProductMaster
	} else if isSellInArchiveEntry(entry) {
		kind = bqsink.KindSellIn
	}
	meta := bqsink.Meta{TenantID: entry.TenantID, BatchID: entry.BatchID, ArchiveID: entry.ID, SourceFile: entry.FileName}
	c, cancel := sinkCtx(ctx)
	defer cancel()
	res := p.sink.DeleteBatch(c, kind, meta)
	if res.Failed() {
		log.Printf("ERROR [ingestion] archive %s deleted from portal but its BigQuery rows were NOT removed: %s", entry.ID, res.Error)
	}
	return res
}

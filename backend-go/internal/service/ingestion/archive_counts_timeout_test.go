package ingestion

import (
	"context"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// slowCountSink blocks ArchiveRowCounts until its context is cancelled.
type slowCountSink struct{ fakeSink }

func (s *slowCountSink) ArchiveRowCounts(ctx context.Context, _ string) ([]bqsink.ArchiveRows, error) {
	<-ctx.Done()
	return nil, ctx.Err()
}

func (s *slowCountSink) DeleteOrphans(context.Context, bqsink.Kind, string, []string, []string) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusOK}
}

func TestListArchivedFilesDoesNotHangOnSlowBigQueryCounts(t *testing.T) {
	old := archiveCountsTimeout
	archiveCountsTimeout = 50 * time.Millisecond
	defer func() { archiveCountsTimeout = old }()

	p := newTestProcessor(t, t.TempDir())
	p.SaveArchivedFile("tenant-adeco", "batch_out", "out26.xlsx", []byte("x"), "fathalla", "2026", "01", 900, 3, 100, 0, 0, 1234)
	p.WithSink(&slowCountSink{})

	start := time.Now()
	list := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out")
	if d := time.Since(start); d > 2*time.Second {
		t.Fatalf("list blocked on BigQuery for %s", d)
	}
	if list.TotalCount != 1 || list.Files[0].RowsIngested != 900 || list.Files[0].TotalUnits != 1234 {
		t.Fatalf("on timeout the listed values must be kept: %+v", list.Files)
	}
}

package ingestion

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

type reconcileSink struct {
	fakeSink
	mu     sync.Mutex
	events []string
	stored []bqsink.ArchiveRows
}

func (r *reconcileSink) ArchiveRowCounts(context.Context, string) ([]bqsink.ArchiveRows, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, "count")
	return r.stored, nil
}

func (r *reconcileSink) DeleteOrphans(_ context.Context, k bqsink.Kind, _ string, _, _ []string) *bqsink.Result {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, "orphans:"+string(k))
	return &bqsink.Result{Status: bqsink.StatusOK}
}

func reconcileFixture(t *testing.T) (*Processor, *reconcileSink) {
	t.Helper()
	p := newTestProcessor(t, t.TempDir())
	s := &reconcileSink{stored: []bqsink.ArchiveRows{
		{Kind: bqsink.KindSellOut, SourceFile: "Book3.xlsx", Rows: 4090}, // deleted file
	}}
	p.WithSink(s)
	p.archiveMu.Lock()
	// A live sell-out file and a large sell-in file still missing from BigQuery (no bytes on disk here,
	// so the write is a no-op; the test only checks that orphan deletion does not depend on it).
	p.archivedFiles["arch_out"] = &ArchivedFile{ID: "arch_out", TenantID: "tenant-adeco", FileName: "2025 out.xlsx", FileType: "sell_out"}
	p.archivedFiles["arch_sellin_in26"] = &ArchivedFile{ID: "arch_sellin_in26", TenantID: "tenant-adeco", BatchID: "batch_sellin_1", FileName: "in26.xlsx", FileType: "sell_in", StoragePath: "/nonexistent/in26.xlsx"}
	p.archiveMu.Unlock()
	return p, s
}

func TestArchiveSyncDeletesOrphansBeforeLargeWrites(t *testing.T) {
	p, s := reconcileFixture(t)
	rep, err := p.ReconcileArchivesToSink(context.Background(), "tenant-adeco", true)
	if err != nil {
		t.Fatal(err)
	}
	if rep.OrphanRows["sell_out"] != 4090 || !rep.OrphanDeleted["sell_out"] {
		t.Fatalf("Book3 orphans must be deleted: %+v", rep)
	}
	if len(s.events) < 2 || s.events[0] != "count" || s.events[1] != "orphans:sell_out" {
		t.Fatalf("orphan deletion must run right after the first count, before any archive write: %v", s.events)
	}
}

func TestArchiveSyncRunsOnOneInstanceOnly(t *testing.T) {
	leases := firestore.NewClient("db", true)
	p, s := reconcileFixture(t)
	p.WithSyncLease(leases)
	// Another instance holds the lease.
	if ok, _ := leases.TryAcquireLease(context.Background(), "archive-sync__tenant-adeco", "other-instance", time.Hour); !ok {
		t.Fatal("setup: lease")
	}
	rep, err := p.ReconcileArchivesToSink(context.Background(), "tenant-adeco", true)
	if err != nil {
		t.Fatal(err)
	}
	if rep.Skipped == "" {
		t.Fatal("must skip while another instance holds the lease")
	}
	for _, e := range s.events {
		if e != "count" {
			t.Fatalf("skipped instance must not write or delete: %v", s.events)
		}
	}

	// Once released, this instance runs and releases the lease when done.
	_ = leases.ReleaseLease(context.Background(), "archive-sync__tenant-adeco", "other-instance")
	rep, err = p.ReconcileArchivesToSink(context.Background(), "tenant-adeco", true)
	if err != nil || rep.Skipped != "" || !rep.OrphanDeleted["sell_out"] {
		t.Fatalf("free lease must run the sync: %+v %v", rep, err)
	}
	if ok, _ := leases.TryAcquireLease(context.Background(), "archive-sync__tenant-adeco", "next", time.Hour); !ok {
		t.Fatal("lease must be released after the sync")
	}
}

func TestArchiveSyncReportModeTakesNoLease(t *testing.T) {
	leases := firestore.NewClient("db", true)
	p, s := reconcileFixture(t)
	p.WithSyncLease(leases)
	_, _ = leases.TryAcquireLease(context.Background(), "archive-sync__tenant-adeco", "other", time.Hour)
	rep, err := p.ReconcileArchivesToSink(context.Background(), "tenant-adeco", false)
	if err != nil || rep.Skipped != "" || rep.OrphanRows["sell_out"] != 4090 || len(s.events) != 1 {
		t.Fatalf("report mode must only count: %+v %v %v", rep, err, s.events)
	}
}

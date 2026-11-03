package ingestion

import (
	"bytes"
	"context"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// heldLease simulates another instance holding every lease.
type heldLease struct{}

func (heldLease) TryAcquireLease(context.Context, string, string, time.Duration) (bool, error) {
	return false, nil
}
func (heldLease) ReleaseLease(context.Context, string, string) error { return nil }

func TestBackgroundRebuildRunsOnceForConcurrentRequests(t *testing.T) {
	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	p, pBQ, pFS := newSnapshotTestProcessor(t, dir)
	_, srcBQ, srcFS := newSnapshotTestProcessor(t, t.TempDir())
	seedSnapshotData(t, srcBQ, srcFS)
	wantBQ, wantFS := exportBoth(t, srcBQ, srcFS)

	var calls atomic.Int32
	gate := make(chan struct{})
	p.WithBackgroundRebuild(func(context.Context) ([]byte, []byte, error) {
		calls.Add(1)
		<-gate
		return wantBQ, wantFS, nil
	})
	var wg sync.WaitGroup
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); p.runBackgroundRebuild(context.Background()) }()
	}
	time.Sleep(100 * time.Millisecond)
	close(gate)
	wg.Wait()
	if n := calls.Load(); n != 1 {
		t.Fatalf("concurrent rebuild requests must run the rebuild once, ran %d times", n)
	}
	// The rebuilt state is swapped in unchanged and persisted for the next cold start.
	gotBQ, gotFS := exportBoth(t, pBQ, pFS)
	if !bytes.Equal(gotBQ, wantBQ) || !bytes.Equal(gotFS, wantFS) {
		t.Fatalf("rebuilt state differs from the replay result")
	}
	p2, _, _ := newSnapshotTestProcessor(t, dir)
	if mode, err := p2.RestoreOrReplay(context.Background()); err != nil || mode != "snapshot" {
		t.Fatalf("next cold start must restore the refreshed snapshot, got mode=%s err=%v", mode, err)
	}
}

func TestRebuildFollowerAdoptsSnapshotInsteadOfRebuilding(t *testing.T) {
	oldPoll := rebuildFollowerPoll
	rebuildFollowerPoll = 10 * time.Millisecond
	defer func() { rebuildFollowerPoll = oldPoll }()

	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	follower, fBQ, fFS := newSnapshotTestProcessor(t, dir)
	follower.WithSyncLease(heldLease{})
	var calls atomic.Int32
	follower.WithBackgroundRebuild(func(context.Context) ([]byte, []byte, error) {
		calls.Add(1)
		return nil, nil, nil
	})

	done := make(chan struct{})
	go func() { follower.runBackgroundRebuild(context.Background()); close(done) }()

	// The lease holder (another instance) finishes its rebuild and writes the snapshot.
	time.Sleep(50 * time.Millisecond)
	leader, lBQ, lFS := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, lBQ, lFS)
	if err := leader.WriteSnapshot(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("follower did not adopt the fresh snapshot")
	}
	if calls.Load() != 0 {
		t.Fatalf("follower must not run its own full rebuild while another instance holds the lease")
	}
	wantBQ, wantFS := exportBoth(t, lBQ, lFS)
	gotBQ, gotFS := exportBoth(t, fBQ, fFS)
	if !bytes.Equal(wantBQ, gotBQ) || !bytes.Equal(wantFS, gotFS) {
		t.Fatalf("adopted state differs from the leader's snapshot")
	}
}

func TestArchiveListNotBlockedWhileReplayRuns(t *testing.T) {
	dir := t.TempDir()
	p, _, _ := newSnapshotTestProcessor(t, dir)
	p.SaveArchivedFile("tenant-adeco", "batch_sellin_1", "in26.xlsx", []byte("wb"), "fathalla", "2026", "01", 1, 1, 1)

	// A replay / rebuild is in progress on this instance.
	p.heavyMu.Lock()
	defer p.heavyMu.Unlock()

	got := make(chan *ArchiveListResponse, 1)
	go func() {
		got <- p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "")
	}()
	select {
	case resp := <-got:
		if resp == nil {
			t.Fatal("archive list returned nothing")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("archive list blocked behind the replay")
	}

	// A snapshot export waits for the replay instead of running alongside it.
	wrote := make(chan struct{})
	go func() { _ = p.WriteSnapshot(); close(wrote) }()
	select {
	case <-wrote:
		t.Fatal("snapshot export ran concurrently with the replay")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestReplayResaveKeepsSnapshotValid(t *testing.T) {
	dir := t.TempDir()
	p, bq, fsr := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, bq, fsr)
	e := p.SaveArchivedFile("tenant-adeco", "batch_sellin_1", "in26.xlsx", []byte("wb"), "fathalla", "2026", "01", 1, 1, 1)
	if err := p.WriteSnapshot(); err != nil {
		t.Fatal(err)
	}
	before, _ := os.Stat(e.StoragePath)
	time.Sleep(20 * time.Millisecond)

	// Another instance replays the same archive (same bytes): the workbook must not be rewritten.
	other, _, _ := newSnapshotTestProcessor(t, dir)
	other.SaveArchivedFile("tenant-adeco", "batch_sellin_2", "in26.xlsx", []byte("wb"), "fathalla", "2026", "01", 1, 1, 1)
	after, _ := os.Stat(e.StoragePath)
	if !after.ModTime().Equal(before.ModTime()) {
		t.Fatalf("replay rewrote identical workbook bytes (mtime %v -> %v)", before.ModTime(), after.ModTime())
	}
	next, _, _ := newSnapshotTestProcessor(t, dir)
	added, err := next.loadSnapshotIncremental()
	if err != nil || len(added) != 0 {
		t.Fatalf("snapshot must stay valid after a replay elsewhere, got added=%v err=%v", added, err)
	}
}

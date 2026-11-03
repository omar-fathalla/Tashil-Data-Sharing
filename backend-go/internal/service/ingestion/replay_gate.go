package ingestion

import (
	"context"
	"log"
	"strings"
	"time"
)

// Replay / rebuild gate (prod OOM fix, 2026-11-03)
//
// One Cloud Run instance (2Gi, 1 CPU) was OOM-killed while a full archive rebuild, the BigQuery archive sync
// and snapshot exports (~430MB of JSON each) ran at the same time, and all three instances did the same full
// rebuild together. Two rules now apply:
//   - within an instance, memory-heavy work (full or incremental replay, background rebuild, archive-sync
//     writes, snapshot export) runs one at a time (heavyMu), and a background rebuild runs at most once;
//   - across instances, a full background rebuild takes the "snapshot-rebuild" lease. Instances that do not
//     get it keep serving their current state and adopt the fresh snapshot the holder writes, instead of
//     repeating the same rebuild.

const snapshotRebuildLeaseName = "snapshot-rebuild"

var (
	// rebuildFollowerPoll is how often an instance without the rebuild lease checks for a fresh snapshot.
	rebuildFollowerPoll = 30 * time.Second
	// rebuildFollowerMaxWait bounds the wait; after it the instance rebuilds by itself.
	rebuildFollowerMaxWait = 20 * time.Minute
)

// withHeavy runs fn while holding the instance-wide heavy-work gate.
func (p *Processor) withHeavy(fn func()) {
	p.heavyMu.Lock()
	defer p.heavyMu.Unlock()
	fn()
}

// holdLease acquires a named cross-instance lease and renews it until release is called.
// Without a lease backend (tests, local) it always succeeds.
func (p *Processor) holdLease(ctx context.Context, name string) (ok bool, release func(), err error) {
	if p.syncLease == nil {
		return true, func() {}, nil
	}
	holder := syncLeaseHolder()
	ok, err = p.syncLease.TryAcquireLease(ctx, name, holder, archiveSyncLeaseTTL)
	if err != nil || !ok {
		return false, func() {}, err
	}
	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		t := time.NewTicker(archiveSyncLeaseTTL / 3)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				if _, err := p.syncLease.TryAcquireLease(context.Background(), name, holder, archiveSyncLeaseTTL); err != nil {
					log.Printf("WARN [lease] %s renew: %v", name, err)
				}
			}
		}
	}()
	return true, func() {
		close(stop)
		<-done
		rctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := p.syncLease.ReleaseLease(rctx, name, holder); err != nil {
			log.Printf("WARN [lease] %s release: %v", name, err)
		}
	}, nil
}

// tryAdoptSnapshot loads a current snapshot (written by another instance) into the live stores and applies
// any workbooks added after it. It reports whether the snapshot was usable.
func (p *Processor) tryAdoptSnapshot(ctx context.Context) bool {
	var ok bool
	p.withHeavy(func() {
		added, err := p.loadSnapshotIncremental()
		if err != nil {
			return
		}
		ok = true
		if len(added) > 0 {
			_ = p.replayArchivedPathsLocked(ctx, added)
		}
	})
	return ok
}

// acquireRebuild decides whether this instance runs the full rebuild. It returns run=false when a fresh
// snapshot from the lease holder was adopted instead.
func (p *Processor) acquireRebuild(ctx context.Context) (run bool, release func()) {
	deadline := time.Now().Add(rebuildFollowerMaxWait)
	for {
		ok, rel, err := p.holdLease(ctx, snapshotRebuildLeaseName)
		if err != nil {
			log.Printf("WARN [Tashil Snapshot] rebuild lease: %v; rebuilding locally", err)
			return true, func() {}
		}
		if ok {
			return true, rel
		}
		if p.tryAdoptSnapshot(ctx) {
			log.Printf("[Tashil Snapshot] Adopted the snapshot rebuilt by another instance")
			return false, func() {}
		}
		if time.Now().After(deadline) {
			log.Printf("[Tashil Snapshot] Waited %s for another instance's rebuild; rebuilding locally", rebuildFollowerMaxWait)
			return true, func() {}
		}
		select {
		case <-ctx.Done():
			return false, func() {}
		case <-time.After(rebuildFollowerPoll):
		}
	}
}

func isArchiveListRequest(method, path string) bool {
	return method == "GET" && strings.TrimSuffix(path, "/") == "/api/v1/ingest/archive"
}

// IsArchiveListRequest reports the archive list endpoint, which reads only the archive index (loaded before
// the server listens) and so does not need to wait for the replayed dataset.
func IsArchiveListRequest(method, path string) bool { return isArchiveListRequest(method, path) }

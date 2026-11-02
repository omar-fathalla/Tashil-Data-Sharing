package ingestion

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// ArchiveSyncFile compares one archived upload with its rows stored in BigQuery.
type ArchiveSyncFile struct {
	Kind         string `json:"kind"`
	ArchiveID    string `json:"archive_id"`
	FileName     string `json:"file_name"`
	ArchiveRows  int    `json:"archive_rows"`  // rows_ingested recorded on the archive entry
	StoredBefore int    `json:"stored_before"` // rows keyed by this archive id
	LegacyBefore int    `json:"legacy_before"` // rows of the same file written before archive ids were recorded
	StoredAfter  int    `json:"stored_after"`
	Action       string `json:"action"` // ok | write | written | failed
}

// ArchiveSyncReport is the result of ReconcileArchivesToSink for one tenant.
type ArchiveSyncReport struct {
	TenantID      string            `json:"tenant_id"`
	Files         []ArchiveSyncFile `json:"files"`
	OrphanRows    map[string]int    `json:"orphan_rows"` // rows of deleted / unknown files, per kind
	OrphanDeleted map[string]bool   `json:"orphan_deleted,omitempty"`
	// Skipped is set when another instance holds the archive-sync lease, so this one did nothing.
	Skipped string `json:"skipped,omitempty"`
}

// SyncLease is a cross-instance lease (Firestore-backed in production) so that only one Cloud Run instance
// re-writes archives at a time; the others skip instead of repeating the same heavy work.
type SyncLease interface {
	TryAcquireLease(ctx context.Context, name, holder string, ttl time.Duration) (bool, error)
	ReleaseLease(ctx context.Context, name, holder string) error
}

// archiveSyncLeaseTTL bounds how long a crashed holder blocks other instances; a live holder renews it.
const archiveSyncLeaseTTL = 10 * time.Minute

// WithSyncLease makes ReconcileArchivesToSink(execute=true) run on one instance at a time.
func (p *Processor) WithSyncLease(l SyncLease) *Processor {
	p.syncLease = l
	return p
}

func syncLeaseHolder() string {
	h, _ := os.Hostname()
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%s-%d-%s", h, os.Getpid(), hex.EncodeToString(b))
}

// holdSyncLease acquires the tenant's archive-sync lease and keeps renewing it until release is called.
func (p *Processor) holdSyncLease(ctx context.Context, tenantID string) (ok bool, release func(), err error) {
	if p.syncLease == nil {
		return true, func() {}, nil
	}
	name := "archive-sync__" + tenantID
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
					log.Printf("WARN [archive-sync] lease renew: %v", err)
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
			log.Printf("WARN [archive-sync] lease release: %v", err)
		}
	}, nil
}

func archiveKind(e *ArchivedFile) bqsink.Kind {
	switch {
	case isProductMasterArchiveEntry(e):
		return bqsink.KindProductMaster
	case isSellInArchiveEntry(e):
		return bqsink.KindSellIn
	default:
		return bqsink.KindSellOut
	}
}

// PlanArchiveSync decides, from stored row counts, which archived files must be (re)written and how many
// stored rows belong to no live file. A file is rewritten when no row carries its archive id (missing, or
// only legacy rows without an archive id); a rewrite replaces the legacy rows of the same file.
func PlanArchiveSync(tenantID string, live []*ArchivedFile, stored []bqsink.ArchiveRows) *ArchiveSyncReport {
	rep := &ArchiveSyncReport{TenantID: tenantID, OrphanRows: map[string]int{}}
	liveIDs := map[string]bool{}
	liveFiles := map[string]bool{} // kind|lower(file)
	for _, e := range live {
		k := archiveKind(e)
		liveIDs[e.ID] = true
		liveFiles[string(k)+"|"+strings.ToLower(e.FileName)] = true
		f := ArchiveSyncFile{Kind: string(k), ArchiveID: e.ID, FileName: e.FileName, ArchiveRows: e.RowsIngested}
		for _, s := range stored {
			if s.Kind != k {
				continue
			}
			if s.ArchiveID == e.ID {
				f.StoredBefore += s.Rows
			} else if s.ArchiveID == "" && strings.EqualFold(s.SourceFile, e.FileName) {
				f.LegacyBefore += s.Rows
			}
		}
		f.StoredAfter = f.StoredBefore
		f.Action = "ok"
		if f.StoredBefore == 0 {
			f.Action = "write"
		}
		rep.Files = append(rep.Files, f)
	}
	for _, s := range stored {
		if s.ArchiveID != "" {
			if !liveIDs[s.ArchiveID] {
				rep.OrphanRows[string(s.Kind)] += s.Rows
			}
			continue
		}
		if !liveFiles[string(s.Kind)+"|"+strings.ToLower(s.SourceFile)] {
			rep.OrphanRows[string(s.Kind)] += s.Rows
		}
	}
	sort.Slice(rep.Files, func(i, j int) bool {
		if rep.Files[i].Kind != rep.Files[j].Kind {
			return rep.Files[i].Kind < rep.Files[j].Kind
		}
		return rep.Files[i].FileName < rep.Files[j].FileName
	})
	return rep
}

func (p *Processor) liveArchives(tenantID string) []*ArchivedFile {
	norm := normalizeArchiveTenantID(tenantID)
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()
	p.loadDiskArchiveLocked()
	var out []*ArchivedFile
	for _, e := range p.archivedFiles {
		if e == nil || e.TenantID != norm {
			continue
		}
		if p.fsRepo != nil && p.fsRepo.IsArchiveDeleted(e.TenantID, e.ID, e.FileName) {
			continue
		}
		out = append(out, e)
	}
	return out
}

// ReconcileArchivesToSink makes BigQuery hold every archived upload of a tenant in full: files with no rows
// under their archive id are re-parsed from the archive and written through the normal idempotent sink path,
// and rows of deleted files are removed. With execute=false it only reports. Re-parsing also refreshes the
// in-memory stores; callers should converge on BigQuery afterwards (SyncDurableFromStore).
func (p *Processor) ReconcileArchivesToSink(ctx context.Context, tenantID string, execute bool) (*ArchiveSyncReport, error) {
	if p.sink == nil || !p.sink.Enabled() {
		return nil, nil
	}
	rec, ok := p.sink.(bqsink.ArchiveReconciler)
	if !ok {
		return nil, nil
	}
	live := p.liveArchives(tenantID)
	stored, err := rec.ArchiveRowCounts(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	rep := PlanArchiveSync(bqsink.NormalizeTenant(tenantID), live, stored)
	if !execute {
		return rep, nil
	}

	ok, release, err := p.holdSyncLease(ctx, rep.TenantID)
	if err != nil {
		return rep, fmt.Errorf("archive-sync lease: %w", err)
	}
	if !ok {
		rep.Skipped = "another instance holds the archive-sync lease"
		log.Printf("[archive-sync] tenant=%s skipped: %s", rep.TenantID, rep.Skipped)
		return rep, nil
	}
	defer release()

	// Orphans first: deleting rows of removed files is cheap and must not wait behind (or be lost with) a large
	// archive write that can take minutes.
	p.deleteArchiveOrphans(ctx, rec, tenantID, live, rep)

	byID := map[string]*ArchivedFile{}
	for _, e := range live {
		byID[e.ID] = e
	}
	var toWrite []*ArchivedFile
	writePM := false
	for _, f := range rep.Files {
		if f.Action == "write" {
			toWrite = append(toWrite, byID[f.ArchiveID])
			if f.Kind == string(bqsink.KindProductMaster) {
				writePM = true
			}
		}
	}
	if writePM {
		// Re-parsing an older catalog would leave it active in memory: re-apply the newest one last.
		var latest *ArchivedFile
		for _, e := range live {
			if isProductMasterArchiveEntry(e) && (latest == nil || e.UploadedAt > latest.UploadedAt) {
				latest = e
			}
		}
		if latest != nil {
			found := false
			for _, e := range toWrite {
				found = found || e.ID == latest.ID
			}
			if !found {
				toWrite = append(toWrite, latest)
			}
		}
	}
	if len(toWrite) > 0 {
		sortArchiveReplayOrder(toWrite)
		log.Printf("[archive-sync] tenant=%s writing %d archived file(s) to BigQuery", rep.TenantID, len(toWrite))
		// One file at a time (replayFiles frees each workbook before the next), so peak memory is one file.
		for _, e := range toWrite {
			start := time.Now()
			p.replayFiles(ctx, []*ArchivedFile{e}, true)
			log.Printf("[archive-sync] tenant=%s wrote %q in %s", rep.TenantID, e.FileName, time.Since(start).Round(time.Millisecond))
		}
	}

	after, err := rec.ArchiveRowCounts(ctx, tenantID)
	if err != nil {
		return rep, fmt.Errorf("recount after sync: %w", err)
	}
	post := PlanArchiveSync(rep.TenantID, live, after)
	for i := range rep.Files {
		for _, a := range post.Files {
			if a.ArchiveID == rep.Files[i].ArchiveID {
				rep.Files[i].StoredAfter = a.StoredBefore
			}
		}
		if rep.Files[i].Action == "write" {
			if rep.Files[i].StoredAfter > 0 {
				rep.Files[i].Action = "written"
			} else {
				rep.Files[i].Action = "failed"
			}
		}
	}
	return rep, nil
}

// deleteArchiveOrphans removes rows of files that are no longer in the archive, per kind.
func (p *Processor) deleteArchiveOrphans(ctx context.Context, rec bqsink.ArchiveReconciler, tenantID string, live []*ArchivedFile, rep *ArchiveSyncReport) {
	kinds := make([]string, 0, len(rep.OrphanRows))
	for k := range rep.OrphanRows {
		kinds = append(kinds, k)
	}
	sort.Strings(kinds)
	for _, kind := range kinds {
		n := rep.OrphanRows[kind]
		if n == 0 {
			continue
		}
		var ids, files []string
		for _, e := range live {
			if string(archiveKind(e)) == kind {
				ids = append(ids, e.ID)
				files = append(files, e.FileName)
			}
		}
		if len(ids) == 0 {
			// No live file of this kind: deleting would wipe the table for the tenant; leave it for an explicit purge.
			log.Printf("WARN [archive-sync] tenant=%s kind=%s has %d orphan row(s) but no live file; not deleted", rep.TenantID, kind, n)
			continue
		}
		res := rec.DeleteOrphans(ctx, bqsink.Kind(kind), tenantID, ids, files)
		if rep.OrphanDeleted == nil {
			rep.OrphanDeleted = map[string]bool{}
		}
		rep.OrphanDeleted[kind] = res != nil && res.Status == bqsink.StatusOK
		log.Printf("[archive-sync] tenant=%s kind=%s orphan_rows=%d deleted=%v", rep.TenantID, kind, n, rep.OrphanDeleted[kind])
		switch bqsink.Kind(kind) {
		case bqsink.KindSellIn:
			p.noteSellInWritten(ctx, tenantID, res)
		case bqsink.KindSellOut:
			p.noteSellOutWritten(ctx, tenantID, res)
		}
	}
}

// LogArchiveSync prints one line per file so the before/after state is visible in Cloud Run logs.
func LogArchiveSync(rep *ArchiveSyncReport) {
	if rep == nil || rep.Skipped != "" {
		return
	}
	for _, f := range rep.Files {
		log.Printf("[archive-sync] tenant=%s %s %q archive=%s archive_rows=%d bq_before=%d legacy_before=%d bq_after=%d action=%s",
			rep.TenantID, f.Kind, f.FileName, f.ArchiveID, f.ArchiveRows, f.StoredBefore, f.LegacyBefore, f.StoredAfter, f.Action)
	}
	for k, n := range rep.OrphanRows {
		log.Printf("[archive-sync] tenant=%s %s orphan_rows=%d deleted=%v", rep.TenantID, k, n, rep.OrphanDeleted[k])
	}
}

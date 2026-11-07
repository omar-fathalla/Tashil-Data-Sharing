package ingestion

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// archiveSidecarDir holds one JSON metadata file per archived upload (<tenantDir>/entries/<archiveID>.json).
//
// index.json is rewritten wholesale by whichever Cloud Run instance handled the last upload, so two instances
// uploading at the same time could drop each other's entries. Each upload now also writes ONLY its own sidecar
// object, so concurrent uploads never overwrite each other's metadata. On load, sidecars are merged over
// index.json (sidecar wins), and deletions remain governed by the Firestore tombstones.
const archiveSidecarDir = "entries"

func sidecarName(id string) string {
	return sanitizeArchiveFilename(id) + ".json"
}

func (p *Processor) writeArchiveSidecarLocked(entry *ArchivedFile) {
	if p.archiveDir == "" || entry == nil || entry.ID == "" {
		return
	}
	dir := filepath.Join(p.archiveDir, entry.TenantID, archiveSidecarDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		log.Printf("ERROR [archive] cannot create sidecar dir %s: %v", dir, err)
		return
	}
	data, err := json.MarshalIndent(entry, "", "  ")
	if err != nil {
		return
	}
	final := filepath.Join(dir, sidecarName(entry.ID))
	tmp := final + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		log.Printf("ERROR [archive] cannot write sidecar %s: %v", final, err)
		return
	}
	if err := os.Rename(tmp, final); err != nil {
		// Some FUSE mounts reject rename-over; fall back to a direct write.
		_ = os.Remove(tmp)
		if err := os.WriteFile(final, data, 0o644); err != nil {
			log.Printf("ERROR [archive] cannot write sidecar %s: %v", final, err)
		}
	}
}

func (p *Processor) removeArchiveSidecarLocked(entry *ArchivedFile) {
	if p.archiveDir == "" || entry == nil || entry.ID == "" {
		return
	}
	_ = os.Remove(filepath.Join(p.archiveDir, entry.TenantID, archiveSidecarDir, sidecarName(entry.ID)))
}

// mergeArchiveSidecars overlays per-entry sidecar files from tenantDir onto the index.json list.
func mergeArchiveSidecars(list []*ArchivedFile, tenantDir string) []*ArchivedFile {
	files, err := os.ReadDir(filepath.Join(tenantDir, archiveSidecarDir))
	if err != nil {
		return list
	}
	byID := make(map[string]int, len(list))
	for i, it := range list {
		if it != nil {
			byID[it.ID] = i
		}
	}
	for _, f := range files {
		if f.IsDir() || !strings.HasSuffix(f.Name(), ".json") {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(tenantDir, archiveSidecarDir, f.Name()))
		if err != nil {
			continue
		}
		var item ArchivedFile
		if json.Unmarshal(raw, &item) != nil || item.ID == "" {
			continue
		}
		if i, ok := byID[item.ID]; ok {
			list[i] = &item
		} else {
			byID[item.ID] = len(list)
			list = append(list, &item)
		}
	}
	return list
}

// archiveDiskSyncInterval bounds how often a list call rescans the shared archive mount.
const archiveDiskSyncInterval = 10 * time.Second

func archiveEntryKind(entry *ArchivedFile) string {
	if isProductMasterArchiveEntry(entry) {
		return "product_master"
	}
	if isSellInArchiveEntry(entry) {
		return "sell_in"
	}
	return "sell_out"
}

// refreshArchiveTombstonesAlways applies shared-mount (+ optional Firestore) deletion tombstones and
// prunes matching in-memory entries. Runs on every list/delete — not throttled — so a simple page
// refresh cannot flap a just-deleted Sell-In/Sell-Out row back into the UI when the request hits a
// peer Cloud Run instance that still holds the startup copy.
func (p *Processor) refreshArchiveTombstonesAlways(ctx context.Context) {
	if p.archiveDir == "" && p.fsRepo == nil {
		return
	}
	if p.fsRepo != nil {
		p.fsRepo.RefreshDeletedArchives(ctx)
	}
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()
	p.applyDiskTombstonesLocked()
	p.pruneTombstonedArchivesLocked()
}

// syncArchiveFromDisk picks up archive entries written by OTHER Cloud Run instances and drops
// entries deleted by other instances (including seed-index rows).
//
// Each instance keeps its own in-memory archive map, filled once at startup. The archive directory is a
// shared GCS mount, so an upload handled by instance A writes its sidecar there, but instances B and C kept
// listing their startup copy and the new sheet never showed in the tab until a restart. This merges new
// sidecars (metadata only; bytes are read lazily from StoragePath on download), refreshes deletion
// tombstones from disk (+ Firestore when configured), prunes tombstoned in-memory entries, and when the
// same (tenant, type, chain, file name) exists twice keeps only the newest upload.
//
// Tombstone refresh/prune is NOT gated by archiveDiskSyncInterval (see refreshArchiveTombstonesAlways);
// only the sidecar merge is throttled.
func (p *Processor) syncArchiveFromDisk(normTenant string, force bool) {
	if normTenant == "" {
		return
	}
	// Always hide deletes from peer instances before any list filter runs.
	p.refreshArchiveTombstonesAlways(context.Background())

	if p.archiveDir == "" {
		return
	}
	now := time.Now().UnixNano()
	p.archiveMu.RLock()
	fresh := !force && now-p.lastArchiveDiskSync < int64(archiveDiskSyncInterval)
	p.archiveMu.RUnlock()
	if fresh {
		return
	}

	tenantDir := filepath.Join(p.archiveDir, normTenant)
	disk := mergeArchiveSidecars(nil, tenantDir)

	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()
	p.lastArchiveDiskSync = now
	// Re-apply after merge window: a concurrent delete may have landed while we read sidecars.
	p.applyDiskTombstonesLocked()
	p.pruneTombstonedArchivesLocked()
	for _, item := range disk {
		if item == nil || item.ID == "" || item.TenantID != normTenant {
			continue
		}
		if p.fsRepo != nil && p.fsRepo.IsArchiveDeleted(item.TenantID, item.ID, item.FileName) {
			continue
		}
		if cur, ok := p.archivedFiles[item.ID]; ok {
			// Another instance re-saved this entry (e.g. a re-upload of the same file): take its metadata
			// and drop cached bytes so the new workbook is read from disk.
			if item.UploadedAt > cur.UploadedAt || item.BatchID != cur.BatchID && item.UploadedAt >= cur.UploadedAt {
				copyItem := *item
				p.archivedFiles[item.ID] = &copyItem
				delete(p.archivedBytes, item.ID)
			}
			continue
		}
		kind := archiveEntryKind(item)
		superseded := false
		for id, other := range p.archivedFiles {
			if other.TenantID != normTenant || kind == "product_master" ||
				archiveEntryKind(other) != kind ||
				!strings.EqualFold(other.RetailChain, item.RetailChain) ||
				!strings.EqualFold(other.FileName, item.FileName) {
				continue
			}
			if other.UploadedAt >= item.UploadedAt {
				superseded = true
				break
			}
			delete(p.archivedFiles, id)
			delete(p.archivedBytes, id)
		}
		if superseded {
			continue
		}
		copyItem := *item
		p.archivedFiles[copyItem.ID] = &copyItem
	}
}

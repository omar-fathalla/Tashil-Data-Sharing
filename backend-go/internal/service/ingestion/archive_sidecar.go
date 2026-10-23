package ingestion

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
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

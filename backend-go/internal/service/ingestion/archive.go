package ingestion

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"runtime/debug"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// ArchivedFile represents a stored Excel or CSV file in the retail chain upload archive.
type ArchivedFile struct {
	ID              string  `json:"id"`
	BatchID         string  `json:"batch_id,omitempty"`
	FileType        string  `json:"file_type,omitempty"` // "sell_out" | "sell_in" | "product_master"
	TenantID        string  `json:"tenant_id"`
	FileName        string  `json:"file_name"`
	ContentType     string  `json:"content_type"`
	FileSizeBytes   int64   `json:"file_size_bytes"`
	RetailChain     string  `json:"retail_chain"`
	ChainNameAr     string  `json:"chain_name_ar"`
	ChainNameEn     string  `json:"chain_name_en"`
	TargetYear      string  `json:"target_year"`
	TargetMonth     string  `json:"target_month"`
	RowsIngested    int     `json:"rows_ingested"`
	BranchesCount   int     `json:"branches_count"`
	TotalRevenue    float64 `json:"total_revenue"`
	TotalCases      float64 `json:"total_cases,omitempty"`
	TotalWeightTons float64 `json:"total_weight_tons,omitempty"`
	UploadedAt      string  `json:"uploaded_at"`
	StoragePath     string  `json:"storage_path,omitempty"`
}

func isProductMasterArchiveEntry(entry *ArchivedFile) bool {
	if entry == nil {
		return false
	}
	if strings.EqualFold(entry.FileType, "product_master") {
		return true
	}
	if strings.HasPrefix(entry.BatchID, "batch_pm_") {
		return true
	}
	if strings.EqualFold(entry.RetailChain, "product-master") || strings.EqualFold(entry.RetailChain, "product_master") {
		return true
	}
	fn := strings.ToLower(entry.FileName)
	return strings.Contains(fn, "product_master") ||
		strings.Contains(entry.FileName, "كارتة الأصناف")
}

func isSellInArchiveEntry(entry *ArchivedFile) bool {
	if entry == nil {
		return false
	}
	if isProductMasterArchiveEntry(entry) {
		return false
	}
	if strings.EqualFold(entry.FileType, "sell_in") {
		return true
	}
	if strings.EqualFold(entry.FileType, "sell_out") {
		return false
	}
	fn := strings.ToLower(entry.FileName)
	return strings.Contains(fn, "sell_in") ||
		strings.Contains(fn, "sellin") ||
		strings.Contains(fn, "plan 10") ||
		strings.HasPrefix(entry.BatchID, "batch_sellin_")
}

// ArchiveListResponse contains the filtered archive items and per-chain summary counts.
type ArchiveListResponse struct {
	TenantID    string          `json:"tenant_id"`
	TotalCount  int             `json:"total_count"`
	ChainCounts map[string]int  `json:"chain_counts"`
	Files       []*ArchivedFile `json:"files"`
}

var yearRegex = regexp.MustCompile(`202[0-9]`)

func normalizeArchiveTenantID(tenantID string) string {
	slug := strings.ToLower(strings.TrimSpace(tenantID))
	slug = strings.TrimPrefix(slug, "tenant-")
	slug = strings.TrimPrefix(slug, "tenant_")
	if slug == "" || slug == "system" || slug == "all" {
		return "tenant-adeco"
	}
	return "tenant-" + slug
}

func getChainNamesArEn(chainCode string) (string, string) {
	switch strings.ToLower(strings.TrimSpace(chainCode)) {
	case "product-master", "product_master":
		return "كارتة الأصناف والأسعار", "Product Master & Price List"
	case "fathalla":
		return "أسواق فتح الله", "Fathalla Market"
	case "gomla":
		return "جملة ماركت", "Gomla Market"
	case "beet-elgomla", "beet_elgomla":
		return "بيت الجملة", "Beet El-Gomla"
	case "carrefour":
		return "كارفور مصر", "Carrefour Egypt"
	case "spinneys":
		return "سبينس مصر", "Spinneys Egypt"
	case "metro":
		return "مترو ماركت", "Metro Market"
	case "seoudi":
		return "سعودي ماركت", "Seoudi Market"
	case "hyperone":
		return "هايبر وان", "Hyper One"
	default:
		if name, ok := domain.GetCustomChainDisplayName(chainCode); ok && name != "" {
			return name, name
		}
		clean := strings.TrimSpace(chainCode)
		if clean == "" {
			return "غير محدد", "Unspecified"
		}
		return clean, clean
	}
}

func detectFileContentType(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".xlsx":
		return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
	case ".xls":
		return "application/vnd.ms-excel"
	case ".csv":
		return "text/csv; charset=utf-8"
	default:
		return "application/octet-stream"
	}
}

func sanitizeArchiveFilename(name string) string {
	base := filepath.Base(strings.TrimSpace(name))
	replacer := strings.NewReplacer("/", "_", "\\", "_", "..", "_", ":", "_")
	return replacer.Replace(base)
}

func inferArchiveYearAndMonth(filename, requestedPeriodDate, latestDate string, distinctMonths map[string]bool) (string, string) {
	if len(requestedPeriodDate) >= 7 {
		year := requestedPeriodDate[:4]
		month := requestedPeriodDate[5:7]
		return year, month
	}
	year := ""
	month := "auto"
	if len(latestDate) >= 7 {
		year = latestDate[:4]
		month = latestDate[5:7]
	}
	if year == "" {
		if m := yearRegex.FindString(filename); m != "" {
			year = m
		} else {
			year = "2026"
		}
	}
	if len(distinctMonths) > 1 {
		var months []string
		for ym := range distinctMonths {
			if len(ym) >= 7 {
				months = append(months, ym[5:7])
			}
		}
		sort.Strings(months)
		if len(months) > 1 {
			month = fmt.Sprintf("%s-%s", months[0], months[len(months)-1])
		}
	}
	return year, month
}

// WithArchiveDir sets a custom directory for persisting archived Excel/CSV files.
func (p *Processor) WithArchiveDir(dir string) *Processor {
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()
	p.archiveDir = dir
	p.loadDiskArchiveLocked()
	return p
}

func (p *Processor) loadDiskArchiveLocked() {
	if p.archiveDir == "" {
		return
	}
	tombstonePath := filepath.Join(p.archiveDir, "deleted_tombstones.json")
	if rawTomb, err := os.ReadFile(tombstonePath); err == nil && len(rawTomb) > 0 && p.fsRepo != nil {
		var tombs []struct {
			TenantID  string `json:"tenant_id"`
			ArchiveID string `json:"archive_id"`
			FileName  string `json:"file_name"`
		}
		if json.Unmarshal(rawTomb, &tombs) == nil {
			for _, t := range tombs {
				_ = p.fsRepo.MarkArchiveDeleted(context.Background(), t.TenantID, t.ArchiveID, t.FileName)
			}
		}
	}
	entries, err := os.ReadDir(p.archiveDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), "_") {
			continue
		}
		indexFile := filepath.Join(p.archiveDir, entry.Name(), "index.json")
		var list []*ArchivedFile
		if raw, err := os.ReadFile(indexFile); err == nil {
			_ = json.Unmarshal(raw, &list)
		}
		list = mergeArchiveSidecars(list, filepath.Join(p.archiveDir, entry.Name()))
		for _, item := range list {
			if item == nil || item.ID == "" {
				continue
			}
			if p.fsRepo != nil && p.fsRepo.IsArchiveDeleted(item.TenantID, item.ID, item.FileName) {
				continue
			}
			// Bytes are read lazily from disk (archivedBytesLocked) instead of pinning every workbook in memory.
			p.archivedFiles[item.ID] = item
		}
	}
}

func (p *Processor) appendDiskTombstoneLocked(tenantID, archiveID, fileName string) {
	if p.archiveDir == "" {
		return
	}
	tombstonePath := filepath.Join(p.archiveDir, "deleted_tombstones.json")
	type tombItem struct {
		TenantID  string `json:"tenant_id"`
		ArchiveID string `json:"archive_id"`
		FileName  string `json:"file_name"`
	}
	var tombs []tombItem
	if raw, err := os.ReadFile(tombstonePath); err == nil && len(raw) > 0 {
		_ = json.Unmarshal(raw, &tombs)
	}
	tombs = append(tombs, tombItem{
		TenantID:  tenantID,
		ArchiveID: archiveID,
		FileName:  fileName,
	})
	if data, err := json.MarshalIndent(tombs, "", "  "); err == nil {
		_ = os.WriteFile(tombstonePath, data, 0o644)
	}
}

func (p *Processor) persistTenantArchiveIndexLocked(normTenant string) {
	if p.archiveDir == "" {
		return
	}
	tenantDir := filepath.Join(p.archiveDir, normTenant)
	if err := os.MkdirAll(tenantDir, 0o755); err != nil {
		return
	}
	var list []*ArchivedFile
	for _, item := range p.archivedFiles {
		if item.TenantID == normTenant {
			list = append(list, item)
		}
	}
	sort.Slice(list, func(i, j int) bool {
		return list[i].UploadedAt > list[j].UploadedAt
	})
	if data, err := json.MarshalIndent(list, "", "  "); err == nil {
		_ = os.WriteFile(filepath.Join(tenantDir, "index.json"), data, 0o644)
	}
}

// SnapshotExistingArchivedFile returns a copy of any existing archived file and its bytes for (tenantID, retailChain, filename).
func (p *Processor) SnapshotExistingArchivedFile(tenantID, retailChain, filename string) (*ArchivedFile, []byte) {
	p.archiveMu.RLock()
	defer p.archiveMu.RUnlock()

	normTenant := normalizeArchiveTenantID(tenantID)
	normChain := strings.ToLower(strings.TrimSpace(retailChain))
	if normChain == "" {
		normChain = "fathalla"
	}
	for id, entry := range p.archivedFiles {
		if entry.TenantID == normTenant &&
			strings.EqualFold(entry.RetailChain, normChain) &&
			strings.EqualFold(entry.FileName, filename) {
			copyEntry := *entry
			var bCopy []byte
			if raw := p.archivedBytesLocked(id); len(raw) > 0 {
				bCopy = make([]byte, len(raw))
				copy(bCopy, raw)
			}
			return &copyEntry, bCopy
		}
	}
	return nil, nil
}

// SaveArchivedFile persists an uploaded Excel/CSV file's raw bytes and metadata into the chain archive.
func (p *Processor) SaveArchivedFile(
	tenantID string,
	batchID string,
	filename string,
	fileBytes []byte,
	retailChain string,
	targetYear string,
	targetMonth string,
	rowsIngested int,
	branchesCount int,
	totalRevenue float64,
	extraMetrics ...float64,
) *ArchivedFile {
	// Pick up entries saved by other instances first, so a re-upload of the same file reuses its
	// archive entry instead of creating a duplicate.
	p.syncArchiveFromDisk(normalizeArchiveTenantID(tenantID), true)
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()

	normTenant := normalizeArchiveTenantID(tenantID)
	normChain := strings.ToLower(strings.TrimSpace(retailChain))
	if normChain == "" {
		normChain = "fathalla"
	}
	chainAr, chainEn := getChainNamesArEn(normChain)
	if targetYear == "" || targetYear == "auto" {
		if m := yearRegex.FindString(filename); m != "" {
			targetYear = m
		} else {
			targetYear = "2026"
		}
	}
	if targetMonth == "" {
		targetMonth = "auto"
	}

	fileType := "sell_out"
	if strings.HasPrefix(batchID, "batch_pm_") || strings.EqualFold(normChain, "product-master") || strings.EqualFold(normChain, "product_master") {
		fileType = "product_master"
	} else if strings.HasPrefix(batchID, "batch_sellin_") {
		fileType = "sell_in"
	}

	var totalCases, totalTons float64
	if len(extraMetrics) > 0 {
		totalCases = extraMetrics[0]
	}
	if len(extraMetrics) > 1 {
		totalTons = extraMetrics[1]
	}

	safeFile := sanitizeArchiveFilename(filename)
	var existingID string
	var existingUploadedAt string
	for id, entry := range p.archivedFiles {
		entryType := "sell_out"
		if isProductMasterArchiveEntry(entry) {
			entryType = "product_master"
		} else if isSellInArchiveEntry(entry) {
			entryType = "sell_in"
		}
		if entry.TenantID == normTenant &&
			entryType == fileType &&
			strings.EqualFold(entry.RetailChain, normChain) &&
			strings.EqualFold(entry.FileName, filename) {
			if fileType == "product_master" {
				// Only reuse existing entry for Product Master if raw bytes are identical (e.g., startup replay);
				// otherwise create a new versioned entry so deleting it rolls back to the prior sheet version.
				if bytes.Equal(p.archivedBytesLocked(id), fileBytes) {
					existingID = id
					existingUploadedAt = entry.UploadedAt
					break
				}
				continue
			}
			existingID = id
			if bytes.Equal(p.archivedBytesLocked(id), fileBytes) {
				// Same bytes = replay or confirmation re-apply: uploaded_at keeps the original upload time
				// (the re-apply order depends on it). Only different bytes (a real new upload) move it.
				existingUploadedAt = entry.UploadedAt
			}
			break
		}
	}

	archiveID := existingID
	if archiveID == "" {
		slug := strings.TrimPrefix(normTenant, "tenant-")
		prefix := "arch"
		if fileType == "product_master" {
			prefix = "arch_pm"
		} else if fileType == "sell_in" {
			prefix = "arch_sellin"
		}
		archiveID = fmt.Sprintf("%s_%s_%s_%d", prefix, slug, normChain, time.Now().UnixNano())
	}

	var storagePath string
	if p.archiveDir != "" {
		tenantDir := filepath.Join(p.archiveDir, normTenant)
		if err := os.MkdirAll(tenantDir, 0o755); err == nil {
			storagePath = filepath.Join(tenantDir, fmt.Sprintf("%s_%s", archiveID, safeFile))
			_ = os.WriteFile(storagePath, fileBytes, 0o644)
		}
	}

	uploadedAt := time.Now().UTC().Format(time.RFC3339Nano)
	if existingUploadedAt != "" {
		uploadedAt = existingUploadedAt
	}

	entry := &ArchivedFile{
		ID:              archiveID,
		BatchID:         batchID,
		FileType:        fileType,
		TenantID:        normTenant,
		FileName:        filename,
		ContentType:     detectFileContentType(filename),
		FileSizeBytes:   int64(len(fileBytes)),
		RetailChain:     normChain,
		ChainNameAr:     chainAr,
		ChainNameEn:     chainEn,
		TargetYear:      targetYear,
		TargetMonth:     targetMonth,
		RowsIngested:    rowsIngested,
		BranchesCount:   branchesCount,
		TotalRevenue:    totalRevenue,
		TotalCases:      totalCases,
		TotalWeightTons: totalTons,
		UploadedAt:      uploadedAt,
		StoragePath:     storagePath,
	}

	bytesCopy := make([]byte, len(fileBytes))
	copy(bytesCopy, fileBytes)
	p.archivedFiles[archiveID] = entry
	p.archivedBytes[archiveID] = bytesCopy

	if p.fsRepo != nil {
		_ = p.fsRepo.UnmarkArchiveDeleted(context.Background(), normTenant, archiveID, filename)
	}

	// Only this upload's sidecar is written. index.json is legacy (read-only on upload): rewriting it from
	// several Cloud Run instances caused GCS generation conflicts and lost entries.
	p.writeArchiveSidecarLocked(entry)
	p.markArchiveApplied(storagePath)
	copyEntry := *entry
	return &copyEntry
}

// UpdateArchivedFileByBatch updates the chain or period metadata when a staged upload is committed with overrides.
func (p *Processor) UpdateArchivedFileByBatch(batchID, retailChain, targetYear, targetMonth string) *ArchivedFile {
	if batchID == "" {
		return nil
	}
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()

	for _, entry := range p.archivedFiles {
		if entry.BatchID == batchID {
			if retailChain != "" {
				normChain := strings.ToLower(strings.TrimSpace(retailChain))
				entry.RetailChain = normChain
				entry.ChainNameAr, entry.ChainNameEn = getChainNamesArEn(normChain)
				// Deduplicate any older entry for the same (tenant, new chain, filename)
				for otherID, other := range p.archivedFiles {
					if otherID != entry.ID &&
						other.TenantID == entry.TenantID &&
						isProductMasterArchiveEntry(other) == isProductMasterArchiveEntry(entry) &&
						isSellInArchiveEntry(other) == isSellInArchiveEntry(entry) &&
						strings.EqualFold(other.RetailChain, normChain) &&
						strings.EqualFold(other.FileName, entry.FileName) {
						if other.StoragePath != "" && other.StoragePath != entry.StoragePath {
							_ = os.Remove(other.StoragePath)
						}
						p.removeArchiveSidecarLocked(other)
						// A legacy index.json row would bring the replaced entry back on reload.
						p.appendDiskTombstoneLocked(other.TenantID, otherID, "")
						delete(p.archivedFiles, otherID)
						delete(p.archivedBytes, otherID)
					}
				}
			}
			if targetYear != "" && targetYear != "auto" {
				entry.TargetYear = targetYear
			}
			if targetMonth != "" && targetMonth != "auto" {
				entry.TargetMonth = targetMonth
			}
			entry.UploadedAt = time.Now().UTC().Format(time.RFC3339Nano)
			p.writeArchiveSidecarLocked(entry)
			copyEntry := *entry
			return &copyEntry
		}
	}
	return nil
}

// RemoveArchivedFileByBatch removes an uncommitted staged archive entry (or restores a previous entry if it replaced one) when discarded.
func (p *Processor) RemoveArchivedFileByBatch(batchID string, prevEntry *ArchivedFile, prevBytes []byte) {
	if batchID == "" {
		return
	}
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()

	for id, entry := range p.archivedFiles {
		if entry.BatchID == batchID {
			tenantID := entry.TenantID
			if prevEntry != nil && prevEntry.ID == id {
				restored := *prevEntry
				p.archivedFiles[id] = &restored
				p.writeArchiveSidecarLocked(&restored)
				if len(prevBytes) > 0 {
					bCopy := make([]byte, len(prevBytes))
					copy(bCopy, prevBytes)
					p.archivedBytes[id] = bCopy
					if restored.StoragePath != "" {
						_ = os.WriteFile(restored.StoragePath, bCopy, 0o644)
					}
				}
			} else {
				if entry.StoragePath != "" {
					_ = os.Remove(entry.StoragePath)
				}
				p.removeArchiveSidecarLocked(entry)
				delete(p.archivedFiles, id)
				delete(p.archivedBytes, id)
			}
			_ = tenantID
			break
		}
	}
}

// ListArchivedFiles returns archived files for the tenant, optionally filtered by retail chain, year, search query, and file type ("sell_out" | "sell_in" | "product_master" | "all").
func (p *Processor) ListArchivedFiles(ctx context.Context, tenantID, chainFilter, yearFilter, searchQuery string, fileTypeFilters ...string) *ArchiveListResponse {
	p.syncArchiveFromDisk(normalizeArchiveTenantID(tenantID), false)
	p.archiveMu.RLock()
	defer p.archiveMu.RUnlock()

	normTenant := normalizeArchiveTenantID(tenantID)
	normChain := strings.ToLower(strings.TrimSpace(chainFilter))
	if normChain == "all" || normChain == "الكل" {
		normChain = ""
	}
	normYear := strings.ToLower(strings.TrimSpace(yearFilter))
	if normYear == "all" || normYear == "الكل" || normYear == "auto" {
		normYear = ""
	}
	normSearch := strings.ToLower(strings.TrimSpace(searchQuery))

	typeFilter := "sell_out"
	if len(fileTypeFilters) > 0 {
		tf := strings.ToLower(strings.TrimSpace(fileTypeFilters[0]))
		if tf == "sell_in" || tf == "sellin" {
			typeFilter = "sell_in"
		} else if tf == "product_master" || tf == "product-master" || tf == "master" {
			typeFilter = "product_master"
		} else if tf == "all" || tf == "*" {
			typeFilter = "all"
		}
	}

	chainCounts := make(map[string]int)
	var filtered []*ArchivedFile

	for _, entry := range p.archivedFiles {
		if entry.TenantID != normTenant {
			continue
		}
		if p.fsRepo != nil && p.fsRepo.IsArchiveDeleted(entry.TenantID, entry.ID, entry.FileName) {
			continue
		}

		isProductMaster := isProductMasterArchiveEntry(entry)
		isSellIn := isSellInArchiveEntry(entry)
		if typeFilter == "product_master" && !isProductMaster {
			continue
		}
		if typeFilter == "sell_in" && !isSellIn {
			continue
		}
		if typeFilter == "sell_out" && (isSellIn || isProductMaster) {
			continue
		}

		chainCounts[entry.RetailChain]++

		if normChain != "" && !strings.EqualFold(entry.RetailChain, normChain) {
			continue
		}
		if normYear != "" && !strings.EqualFold(entry.TargetYear, normYear) {
			continue
		}
		if normSearch != "" {
			matchName := strings.Contains(strings.ToLower(entry.FileName), normSearch)
			matchChainAr := strings.Contains(strings.ToLower(entry.ChainNameAr), normSearch)
			matchChainEn := strings.Contains(strings.ToLower(entry.ChainNameEn), normSearch)
			if !matchName && !matchChainAr && !matchChainEn {
				continue
			}
		}
		copyEntry := *entry
		if copyEntry.FileType == "" {
			if isProductMaster {
				copyEntry.FileType = "product_master"
			} else if isSellIn {
				copyEntry.FileType = "sell_in"
			} else {
				copyEntry.FileType = "sell_out"
			}
		}
		filtered = append(filtered, &copyEntry)
	}

	sort.Slice(filtered, func(i, j int) bool {
		if filtered[i].UploadedAt == filtered[j].UploadedAt {
			return filtered[i].ID > filtered[j].ID
		}
		return filtered[i].UploadedAt > filtered[j].UploadedAt
	})

	if filtered == nil {
		filtered = []*ArchivedFile{}
	}

	return &ArchiveListResponse{
		TenantID:    normTenant,
		TotalCount:  len(filtered),
		ChainCounts: chainCounts,
		Files:       filtered,
	}
}

// GetArchivedFile retrieves an archived file metadata and its raw bytes by ID for a tenant.
func (p *Processor) GetArchivedFile(ctx context.Context, tenantID, archiveID string) (*ArchivedFile, []byte, error) {
	p.archiveMu.RLock()
	defer p.archiveMu.RUnlock()

	normTenant := normalizeArchiveTenantID(tenantID)
	entry, ok := p.archivedFiles[archiveID]
	if !ok || entry == nil {
		return nil, nil, fmt.Errorf("archived file not found: %s", archiveID)
	}
	if entry.TenantID != normTenant && tenantID != "system" && tenantID != "all" && tenantID != "tenant-system" && tenantID != "tenant-all" {
		return nil, nil, fmt.Errorf("unauthorized tenant access to archived file")
	}

	if raw, ok := p.archivedBytes[archiveID]; ok && len(raw) > 0 {
		copyEntry := *entry
		return &copyEntry, raw, nil
	}
	if entry.StoragePath != "" {
		targetPath := entry.StoragePath
		if _, err := os.Stat(targetPath); os.IsNotExist(err) && p.archiveDir != "" {
			alt := filepath.Join(p.archiveDir, entry.TenantID, filepath.Base(entry.StoragePath))
			if _, err2 := os.Stat(alt); err2 == nil {
				targetPath = alt
			}
		}
		if raw, err := os.ReadFile(targetPath); err == nil && len(raw) > 0 {
			copyEntry := *entry
			return &copyEntry, raw, nil
		}
	}
	return nil, nil, fmt.Errorf("archived file bytes unavailable for: %s", archiveID)
}

// ArchiveDeleteError is returned when archive delete fails after looking up the file.
// Stage is one of: "bigquery", "firestore", "memory_store", "partial".
type ArchiveDeleteError struct {
	Stage   string
	Message string
	Cause   error
}

func (e *ArchiveDeleteError) Error() string {
	if e == nil {
		return ""
	}
	if e.Cause != nil {
		return fmt.Sprintf("%s: %s: %v", e.Stage, e.Message, e.Cause)
	}
	return fmt.Sprintf("%s: %s", e.Stage, e.Message)
}

func (e *ArchiveDeleteError) Unwrap() error { return e.Cause }

// ErrArchivedFileNotFound is returned when no archive entry matches the requested id/name.
var ErrArchivedFileNotFound = fmt.Errorf("archived file not found")

func archiveNotFound(archiveID string) error {
	return fmt.Errorf("%w: %s", ErrArchivedFileNotFound, archiveID)
}

// DeleteArchivedFile deletes an archived file and purges its analytics rows.
//
// Safe order (success only when both durable row removal AND list/archive removal succeed):
//  1. Look up the entry; leave it listed until durable deletes finish.
//  2. Delete BigQuery rows via the durable sink (when enabled). On failure, abort — file stays listed.
//  3. Purge in-memory analytics (bqRepo). On failure, abort — file stays listed.
//  4. Tombstone + remove from archive list / disk. On failure after a successful BigQuery delete,
//     return a partial error (rows may already be gone; list still shows the file when possible).
//
// Sell-Out last-file delete is scoped to this archive's batch/file only. It no longer calls
// ClearTenantData or a tenant-wide RemoveBatchRecords("", "") wipe — that was unsafe and is
// flagged for Mohamed's product decision (use explicit clear endpoints for full wipes).
func (p *Processor) DeleteArchivedFile(ctx context.Context, tenantID, archiveID string) (*ArchivedFile, error) {
	p.archiveMu.Lock()

	normTenant := normalizeArchiveTenantID(tenantID)
	entry, ok := p.archivedFiles[archiveID]
	if !ok || entry == nil {
		// Fallback match by BatchID or FileName (preferring the newest entry when multiple versions share a FileName)
		for _, candidate := range p.archivedFiles {
			if candidate.TenantID == normTenant &&
				(candidate.BatchID == archiveID || strings.EqualFold(candidate.FileName, archiveID)) {
				if entry == nil || candidate.UploadedAt > entry.UploadedAt || (candidate.UploadedAt == entry.UploadedAt && candidate.ID > entry.ID) {
					entry = candidate
					archiveID = candidate.ID
					ok = true
				}
			}
		}
	}
	if (!ok || entry == nil) && p.bqRepo != nil {
		// Handle deletion of synthesized default seed Product Master bubble when not in p.archivedFiles
		if pm, err := p.bqRepo.GetProductMaster(ctx, normTenant, bigquery.ProductMasterFilter{}); err == nil && pm != nil && pm.TotalSKUs > 0 {
			srcName := pm.SourceFilename
			if srcName == "" {
				srcName = "adeco_product_master_2026_08_01.xlsx"
			}
			if strings.EqualFold(archiveID, "pm_default_seed") || strings.EqualFold(archiveID, srcName) {
				p.archiveMu.Unlock()
				seed := &ArchivedFile{
					ID:           archiveID,
					FileType:     "product_master",
					TenantID:     normTenant,
					FileName:     srcName,
					RetailChain:  "product-master",
					RowsIngested: pm.TotalSKUs,
				}
				if res := p.sinkDeleteArchived(ctx, seed); res != nil && res.Failed() {
					return nil, &ArchiveDeleteError{Stage: "bigquery", Message: "failed to remove product master rows from BigQuery", Cause: fmt.Errorf("%s", res.Error)}
				}
				if err := p.bqRepo.ClearProductMaster(ctx, normTenant); err != nil {
					return nil, &ArchiveDeleteError{Stage: "memory_store", Message: "failed to clear product master from analytics store", Cause: err}
				}
				_ = p.bqRepo.RestoreBaselineProductMaster(ctx, normTenant, srcName)
				p.archiveMu.Lock()
				if p.fsRepo != nil {
					if err := p.fsRepo.MarkArchiveDeleted(ctx, normTenant, archiveID, srcName); err != nil {
						p.archiveMu.Unlock()
						return nil, &ArchiveDeleteError{Stage: "firestore", Message: "BigQuery rows removed but archive tombstone failed", Cause: err}
					}
				}
				p.appendDiskTombstoneLocked(normTenant, archiveID, srcName)
				p.archiveMu.Unlock()
				return seed, nil
			}
		}
	}
	if !ok || entry == nil {
		p.archiveMu.Unlock()
		return nil, archiveNotFound(archiveID)
	}
	if entry.TenantID != normTenant && tenantID != "system" && tenantID != "all" && tenantID != "tenant-system" && tenantID != "tenant-all" {
		p.archiveMu.Unlock()
		return nil, fmt.Errorf("unauthorized tenant access to archived file")
	}

	deletedEntry := *entry
	archiveID = deletedEntry.ID

	hasSameNameRemaining := false
	for _, f := range p.archivedFiles {
		if f.ID == archiveID {
			continue
		}
		if f.TenantID == normTenant && strings.EqualFold(f.FileName, deletedEntry.FileName) {
			hasSameNameRemaining = true
			break
		}
	}
	tombstoneFileName := deletedEntry.FileName
	if hasSameNameRemaining {
		tombstoneFileName = ""
	}

	// Snapshot remaining PM entries before unlock (used after durable delete).
	var remainingPM []*ArchivedFile
	if isProductMasterArchiveEntry(&deletedEntry) {
		for _, f := range p.archivedFiles {
			if f.ID == archiveID {
				continue
			}
			if f.TenantID == normTenant && isProductMasterArchiveEntry(f) {
				copyEntry := *f
				remainingPM = append(remainingPM, &copyEntry)
			}
		}
		sort.Slice(remainingPM, func(i, j int) bool {
			if remainingPM[i].UploadedAt == remainingPM[j].UploadedAt {
				return remainingPM[i].ID < remainingPM[j].ID
			}
			return remainingPM[i].UploadedAt < remainingPM[j].UploadedAt
		})
	}
	p.archiveMu.Unlock()

	// --- Phase 1: durable BigQuery row removal (file still listed) ---
	if res := p.sinkDeleteArchived(ctx, &deletedEntry); res != nil && res.Failed() {
		return nil, &ArchiveDeleteError{
			Stage:   "bigquery",
			Message: "failed to remove analytics rows from BigQuery; archive file was left listed",
			Cause:   fmt.Errorf("%s", res.Error),
		}
	}

	// --- Phase 2: in-memory analytics purge (file still listed) ---
	if err := p.purgeAnalyticsForDeletedArchive(ctx, normTenant, &deletedEntry, remainingPM); err != nil {
		return nil, err
	}

	// --- Phase 3: remove from archive list / tombstone / disk ---
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()

	// Re-check the entry still exists (another request may have won the race).
	if cur, still := p.archivedFiles[archiveID]; !still || cur == nil {
		// Analytics already purged; treat as success if tombstone can be recorded.
		if p.fsRepo != nil {
			if err := p.fsRepo.MarkArchiveDeleted(ctx, normTenant, deletedEntry.ID, tombstoneFileName); err != nil {
				return nil, &ArchiveDeleteError{Stage: "partial", Message: "BigQuery rows removed but archive list update failed", Cause: err}
			}
		}
		p.appendDiskTombstoneLocked(normTenant, deletedEntry.ID, tombstoneFileName)
		return &deletedEntry, nil
	}

	if p.fsRepo != nil {
		if err := p.fsRepo.MarkArchiveDeleted(ctx, normTenant, deletedEntry.ID, tombstoneFileName); err != nil {
			return nil, &ArchiveDeleteError{
				Stage:   "firestore",
				Message: "BigQuery rows removed but archive tombstone failed; file left listed so you can retry",
				Cause:   err,
			}
		}
	}
	p.appendDiskTombstoneLocked(normTenant, deletedEntry.ID, tombstoneFileName)

	p.removeArchiveSidecarLocked(&deletedEntry)
	delete(p.archivedFiles, archiveID)
	delete(p.archivedBytes, archiveID)

	if deletedEntry.StoragePath != "" {
		_ = os.Remove(deletedEntry.StoragePath)
	}
	if p.archiveDir != "" {
		tenantDir := filepath.Join(p.archiveDir, normTenant)
		indexPath := filepath.Join(tenantDir, "index.json")
		var remainingDisk []*ArchivedFile
		for _, f := range p.archivedFiles {
			if f.TenantID == normTenant {
				remainingDisk = append(remainingDisk, f)
			}
		}
		if len(remainingDisk) > 0 {
			if data, err := json.MarshalIndent(remainingDisk, "", "  "); err == nil {
				_ = os.WriteFile(indexPath, data, 0644)
			}
		} else {
			_ = os.Remove(indexPath)
		}
	}

	return &deletedEntry, nil
}

// purgeAnalyticsForDeletedArchive removes in-memory analytics for one deleted archive.
// Sell-Out/Sell-In deletes are always scoped to this file's batch (and chain when needed).
// A missing last Sell-Out file no longer wipes the whole tenant.
func (p *Processor) purgeAnalyticsForDeletedArchive(ctx context.Context, normTenant string, deletedEntry *ArchivedFile, remainingPM []*ArchivedFile) error {
	if deletedEntry == nil {
		return nil
	}
	if isProductMasterArchiveEntry(deletedEntry) {
		if p.bqRepo == nil {
			return nil
		}
		if err := p.bqRepo.ClearProductMaster(ctx, normTenant); err != nil {
			return &ArchiveDeleteError{Stage: "memory_store", Message: "failed to clear product master from analytics store", Cause: err}
		}
		if len(remainingPM) == 0 {
			_ = p.bqRepo.RestoreBaselineProductMaster(ctx, normTenant, deletedEntry.FileName)
			return nil
		}
		for _, f := range remainingPM {
			p.archiveMu.RLock()
			raw := p.archivedBytes[f.ID]
			p.archiveMu.RUnlock()
			if len(raw) == 0 && f.StoragePath != "" {
				if b, err := os.ReadFile(f.StoragePath); err == nil {
					raw = b
				}
			}
			if len(raw) > 0 {
				if summary, err := gemini.ParseProductMasterWorkbook(normTenant, f.FileName, raw); err == nil && summary != nil {
					if _, err := p.bqRepo.SetProductMaster(ctx, normTenant, summary); err != nil {
						return &ArchiveDeleteError{Stage: "memory_store", Message: "failed to rebuild product master after delete", Cause: err}
					}
				}
			}
		}
		return nil
	}

	if p.bqRepo == nil {
		return nil
	}

	if isSellInArchiveEntry(deletedEntry) {
		if err := p.bqRepo.RemoveSellInFileRecords(ctx, normTenant, deletedEntry.BatchID, deletedEntry.FileName, deletedEntry.RetailChain); err != nil {
			return &ArchiveDeleteError{Stage: "memory_store", Message: "failed to remove sell-in records for archived file", Cause: err}
		}
		return nil
	}

	// Sell-Out: always scope to this archive's batch (and chain). Never wipe the whole tenant
	// or clear Firestore tenant data as a side effect of deleting the last uploaded file.
	if err := p.bqRepo.RemoveBatchRecords(ctx, normTenant, deletedEntry.BatchID, deletedEntry.RetailChain); err != nil {
		return &ArchiveDeleteError{Stage: "memory_store", Message: "failed to remove sell-out records for archived file", Cause: err}
	}
	return nil
}

// ClearTenantArchives removes all archived files for a specific tenant from memory, disk, and records deletion tombstones in Cloud Firestore.
func (p *Processor) ClearTenantArchives(ctx context.Context, tenantID string) {
	clean := strings.ToLower(strings.TrimSpace(tenantID))
	if clean == "" || clean == "all" || clean == "*" {
		return
	}
	normTenant := normalizeArchiveTenantID(tenantID)

	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()

	for id, entry := range p.archivedFiles {
		if entry.TenantID == normTenant {
			if p.fsRepo != nil {
				_ = p.fsRepo.MarkArchiveDeleted(ctx, normTenant, entry.ID, entry.FileName)
			}
			if entry.StoragePath != "" {
				_ = os.Remove(entry.StoragePath)
			}
			delete(p.archivedFiles, id)
			delete(p.archivedBytes, id)
		}
	}

	if p.archiveDir != "" {
		tenantDir := filepath.Join(p.archiveDir, normTenant)
		_ = os.Remove(filepath.Join(tenantDir, "index.json"))
		_ = os.RemoveAll(filepath.Join(tenantDir, archiveSidecarDir))
	}
}

// ReplayArchivedFilesToDatabase replays all existing archived files on disk into BigQuery and Firestore on server startup.
// It ensures ONLY real user-uploaded files on disk exist in the system, and never re-reads external directories.
func (p *Processor) ReplayArchivedFilesToDatabase(ctx context.Context) error {
	return p.replayArchivedFiles(ctx, false)
}

// BackfillArchiveToSink replays every archived file like startup does, but WITH durable BigQuery writes enabled.
// Writes are idempotent (dedupe by period / file), so running it twice does not duplicate rows.
func (p *Processor) BackfillArchiveToSink(ctx context.Context) error {
	return p.replayArchivedFiles(ctx, true)
}

func (p *Processor) replayArchivedFiles(ctx context.Context, writeSink bool) error {
	if !writeSink {
		p.replaying.Store(true)
		defer p.replaying.Store(false)
	}
	p.archiveMu.Lock()
	p.loadDiskArchiveLocked()
	files := make([]*ArchivedFile, 0, len(p.archivedFiles))
	hasSeedSellIn := false
	hasSeedProductMaster := false
	for _, f := range p.archivedFiles {
		files = append(files, f)
		if strings.EqualFold(f.FileName, "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx") {
			hasSeedSellIn = true
		}
		if isProductMasterArchiveEntry(f) || strings.EqualFold(f.FileName, "adeco_product_master_2026_08_01.xlsx") {
			hasSeedProductMaster = true
		}
	}
	p.archiveMu.Unlock()

	// Ensure Adeco Product Master & Price List seed dataset is archived on startup if not already present
	pmSeedDeleted := p.fsRepo != nil && p.fsRepo.IsArchiveDeleted("tenant-adeco", "", "adeco_product_master_2026_08_01.xlsx")
	if !hasSeedProductMaster && !pmSeedDeleted {
		pmSeedPaths := []string{
			"data/product_master/adeco_product_master_2026_08_01.xlsx",
			"/app/data/product_master/adeco_product_master_2026_08_01.xlsx",
		}
		for _, sp := range pmSeedPaths {
			if seedBytes, err := os.ReadFile(sp); err == nil && len(seedBytes) > 0 {
				if p.bqRepo != nil && len(p.bqRepo.GetProductMasterItems("tenant-adeco")) > 0 {
					pmItems := p.bqRepo.GetProductMasterItems("tenant-adeco")
					p.SaveArchivedFile("tenant-adeco", "batch_pm_seed_2026_08_01", filepath.Base(sp), seedBytes, "product-master", "2026", "08", len(pmItems), 0, 0)
				} else {
					_, _ = p.ProcessProductMaster(ctx, "tenant-adeco", filepath.Base(sp), seedBytes, false)
				}
				break
			}
		}
	}

	// Ensure CPFR Sell-In seed dataset is loaded on startup if not already archived and not deleted by the user
	seedDeleted := p.fsRepo != nil && p.fsRepo.IsArchiveDeleted("tenant-adeco", "", "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx")
	if !hasSeedSellIn && !seedDeleted {
		seedPaths := []string{
			"data/cpfr_seed/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
			"/app/data/cpfr_seed/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
			"/Users/fathalla/Downloads/Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
		}
		for _, sp := range seedPaths {
			if seedBytes, err := os.ReadFile(sp); err == nil && len(seedBytes) > 0 {
				_, _ = p.ProcessSellInPlan(ctx, "tenant-adeco", filepath.Base(sp), seedBytes, false, "fathalla")
				break
			}
		}
	}

	// Sort files so Product Master catalogs are replayed first, then Sell-Out workbooks, then Sell-In plans, and chronologically within each type
	typePriority := func(f *ArchivedFile) int {
		if isProductMasterArchiveEntry(f) {
			return 0
		}
		if isSellInArchiveEntry(f) {
			return 2
		}
		return 1
	}
	sort.Slice(files, func(i, j int) bool {
		pi, pj := typePriority(files[i]), typePriority(files[j])
		if pi != pj {
			return pi < pj
		}
		if files[i].UploadedAt == files[j].UploadedAt {
			return files[i].ID < files[j].ID
		}
		return files[i].UploadedAt < files[j].UploadedAt
	})

	p.replayFiles(ctx, files, writeSink)
	return nil
}

// replayArchivedPaths replays only the archived workbooks at the given archive-relative paths
// (as recorded in the snapshot manifest), in the same order rules as a full replay.
func (p *Processor) replayArchivedPaths(ctx context.Context, relPaths []string) error {
	p.replaying.Store(true)
	defer p.replaying.Store(false)
	want := make(map[string]bool, len(relPaths))
	for _, r := range relPaths {
		want[filepath.Base(r)] = true
	}
	p.archiveMu.Lock()
	p.loadDiskArchiveLocked()
	var files []*ArchivedFile
	for _, f := range p.archivedFiles {
		if f.StoragePath != "" && want[filepath.Base(f.StoragePath)] {
			files = append(files, f)
		}
	}
	p.archiveMu.Unlock()
	sortArchiveReplayOrder(files)
	p.replayFiles(ctx, files, false)
	return nil
}

func sortArchiveReplayOrder(files []*ArchivedFile) {
	typePriority := func(f *ArchivedFile) int {
		if isProductMasterArchiveEntry(f) {
			return 0
		}
		if isSellInArchiveEntry(f) {
			return 2
		}
		return 1
	}
	sort.Slice(files, func(i, j int) bool {
		pi, pj := typePriority(files[i]), typePriority(files[j])
		if pi != pj {
			return pi < pj
		}
		if files[i].UploadedAt == files[j].UploadedAt {
			return files[i].ID < files[j].ID
		}
		return files[i].UploadedAt < files[j].UploadedAt
	})
}

func (p *Processor) replayFiles(ctx context.Context, files []*ArchivedFile, writeSink bool) {
	for _, f := range files {
		p.archiveMu.RLock()
		raw := p.archivedBytes[f.ID]
		p.archiveMu.RUnlock()

		if len(raw) == 0 && f.StoragePath != "" {
			targetPath := f.StoragePath
			if _, err := os.Stat(targetPath); os.IsNotExist(err) && p.archiveDir != "" {
				alt := filepath.Join(p.archiveDir, f.TenantID, filepath.Base(f.StoragePath))
				if _, err2 := os.Stat(alt); err2 == nil {
					targetPath = alt
				}
			}
			// Read from disk for this file only; do not pin every archived workbook in memory during a replay.
			if b, err := os.ReadFile(targetPath); err == nil && len(b) > 0 {
				raw = b
			}
		}
		if len(raw) == 0 {
			continue
		}

		if isProductMasterArchiveEntry(f) {
			// During a sink backfill, always reprocess so the catalog reaches BigQuery even if it is already loaded in memory.
			if writeSink || p.bqRepo == nil || len(p.bqRepo.GetProductMasterItems(f.TenantID)) == 0 {
				_, _ = p.ProcessProductMaster(ctx, f.TenantID, f.FileName, raw, false)
			}
		} else if isSellInArchiveEntry(f) {
			_, _ = p.ProcessSellInPlan(ctx, f.TenantID, f.FileName, raw, false, f.RetailChain)
		} else {
			// Replays re-read already accepted uploads: no Gemini calls, and validation only logs.
			_, _ = p.ProcessUpload(gemini.WithReplay(ctx), f.TenantID, f.FileName, raw, f.RetailChain)
		}
		p.markArchiveApplied(f.StoragePath)
		// Release the parsed workbook before the next one so peak memory stays near one file.
		raw = nil
		runtime.GC()
		debug.FreeOSMemory()
	}
}


// archivedBytesLocked returns an archived file's bytes from the in-memory cache, or
// reads them from disk when they are not cached. Caller holds archiveMu.
func (p *Processor) archivedBytesLocked(id string) []byte {
	if raw, ok := p.archivedBytes[id]; ok && len(raw) > 0 {
		return raw
	}
	entry, ok := p.archivedFiles[id]
	if !ok || entry == nil || entry.StoragePath == "" {
		return nil
	}
	targetPath := entry.StoragePath
	if _, err := os.Stat(targetPath); os.IsNotExist(err) && p.archiveDir != "" {
		targetPath = filepath.Join(p.archiveDir, entry.TenantID, filepath.Base(entry.StoragePath))
	}
	b, err := os.ReadFile(targetPath)
	if err != nil {
		return nil
	}
	return b
}

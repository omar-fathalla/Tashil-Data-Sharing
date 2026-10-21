package ingestion

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// ArchivedFile represents a stored Excel or CSV file in the retail chain upload archive.
type ArchivedFile struct {
	ID              string  `json:"id"`
	BatchID         string  `json:"batch_id,omitempty"`
	FileType        string  `json:"file_type,omitempty"` // "sell_out" | "sell_in"
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

func isSellInArchiveEntry(entry *ArchivedFile) bool {
	if entry == nil {
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
		if !entry.IsDir() {
			continue
		}
		indexFile := filepath.Join(p.archiveDir, entry.Name(), "index.json")
		raw, err := os.ReadFile(indexFile)
		if err != nil {
			continue
		}
		var list []*ArchivedFile
		if err := json.Unmarshal(raw, &list); err != nil {
			continue
		}
		for _, item := range list {
			if item == nil || item.ID == "" {
				continue
			}
			if p.fsRepo != nil && p.fsRepo.IsArchiveDeleted(item.TenantID, item.ID, item.FileName) {
				continue
			}
			p.archivedFiles[item.ID] = item
			if item.StoragePath != "" {
				if b, err := os.ReadFile(item.StoragePath); err == nil && len(b) > 0 {
					p.archivedBytes[item.ID] = b
				}
			}
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
			if raw, ok := p.archivedBytes[id]; ok && len(raw) > 0 {
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
	if strings.HasPrefix(batchID, "batch_sellin_") {
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
	for id, entry := range p.archivedFiles {
		entryType := "sell_out"
		if isSellInArchiveEntry(entry) {
			entryType = "sell_in"
		}
		if entry.TenantID == normTenant &&
			entryType == fileType &&
			strings.EqualFold(entry.RetailChain, normChain) &&
			strings.EqualFold(entry.FileName, filename) {
			existingID = id
			break
		}
	}

	archiveID := existingID
	if archiveID == "" {
		slug := strings.TrimPrefix(normTenant, "tenant-")
		prefix := "arch"
		if fileType == "sell_in" {
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
		UploadedAt:      time.Now().UTC().Format(time.RFC3339),
		StoragePath:     storagePath,
	}

	bytesCopy := make([]byte, len(fileBytes))
	copy(bytesCopy, fileBytes)
	p.archivedFiles[archiveID] = entry
	p.archivedBytes[archiveID] = bytesCopy

	if p.fsRepo != nil {
		_ = p.fsRepo.UnmarkArchiveDeleted(context.Background(), normTenant, archiveID, filename)
	}

	p.persistTenantArchiveIndexLocked(normTenant)
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
						isSellInArchiveEntry(other) == isSellInArchiveEntry(entry) &&
						strings.EqualFold(other.RetailChain, normChain) &&
						strings.EqualFold(other.FileName, entry.FileName) {
						if other.StoragePath != "" && other.StoragePath != entry.StoragePath {
							_ = os.Remove(other.StoragePath)
						}
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
			entry.UploadedAt = time.Now().UTC().Format(time.RFC3339)
			p.persistTenantArchiveIndexLocked(entry.TenantID)
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
				delete(p.archivedFiles, id)
				delete(p.archivedBytes, id)
			}
			p.persistTenantArchiveIndexLocked(tenantID)
			break
		}
	}
}

// ListArchivedFiles returns archived files for the tenant, optionally filtered by retail chain, year, search query, and file type ("sell_out" | "sell_in" | "all").
func (p *Processor) ListArchivedFiles(ctx context.Context, tenantID, chainFilter, yearFilter, searchQuery string, fileTypeFilters ...string) *ArchiveListResponse {
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

		isSellIn := isSellInArchiveEntry(entry)
		if typeFilter == "sell_in" && !isSellIn {
			continue
		}
		if typeFilter == "sell_out" && isSellIn {
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
			if isSellIn {
				copyEntry.FileType = "sell_in"
			} else {
				copyEntry.FileType = "sell_out"
			}
		}
		filtered = append(filtered, &copyEntry)
	}

	sort.Slice(filtered, func(i, j int) bool {
		if filtered[i].UploadedAt == filtered[j].UploadedAt {
			return filtered[i].FileName < filtered[j].FileName
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

// DeleteArchivedFile deletes an archived file from memory, disk, and Cloud Firestore, and purges its facts from BigQuery and Firestore.
func (p *Processor) DeleteArchivedFile(ctx context.Context, tenantID, archiveID string) (*ArchivedFile, error) {
	p.archiveMu.Lock()
	defer p.archiveMu.Unlock()

	normTenant := normalizeArchiveTenantID(tenantID)
	entry, ok := p.archivedFiles[archiveID]
	if !ok || entry == nil {
		// Fallback match by BatchID or FileName for resilience across client/server IDs
		for _, candidate := range p.archivedFiles {
			if candidate.TenantID == normTenant &&
				(candidate.BatchID == archiveID || strings.EqualFold(candidate.FileName, archiveID)) {
				entry = candidate
				archiveID = candidate.ID
				ok = true
				break
			}
		}
	}
	if !ok || entry == nil {
		return nil, fmt.Errorf("archived file not found: %s", archiveID)
	}
	if entry.TenantID != normTenant && tenantID != "system" && tenantID != "all" && tenantID != "tenant-system" && tenantID != "tenant-all" {
		return nil, fmt.Errorf("unauthorized tenant access to archived file")
	}

	deletedEntry := *entry

	// 0. Record permanent deletion tombstone in Cloud Firestore and disk so it never resurrects on refresh or restart
	if p.fsRepo != nil {
		_ = p.fsRepo.MarkArchiveDeleted(ctx, normTenant, deletedEntry.ID, deletedEntry.FileName)
	}
	p.appendDiskTombstoneLocked(normTenant, deletedEntry.ID, deletedEntry.FileName)

	// 1. Remove from in-memory maps
	delete(p.archivedFiles, archiveID)
	delete(p.archivedBytes, archiveID)

	// 2. Remove physical file from disk if exists
	if entry.StoragePath != "" {
		_ = os.Remove(entry.StoragePath)
	}

	// 3. Remove entry from index.json on disk
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

	// 4. Purge facts / analytics from BigQuery and Firestore:
	isSellInFile := isSellInArchiveEntry(&deletedEntry)
	if isSellInFile {
		// Only remove Sell-In records belonging to this deleted Sell-In file; never touch Sell-Out or other Sell-In files!
		_ = p.bqRepo.RemoveSellInFileRecords(ctx, normTenant, deletedEntry.BatchID, deletedEntry.FileName, deletedEntry.RetailChain)
		return &deletedEntry, nil
	}

	remainingSellOutTenantFiles := 0
	remainingSellOutChainFiles := 0
	for _, f := range p.archivedFiles {
		if f.TenantID == normTenant && !isSellInArchiveEntry(f) {
			remainingSellOutTenantFiles++
			if strings.EqualFold(f.RetailChain, deletedEntry.RetailChain) {
				remainingSellOutChainFiles++
			}
		}
	}

	if remainingSellOutTenantFiles == 0 {
		// Purge all Sell-Out records for all chains of this tenant
		_ = p.bqRepo.RemoveBatchRecords(ctx, normTenant, "", "")
		_ = p.fsRepo.ClearTenantData(ctx, normTenant)
	} else if remainingSellOutChainFiles == 0 {
		_ = p.bqRepo.RemoveBatchRecords(ctx, normTenant, "", deletedEntry.RetailChain)
	} else {
		_ = p.bqRepo.RemoveBatchRecords(ctx, normTenant, deletedEntry.BatchID, deletedEntry.RetailChain)
	}

	return &deletedEntry, nil
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
	}
}

// ReplayArchivedFilesToDatabase replays all existing archived files on disk into BigQuery and Firestore on server startup.
// It ensures ONLY real user-uploaded files on disk exist in the system, and never re-reads external directories.
func (p *Processor) ReplayArchivedFilesToDatabase(ctx context.Context) error {
	p.archiveMu.Lock()
	p.loadDiskArchiveLocked()
	files := make([]*ArchivedFile, 0, len(p.archivedFiles))
	hasSeedSellIn := false
	for _, f := range p.archivedFiles {
		files = append(files, f)
		if strings.EqualFold(f.FileName, "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx") {
			hasSeedSellIn = true
		}
	}
	p.archiveMu.Unlock()

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

	// Sort files chronologically so earlier files are processed first
	sort.Slice(files, func(i, j int) bool {
		return files[i].UploadedAt < files[j].UploadedAt
	})

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
			if b, err := os.ReadFile(targetPath); err == nil && len(b) > 0 {
				raw = b
				p.archiveMu.Lock()
				p.archivedBytes[f.ID] = b
				p.archiveMu.Unlock()
			}
		}
		if len(raw) == 0 {
			continue
		}

		if isSellInArchiveEntry(f) {
			_, _ = p.ProcessSellInPlan(ctx, f.TenantID, f.FileName, raw, false, f.RetailChain)
		} else {
			_, _ = p.ProcessUpload(ctx, f.TenantID, f.FileName, raw, f.RetailChain)
		}
	}

	return nil
}


package ingestion

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func newArchiveTestProcessor(dir string) *Processor {
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	return NewProcessor(agent, bigquery.NewClient("test-proj", "test-dataset", true), firestore.NewClient("test-db", true)).WithArchiveDir(dir)
}

// An upload handled by one Cloud Run instance must show in the list served by another instance
// that shares the same archive mount.
func TestSellInArchiveVisibleAcrossInstances(t *testing.T) {
	dir := t.TempDir()
	a := newArchiveTestProcessor(dir)
	b := newArchiveTestProcessor(dir) // started before the upload

	if n := len(b.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in").Files); n != 0 {
		t.Fatalf("expected empty archive, got %d", n)
	}
	a.SaveArchivedFile("tenant-adeco", "batch_sellin_20261101_abcd", "Sell In Nov.xlsx", []byte("x"), "fathalla", "2026", "11", 10, 2, 100)

	b.syncArchiveFromDisk("tenant-adeco", true)
	files := b.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in").Files
	if len(files) != 1 || files[0].FileName != "Sell In Nov.xlsx" || files[0].FileType != "sell_in" {
		t.Fatalf("instance B does not list the Sell-In upload from instance A: %+v", files)
	}
	if n := len(b.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out").Files); n != 0 {
		t.Fatalf("Sell-In upload leaked into Sell-Out list: %d", n)
	}

	// A retry of the same file on a third instance replaces, not duplicates, the entry.
	c := newArchiveTestProcessor(t.TempDir())
	c.archiveDir = dir
	c.SaveArchivedFile("tenant-adeco", "batch_sellin_20261101_efgh", "Sell In Nov.xlsx", []byte("y"), "fathalla", "2026", "11", 10, 2, 100)
	b.syncArchiveFromDisk("tenant-adeco", true)
	files = b.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in").Files
	if len(files) != 1 || files[0].BatchID != "batch_sellin_20261101_efgh" {
		t.Fatalf("expected only the newest retry, got %+v", files)
	}
}

func insertSharedArchive(t *testing.T, procs []*Processor, entry *ArchivedFile, raw []byte) {
	t.Helper()
	for _, p := range procs {
		copyEntry := *entry
		p.InsertArchivedFileEntry(&copyEntry, raw)
	}
}

func listHasID(files []*ArchivedFile, id string) bool {
	for _, f := range files {
		if f != nil && f.ID == id {
			return true
		}
	}
	return false
}

// After instance A deletes an archive (incl. a seed-index row), instance B's list must drop it
// on a plain List (page refresh) — without force-sync and without a process restart.
// Covers Sell-Out and Sell-In (Mohamed: Sell-In flaps hardest after refresh).
func TestDeleteRemovesFromListAcrossInstances(t *testing.T) {
	for _, tc := range []struct {
		name     string
		fileType string
		id       string
		fileName string
		batchID  string
	}{
		{
			name:     "sell_out_seed",
			fileType: "sell_out",
			id:       "arch_adeco_fathalla_1792255997606803322",
			fileName: "2025 out.xlsx",
			batchID:  "batch_20261023153339_5cae5689",
		},
		{
			name:     "sell_in_seed",
			fileType: "sell_in",
			id:       "arch_sellin_adeco_fathalla_1792619328568966000",
			fileName: "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
			batchID:  "batch_sellin_20261023153351_e57d5ae0",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			a := newArchiveTestProcessor(dir)
			b := newArchiveTestProcessor(dir)
			entry := &ArchivedFile{
				ID:           tc.id,
				BatchID:      tc.batchID,
				FileType:     tc.fileType,
				TenantID:     "tenant-adeco",
				FileName:     tc.fileName,
				RetailChain:  "fathalla",
				TargetYear:   "2026",
				RowsIngested: 100,
				UploadedAt:   "2026-10-23T12:33:51.680341Z",
			}
			insertSharedArchive(t, []*Processor{a, b}, entry, []byte("seed-xlsx"))

			// Prime B's disk-sync throttle so a naive refresh would previously skip tombstone prune.
			b.syncArchiveFromDisk("tenant-adeco", true)

			if _, err := a.DeleteArchivedFile(context.Background(), "tenant-adeco", tc.id); err != nil {
				t.Fatalf("delete on A: %v", err)
			}
			if listHasID(a.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", tc.fileType).Files, tc.id) {
				t.Fatal("deleting instance still lists archive after delete")
			}

			// Plain list = page refresh on peer (must not reappear even inside sync throttle window).
			if listHasID(b.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", tc.fileType).Files, tc.id) {
				t.Fatal("peer instance still lists deleted archive after refresh (tombstone not applied)")
			}
		})
	}
}

// A brand-new process that loads the shared archive dir must not resurrect a deleted seed-index id.
func TestDeleteSeedIndexGoneAfterReloadNewInstance(t *testing.T) {
	for _, tc := range []struct {
		name     string
		fileType string
		id       string
		fileName string
		batchID  string
	}{
		{
			name:     "sell_out",
			fileType: "sell_out",
			id:       "arch_adeco_fathalla_1792258238476465882",
			fileName: "2026 out.xlsx",
			batchID:  "batch_20261023153324_68c4fd43",
		},
		{
			name:     "sell_in",
			fileType: "sell_in",
			id:       "arch_sellin_adeco_fathalla_1792619328568966000",
			fileName: "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
			batchID:  "batch_sellin_20261023153351_e57d5ae0",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			tenantDir := dir + "/tenant-adeco"
			if err := os.MkdirAll(tenantDir, 0o755); err != nil {
				t.Fatal(err)
			}
			storage := tenantDir + "/" + tc.id + "_" + tc.fileName
			index := `[
  {
    "id": "` + tc.id + `",
    "batch_id": "` + tc.batchID + `",
    "file_type": "` + tc.fileType + `",
    "tenant_id": "tenant-adeco",
    "file_name": "` + tc.fileName + `",
    "retail_chain": "fathalla",
    "target_year": "2026",
    "rows_ingested": 100,
    "uploaded_at": "2026-10-23T12:33:38.35024Z",
    "storage_path": "` + storage + `"
  }
]`
			if err := os.WriteFile(tenantDir+"/index.json", []byte(index), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(storage, []byte("xlsx"), 0o644); err != nil {
				t.Fatal(err)
			}

			p1 := newArchiveTestProcessor(dir)
			listed := p1.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", tc.fileType)
			if listed.TotalCount != 1 || listed.Files[0].ID != tc.id {
				t.Fatalf("expected seed loaded from index, got %+v", listed)
			}
			if _, err := p1.DeleteArchivedFile(context.Background(), "tenant-adeco", tc.id); err != nil {
				t.Fatalf("delete: %v", err)
			}
			if n := p1.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", tc.fileType).TotalCount; n != 0 {
				t.Fatalf("after delete want 0, got %d", n)
			}

			p2 := newArchiveTestProcessor(dir)
			after := p2.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", tc.fileType)
			if listHasID(after.Files, tc.id) {
				t.Fatalf("new instance resurrected deleted seed-index entry: %+v", after.Files)
			}
			if after.TotalCount != 0 {
				t.Fatalf("expected empty %s list after reload, got %d", tc.fileType, after.TotalCount)
			}
		})
	}
}

// Mohamed flap: delete file A on instance 1 → peer refresh briefly shows it → later gone →
// deleting file B on the peer must NOT rewrite A back into the shared index / list.
func TestDeleteOtherFileDoesNotResurrectPeerDeletedArchive(t *testing.T) {
	for _, fileType := range []string{"sell_in", "sell_out"} {
		t.Run(fileType, func(t *testing.T) {
			dir := t.TempDir()
			a := newArchiveTestProcessor(dir)
			b := newArchiveTestProcessor(dir)

			idKeepGone := "arch_gone_" + fileType
			idOther := "arch_other_" + fileType
			insertSharedArchive(t, []*Processor{a, b}, &ArchivedFile{
				ID: idKeepGone, BatchID: "batch_gone", FileType: fileType, TenantID: "tenant-adeco",
				FileName: "gone.xlsx", RetailChain: "fathalla", TargetYear: "2026",
				RowsIngested: 10, UploadedAt: "2026-10-23T12:00:00Z",
			}, []byte("a"))
			insertSharedArchive(t, []*Processor{a, b}, &ArchivedFile{
				ID: idOther, BatchID: "batch_other", FileType: fileType, TenantID: "tenant-adeco",
				FileName: "other.xlsx", RetailChain: "fathalla", TargetYear: "2026",
				RowsIngested: 20, UploadedAt: "2026-10-23T12:01:00Z",
			}, []byte("b"))

			if _, err := a.DeleteArchivedFile(context.Background(), "tenant-adeco", idKeepGone); err != nil {
				t.Fatalf("delete gone on A: %v", err)
			}
			// Peer deletes a different file (rewrites index.json from its memory).
			if _, err := b.DeleteArchivedFile(context.Background(), "tenant-adeco", idOther); err != nil {
				t.Fatalf("delete other on B: %v", err)
			}

			for _, p := range []*Processor{a, b, newArchiveTestProcessor(dir)} {
				files := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", fileType).Files
				if listHasID(files, idKeepGone) {
					t.Fatalf("deleted id %s reappeared after peer deleted another file: %+v", idKeepGone, files)
				}
				if listHasID(files, idOther) {
					t.Fatalf("other deleted id %s still listed: %+v", idOther, files)
				}
			}
		})
	}
}

// Live Sell-In 01:45–01:52 Cairo (rev 00062): three Cloud Run instances with concurrent deletes/lists.
// Tombstones must live on the shared archive mount so every instance's List drops deleted ids.
func TestSellInThreeInstancesConvergeOnSharedTombstones(t *testing.T) {
	dir := t.TempDir()
	inst5aec := newArchiveTestProcessor(dir)
	instD931 := newArchiveTestProcessor(dir)
	inst4eb9 := newArchiveTestProcessor(dir)

	type file struct {
		id, name, batch string
	}
	files := []file{
		{"arch_si_12_unknown", "12_unknown_barcode.xlsx", "batch_si_12"},
		{"arch_si_06_form", "06_form_vs_sheet.xlsx", "batch_si_06"},
		{"arch_si_in26", "in26.xlsx", "batch_si_in26"},
		{"arch_si_13_fuzzy", "13_fuzzy_near_match.xlsx", "batch_si_13"},
		{"arch_si_adeco_seed", "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", "batch_si_seed"},
	}
	procs := []*Processor{inst5aec, instD931, inst4eb9}
	for i, f := range files {
		insertSharedArchive(t, procs, &ArchivedFile{
			ID: f.id, BatchID: f.batch, FileType: "sell_in", TenantID: "tenant-adeco",
			FileName: f.name, RetailChain: "fathalla", TargetYear: "2026",
			RowsIngested: 100 + i, UploadedAt: fmt.Sprintf("2026-11-07T23:40:%02dZ", i),
		}, []byte(f.name))
	}

	// 4eb9 never had 13_fuzzy (live DELETE 404 shape) before the concurrent wave.
	inst4eb9.archiveMu.Lock()
	delete(inst4eb9.archivedFiles, "arch_si_13_fuzzy")
	delete(inst4eb9.archivedBytes, "arch_si_13_fuzzy")
	inst4eb9.archiveMu.Unlock()

	var start, deletesDone sync.WaitGroup
	start.Add(1)
	deletesDone.Add(3)
	errCh := make(chan error, 8)

	go func() {
		defer deletesDone.Done()
		start.Wait()
		for _, id := range []string{"arch_si_12_unknown", "arch_si_06_form", "arch_si_13_fuzzy"} {
			if _, err := inst5aec.DeleteArchivedFile(context.Background(), "tenant-adeco", id); err != nil && !errors.Is(err, ErrArchivedFileNotFound) {
				errCh <- fmt.Errorf("5aec delete %s: %w", id, err)
				return
			}
		}
	}()
	go func() {
		defer deletesDone.Done()
		start.Wait()
		if _, err := instD931.DeleteArchivedFile(context.Background(), "tenant-adeco", "arch_si_in26"); err != nil && !errors.Is(err, ErrArchivedFileNotFound) {
			errCh <- fmt.Errorf("d931 delete in26: %w", err)
		}
	}()
	go func() {
		defer deletesDone.Done()
		start.Wait()
		// Concurrent list pressure on the peer that did not own the deletes.
		for i := 0; i < 5; i++ {
			_ = inst4eb9.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in")
		}
		if _, err := inst4eb9.DeleteArchivedFile(context.Background(), "tenant-adeco", "arch_si_13_fuzzy"); err != nil && !errors.Is(err, ErrArchivedFileNotFound) {
			errCh <- fmt.Errorf("4eb9 delete 13_fuzzy: %w", err)
		}
	}()
	start.Done()
	deletesDone.Wait()
	close(errCh)
	for err := range errCh {
		t.Fatal(err)
	}

	wantTombs := []string{"arch_si_12_unknown", "arch_si_06_form", "arch_si_in26", "arch_si_13_fuzzy"}
	for _, id := range wantTombs {
		path := filepath.Join(dir, diskTombstoneDir, "id_"+sanitizeArchiveFilename(id)+".json")
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("shared per-id tombstone missing for %s after concurrent deletes: %v", id, err)
		}
	}

	var listWG sync.WaitGroup
	listWG.Add(4)
	listErr := make(chan error, 4)
	check := func(p *Processor, label string) {
		defer listWG.Done()
		listed := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in")
		for _, gone := range []string{"arch_si_12_unknown", "arch_si_06_form", "arch_si_in26", "arch_si_13_fuzzy"} {
			if listHasID(listed.Files, gone) {
				listErr <- fmt.Errorf("%s still lists deleted Sell-In %s: %+v", label, gone, listed.Files)
				return
			}
		}
		if listed.TotalCount != 1 || listed.Files[0].ID != "arch_si_adeco_seed" {
			listErr <- fmt.Errorf("%s want only Adeco seed Sell-In, got %+v", label, listed.Files)
		}
	}
	go check(inst4eb9, "4eb9")
	go check(instD931, "d931")
	go check(inst5aec, "5aec")
	go check(newArchiveTestProcessor(dir), "fresh")
	listWG.Wait()
	close(listErr)
	for err := range listErr {
		t.Fatal(err)
	}
}

// Delete then same-name reupload must stay visible on the uploading instance, a peer, and a fresh
// process — while the OLD archive id remains tombstoned (Sell-In and Sell-Out).
func TestSameNameReuploadVisibleAcrossInstancesAfterDelete(t *testing.T) {
	for _, fileType := range []string{"sell_in", "sell_out"} {
		t.Run(fileType, func(t *testing.T) {
			dir := t.TempDir()
			a := newArchiveTestProcessor(dir)
			b := newArchiveTestProcessor(dir)

			oldID := "arch_old_" + fileType
			fileName := "reupload_same_name.xlsx"
			batchPrefix := "batch_" + fileType + "_"
			if fileType == "sell_in" {
				batchPrefix = "batch_sellin_"
			}
			insertSharedArchive(t, []*Processor{a, b}, &ArchivedFile{
				ID: oldID, BatchID: batchPrefix + "old", FileType: fileType, TenantID: "tenant-adeco",
				FileName: fileName, RetailChain: "fathalla", TargetYear: "2026",
				RowsIngested: 10, UploadedAt: "2026-11-07T22:00:00Z",
			}, []byte("old"))

			if _, err := a.DeleteArchivedFile(context.Background(), "tenant-adeco", oldID); err != nil {
				t.Fatalf("delete: %v", err)
			}
			// Simulate legacy disk tombs that still carry file_name on the id row (prod shape before fix).
			tombPath := filepath.Join(dir, "deleted_tombstones.json")
			legacy := []diskTombstoneItem{{
				TenantID: "tenant-adeco", ArchiveID: oldID, FileName: fileName,
			}}
			raw, _ := json.MarshalIndent(legacy, "", "  ")
			if err := os.WriteFile(tombPath, raw, 0o644); err != nil {
				t.Fatal(err)
			}
			// Peer B already applied a stale name tombstone into memory (pre-fix Remember behavior).
			b.fsRepo.RememberArchiveDeleted("tenant-adeco", "", fileName)

			newEntry := a.SaveArchivedFile("tenant-adeco", batchPrefix+"new", fileName, []byte("new-bytes"), "fathalla", "2026", "11", 20, 1, 100)
			if newEntry == nil || newEntry.ID == "" || newEntry.ID == oldID {
				t.Fatalf("expected new archive id after reupload, got %+v", newEntry)
			}

			assertVisible := func(p *Processor, label string) {
				t.Helper()
				listed := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", fileType)
				if listHasID(listed.Files, oldID) {
					t.Fatalf("%s still lists deleted old id %s", label, oldID)
				}
				if !listHasID(listed.Files, newEntry.ID) {
					t.Fatalf("%s missing reuploaded %s (%s): %+v", label, fileName, newEntry.ID, listed.Files)
				}
			}
			assertVisible(a, "uploader-A")
			assertVisible(b, "peer-B")
			fresh := newArchiveTestProcessor(dir)
			assertVisible(fresh, "fresh-C")
			if !fresh.fsRepo.IsArchiveDeleted("tenant-adeco", oldID, "") {
				t.Fatal("old archive id lost its tombstone after same-name reupload")
			}
		})
	}
}

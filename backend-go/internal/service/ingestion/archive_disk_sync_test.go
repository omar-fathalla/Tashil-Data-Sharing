package ingestion

import (
	"context"
	"os"
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

// After instance A deletes an archive (incl. a seed-index row), instance B's list must drop it
// once disk tombstones are refreshed — without requiring a process restart.
func TestDeleteRemovesFromListAcrossInstances(t *testing.T) {
	dir := t.TempDir()
	a := newArchiveTestProcessor(dir)
	b := newArchiveTestProcessor(dir)

	seedID := "arch_adeco_fathalla_1792255997606803322"
	a.InsertArchivedFileEntry(&ArchivedFile{
		ID:           seedID,
		BatchID:      "batch_20261023153339_5cae5689",
		FileType:     "sell_out",
		TenantID:     "tenant-adeco",
		FileName:     "2025 out.xlsx",
		RetailChain:  "fathalla",
		TargetYear:   "2025",
		RowsIngested: 28015,
		UploadedAt:   "2026-10-23T12:33:51.680341Z",
	}, []byte("seed-xlsx"))
	// Instance B loads the same seed the way Cloud Run does at startup (shared mount index).
	b.InsertArchivedFileEntry(&ArchivedFile{
		ID:           seedID,
		BatchID:      "batch_20261023153339_5cae5689",
		FileType:     "sell_out",
		TenantID:     "tenant-adeco",
		FileName:     "2025 out.xlsx",
		RetailChain:  "fathalla",
		TargetYear:   "2025",
		RowsIngested: 28015,
		UploadedAt:   "2026-10-23T12:33:51.680341Z",
	}, []byte("seed-xlsx"))

	if _, err := a.DeleteArchivedFile(context.Background(), "tenant-adeco", seedID); err != nil {
		t.Fatalf("delete on A: %v", err)
	}
	for _, f := range a.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out").Files {
		if f.ID == seedID {
			t.Fatal("deleting instance still lists seed archive after delete")
		}
	}

	// Force sync so B reloads disk tombstones within the 10s throttle window.
	b.syncArchiveFromDisk("tenant-adeco", true)
	for _, f := range b.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out").Files {
		if f.ID == seedID {
			t.Fatal("peer instance still lists deleted seed archive (tombstone not applied)")
		}
	}
}

// A brand-new process that loads the shared archive dir must not resurrect a deleted seed-index id.
func TestDeleteSeedIndexGoneAfterReloadNewInstance(t *testing.T) {
	dir := t.TempDir()
	tenantDir := dir + "/tenant-adeco"
	if err := os.MkdirAll(tenantDir, 0o755); err != nil {
		t.Fatal(err)
	}
	seedID := "arch_adeco_fathalla_1792258238476465882"
	index := `[
  {
    "id": "` + seedID + `",
    "batch_id": "batch_20261023153324_68c4fd43",
    "file_type": "sell_out",
    "tenant_id": "tenant-adeco",
    "file_name": "2026 out.xlsx",
    "retail_chain": "fathalla",
    "target_year": "2026",
    "rows_ingested": 30643,
    "uploaded_at": "2026-10-23T12:33:38.35024Z",
    "storage_path": "` + tenantDir + `/` + seedID + `_2026 out.xlsx"
  }
]`
	if err := os.WriteFile(tenantDir+"/index.json", []byte(index), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(tenantDir+"/"+seedID+"_2026 out.xlsx", []byte("xlsx"), 0o644); err != nil {
		t.Fatal(err)
	}

	p1 := newArchiveTestProcessor(dir)
	listed := p1.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out")
	if listed.TotalCount != 1 || listed.Files[0].ID != seedID {
		t.Fatalf("expected seed loaded from index, got %+v", listed)
	}
	if _, err := p1.DeleteArchivedFile(context.Background(), "tenant-adeco", seedID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if n := p1.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out").TotalCount; n != 0 {
		t.Fatalf("after delete want 0, got %d", n)
	}

	// New Cloud Run instance / process restart sharing the mount.
	p2 := newArchiveTestProcessor(dir)
	after := p2.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out")
	for _, f := range after.Files {
		if f.ID == seedID {
			t.Fatalf("new instance resurrected deleted seed-index entry: %+v", f)
		}
	}
	if after.TotalCount != 0 {
		t.Fatalf("expected empty sell-out list after reload, got %d", after.TotalCount)
	}
}

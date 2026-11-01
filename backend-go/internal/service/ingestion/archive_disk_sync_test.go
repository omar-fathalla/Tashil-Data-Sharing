package ingestion

import (
	"context"
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

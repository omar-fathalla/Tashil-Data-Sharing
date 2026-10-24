package ingestion

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func newSnapshotTestProcessor(t *testing.T, archiveDir string) (*Processor, *bigquery.Client, *firestore.Client) {
	t.Helper()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fsr := firestore.NewClient("test-db", true)
	p := NewProcessor(gemini.NewAgent("", "gemini-3.8-flash", true), bq, fsr).WithArchiveDir(archiveDir)
	p.snap.buildID = "test-build"
	return p, bq, fsr
}

func seedSnapshotData(t *testing.T, bq *bigquery.Client, fsr *firestore.Client) {
	t.Helper()
	ctx := context.Background()
	facts := []domain.SellOutFact{
		{RecordID: "r1", TenantID: "tenant-a", RetailerChain: "fathalla", StoreID: "s1", Barcode: "111", SKUName: "Tea", Category: "Beverages", Supplier: "Acme", IsOwnBrand: true},
		{RecordID: "r2", TenantID: "tenant-b", RetailerChain: "gomla", StoreID: "s9", Barcode: "222", SKUName: "Rice", Category: "Grocery", Supplier: "Other"},
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatalf("insert facts: %v", err)
	}
	if err := fsr.SaveIngestionBatch(ctx, &domain.IngestionBatch{BatchID: "b1", TenantID: "tenant-a", Filename: "a.xlsx", TotalRows: 2, TotalRevenue: 12.5}); err != nil {
		t.Fatalf("save batch: %v", err)
	}
}

func writeArchiveFile(t *testing.T, dir, name, content string) {
	t.Helper()
	path := filepath.Join(dir, "tenant-a", name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func exportBoth(t *testing.T, bq *bigquery.Client, fsr *firestore.Client) ([]byte, []byte) {
	t.Helper()
	b, err := bq.ExportSnapshot()
	if err != nil {
		t.Fatalf("bq export: %v", err)
	}
	f, err := fsr.ExportSnapshot()
	if err != nil {
		t.Fatalf("fs export: %v", err)
	}
	return b, f
}

func TestSnapshotRoundTripRestoresIdenticalState(t *testing.T) {
	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	p, bq, fsr := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, bq, fsr)
	wantBQ, wantFS := exportBoth(t, bq, fsr)

	if err := p.WriteSnapshot(); err != nil {
		t.Fatalf("WriteSnapshot: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "_snapshot", "state.json.gz")); err != nil {
		t.Fatalf("snapshot file missing: %v", err)
	}

	p2, bq2, fsr2 := newSnapshotTestProcessor(t, dir)
	_ = p2.ClearTenantData(context.Background(), "all")
	mode, err := p2.RestoreOrReplay(context.Background())
	if err != nil || mode != "snapshot" {
		t.Fatalf("expected snapshot restore, got mode=%s err=%v", mode, err)
	}
	gotBQ, gotFS := exportBoth(t, bq2, fsr2)
	if !bytes.Equal(wantBQ, gotBQ) {
		t.Fatalf("bigquery state differs after restore")
	}
	if !bytes.Equal(wantFS, gotFS) {
		t.Fatalf("firestore state differs after restore")
	}

	// Tenant isolation: tenant-b data must not be visible under tenant-a.
	recs, _, err := bq2.GetSellOutRecords(context.Background(), "tenant-a", bigquery.RecordFilter{})
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range recs {
		if r.TenantID == "tenant-b" {
			t.Fatalf("tenant-b record leaked into tenant-a results")
		}
	}
}

func TestSnapshotRejectedWhenCorrupt(t *testing.T) {
	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	p, bq, fsr := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, bq, fsr)
	if err := p.WriteSnapshot(); err != nil {
		t.Fatal(err)
	}
	path := p.SnapshotPath()
	raw, _ := os.ReadFile(path)
	if err := os.WriteFile(path, raw[:len(raw)/2], 0o644); err != nil {
		t.Fatal(err)
	}
	p2, _, _ := newSnapshotTestProcessor(t, dir)
	if err := p2.loadSnapshot(); err == nil || !strings.Contains(err.Error(), "corrupt") {
		t.Fatalf("expected corrupt snapshot error, got %v", err)
	}
	mode, _ := p2.RestoreOrReplay(context.Background())
	if mode != "replay" {
		t.Fatalf("expected fallback to replay, got %s", mode)
	}
	// A fresh, valid snapshot is written after the fallback replay.
	p3, _, _ := newSnapshotTestProcessor(t, dir)
	if err := p3.loadSnapshot(); err != nil {
		t.Fatalf("expected fresh snapshot after replay, got %v", err)
	}
}

func TestSnapshotRejectedWhenArchiveChanged(t *testing.T) {
	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	p, bq, fsr := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, bq, fsr)
	if err := p.WriteSnapshot(); err != nil {
		t.Fatal(err)
	}
	// New upload after the snapshot -> stale.
	writeArchiveFile(t, dir, "new_upload.xlsx", "more")
	p2, _, _ := newSnapshotTestProcessor(t, dir)
	if err := p2.loadSnapshot(); err == nil || !strings.Contains(err.Error(), "stale") {
		t.Fatalf("expected stale error after new file, got %v", err)
	}
	// Modified file contents (same name) -> stale.
	_ = os.Remove(filepath.Join(dir, "tenant-a", "new_upload.xlsx"))
	future := time.Now().Add(time.Hour)
	_ = os.Chtimes(filepath.Join(dir, "tenant-a", "sales.xlsx"), future, future)
	if err := p2.loadSnapshot(); err == nil || !strings.Contains(err.Error(), "stale") {
		t.Fatalf("expected stale error after modified file, got %v", err)
	}
}

func TestSnapshotRejectedForDifferentBuild(t *testing.T) {
	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	p, bq, fsr := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, bq, fsr)
	if err := p.WriteSnapshot(); err != nil {
		t.Fatal(err)
	}
	p2, _, _ := newSnapshotTestProcessor(t, dir)
	p2.snap.buildID = "other-build"
	if err := p2.loadSnapshot(); err == nil || !strings.Contains(err.Error(), "different server build") {
		t.Fatalf("expected build mismatch, got %v", err)
	}
}

func TestSnapshotDirIgnoredByArchiveLoader(t *testing.T) {
	dir := t.TempDir()
	writeArchiveFile(t, dir, "sales.xlsx", "workbook-bytes")
	p, bq, fsr := newSnapshotTestProcessor(t, dir)
	seedSnapshotData(t, bq, fsr)
	if err := p.WriteSnapshot(); err != nil {
		t.Fatal(err)
	}
	m1, _ := p.buildManifest()
	for _, e := range m1 {
		if strings.Contains(e.Path, "_snapshot") {
			t.Fatalf("snapshot dir must not be part of its own manifest: %s", e.Path)
		}
	}
}

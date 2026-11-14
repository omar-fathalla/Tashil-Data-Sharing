package ingestion

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func TestDeleteArchivedFileFailsWhenSinkFailsAndKeepsFileListed(t *testing.T) {
	dir := t.TempDir()
	fs := &fakeSink{fail: errors.New("bq permission denied")}
	p := newTestProcessor(t, dir).WithSink(fs)
	ctx := context.Background()

	res := processUploadApproved(t, p, ctx, "tenant-adeco", "fathalla_weekly.csv", sampleCSV)
	before := p.ListArchivedFiles(ctx, "tenant-adeco", "", "", "", "sell_out")
	if before.TotalCount == 0 {
		t.Fatal("expected archive entry before delete")
	}

	_, err := p.DeleteArchivedFile(ctx, "tenant-adeco", res.ArchiveID)
	if err == nil {
		t.Fatal("expected BigQuery delete failure to surface")
	}
	var ade *ArchiveDeleteError
	if !errors.As(err, &ade) || ade.Stage != "bigquery" {
		t.Fatalf("expected ArchiveDeleteError stage=bigquery, got %v", err)
	}
	if !strings.Contains(err.Error(), "bq permission denied") {
		t.Fatalf("error should include sink message, got %v", err)
	}

	after := p.ListArchivedFiles(ctx, "tenant-adeco", "", "", "", "sell_out")
	if after.TotalCount != before.TotalCount {
		t.Fatalf("failed delete must keep file listed: before=%d after=%d", before.TotalCount, after.TotalCount)
	}
	found := false
	for _, f := range after.Files {
		if f.ID == res.ArchiveID {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("deleted archive id missing from list after failed BigQuery delete")
	}
}

func TestDeleteArchivedFileSucceedsOnlyAfterSinkDelete(t *testing.T) {
	dir := t.TempDir()
	fs := &fakeSink{}
	p := newTestProcessor(t, dir).WithSink(fs)
	ctx := context.Background()
	res := processUploadApproved(t, p, ctx, "tenant-adeco", "gomla_weekly.csv", sampleCSV)
	deleted, err := p.DeleteArchivedFile(ctx, "tenant-adeco", res.ArchiveID)
	if err != nil {
		t.Fatal(err)
	}
	if deleted.FileName != "gomla_weekly.csv" {
		t.Fatalf("unexpected deleted entry: %+v", deleted)
	}
	if len(fs.deletes) != 1 {
		t.Fatalf("expected one sink delete, got %+v", fs.deletes)
	}
	after := p.ListArchivedFiles(ctx, "tenant-adeco", "", "", "", "sell_out")
	for _, f := range after.Files {
		if f.ID == res.ArchiveID {
			t.Fatal("successful delete must remove file from list")
		}
	}
}

func TestDeleteLastSellOutFileClearsLeftoverFacts(t *testing.T) {
	// Last Sell-Out archive must clear leftover in-memory facts whose batch id no longer
	// matches (hydrated / stale index). It must not call ClearTenantData (Sell-In stays).
	dir := t.TempDir()
	p := newTestProcessor(t, dir)
	ctx := context.Background()

	bq, ok := p.bqRepo.(*bigquery.Client)
	if !ok {
		t.Fatal("expected *bigquery.Client")
	}
	facts := []domain.SellOutFact{
		{TenantID: "tenant-adeco", IngestionBatchID: "batch_stale", RetailerChain: "fathalla", Barcode: "1", NetRevenue: 10, RecordID: "stale-1"},
		{TenantID: "tenant-adeco", IngestionBatchID: "batch_delete", RetailerChain: "fathalla", Barcode: "2", NetRevenue: 20, RecordID: "del-1"},
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	sellIn := []domain.SellInRecord{{
		TenantID: "tenant-adeco", SourceFilename: "in26.xlsx", RetailerChain: "fathalla",
		Year: 2026, MonthNum: 1, CustomerName: "فرع", NetQtyCases: 5, NetValueEGP: 100,
	}}
	if err := bq.SetSellInRecords(ctx, "tenant-adeco", "in26.xlsx", sellIn); err != nil {
		t.Fatal(err)
	}

	entry := p.SaveArchivedFile("tenant-adeco", "batch_delete", "last_out.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 20)
	if _, err := p.DeleteArchivedFile(ctx, "tenant-adeco", entry.ID); err != nil {
		t.Fatal(err)
	}

	if snap := bq.SellOutFactsSnapshot("tenant-adeco"); len(snap) != 0 {
		t.Fatalf("last-file delete must clear leftover sell-out facts, got %+v", snap)
	}
	got, _, err := bq.GetSellInRecords(ctx, "tenant-adeco", bigquery.SellInRecordFilter{})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].NetValueEGP != 100 {
		t.Fatalf("Sell-In must be preserved after last Sell-Out delete, got %+v", got)
	}
}

func TestDeleteSellOutFileFallsBackToFilename(t *testing.T) {
	dir := t.TempDir()
	p := newTestProcessor(t, dir)
	ctx := context.Background()
	bq := p.bqRepo.(*bigquery.Client)
	facts := []domain.SellOutFact{
		{TenantID: "tenant-adeco", IngestionBatchID: "old_batch", SourceFilename: "out26.xlsx", RetailerChain: "fathalla", Barcode: "1", NetRevenue: 10, RecordID: "a"},
		{TenantID: "tenant-adeco", IngestionBatchID: "other_batch", SourceFilename: "other.xlsx", RetailerChain: "fathalla", Barcode: "2", NetRevenue: 20, RecordID: "b"},
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	// Two archives so this is not a last-file clear.
	keep := p.SaveArchivedFile("tenant-adeco", "other_batch", "other.xlsx", []byte("y"), "fathalla", "2026", "02", 1, 1, 20)
	del := p.SaveArchivedFile("tenant-adeco", "new_batch", "out26.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 10)
	_ = keep
	if _, err := p.DeleteArchivedFile(ctx, "tenant-adeco", del.ID); err != nil {
		t.Fatal(err)
	}
	var got []domain.SellOutFact
	for _, r := range bq.SellOutFactsSnapshot("tenant-adeco") {
		if r.RecordID == "a" || r.RecordID == "b" {
			got = append(got, r)
		}
	}
	if len(got) != 1 || got[0].RecordID != "b" {
		t.Fatalf("filename fallback must drop out26 leftovers and keep other.xlsx, got %+v", got)
	}
}

func TestDeleteOneOfTwoSellOutFilesKeepsTheOther(t *testing.T) {
	dir := t.TempDir()
	p := newTestProcessor(t, dir)
	ctx := context.Background()
	bq := p.bqRepo.(*bigquery.Client)
	facts := []domain.SellOutFact{
		{TenantID: "tenant-adeco", IngestionBatchID: "batch_keep", SourceFilename: "keep.xlsx", RetailerChain: "fathalla", Barcode: "1", NetRevenue: 10, RecordID: "keep-1"},
		{TenantID: "tenant-adeco", IngestionBatchID: "batch_delete", SourceFilename: "del.xlsx", RetailerChain: "fathalla", Barcode: "2", NetRevenue: 20, RecordID: "del-1"},
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	keep := p.SaveArchivedFile("tenant-adeco", "batch_keep", "keep.xlsx", []byte("k"), "fathalla", "2026", "01", 1, 1, 10)
	del := p.SaveArchivedFile("tenant-adeco", "batch_delete", "del.xlsx", []byte("d"), "fathalla", "2026", "02", 1, 1, 20)
	_ = keep
	if _, err := p.DeleteArchivedFile(ctx, "tenant-adeco", del.ID); err != nil {
		t.Fatal(err)
	}
	var got []domain.SellOutFact
	for _, r := range bq.SellOutFactsSnapshot("tenant-adeco") {
		if r.RecordID == "keep-1" || r.RecordID == "del-1" {
			got = append(got, r)
		}
	}
	if len(got) != 1 || got[0].IngestionBatchID != "batch_keep" {
		t.Fatalf("deleting one of two files must keep the other, got %+v", got)
	}
}

func TestDeleteArchivedFileNotFoundError(t *testing.T) {
	p := newTestProcessor(t, t.TempDir())
	_, err := p.DeleteArchivedFile(context.Background(), "tenant-adeco", "missing-id")
	if !errors.Is(err, ErrArchivedFileNotFound) {
		t.Fatalf("want ErrArchivedFileNotFound, got %v", err)
	}
}

func TestDeleteSellInFileReportsSinkFailureAndStaysListed(t *testing.T) {
	dir := t.TempDir()
	fs := &fakeSink{fail: errors.New("sink down")}
	p := newTestProcessor(t, dir).WithSink(fs)
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_1", "sell_in_plan.xlsx", []byte("a"), "fathalla", "2026", "01", 1, 1, 1)

	_, err := p.DeleteArchivedFile(context.Background(), "tenant-adeco", entry.ID)
	if err == nil {
		t.Fatal("expected sink failure")
	}
	var ade *ArchiveDeleteError
	if !errors.As(err, &ade) || ade.Stage != "bigquery" {
		t.Fatalf("expected bigquery stage, got %v", err)
	}
	list := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in")
	if list.TotalCount != 1 {
		t.Fatalf("sell-in file must stay listed after failed delete, got %d", list.TotalCount)
	}
}

// failTombstoneFS wraps a Repository and forces MarkArchiveDeleted to fail after durable deletes succeed.
type failTombstoneFS struct {
	firestore.Repository
	err error
}

func (f *failTombstoneFS) MarkArchiveDeleted(context.Context, string, string, string) error {
	return f.err
}

func TestDeleteArchivedFileFirestoreFailureKeepsFileListed(t *testing.T) {
	dir := t.TempDir()
	baseFS := firestore.NewClient("test-db", true)
	wrapped := &failTombstoneFS{Repository: baseFS, err: errors.New("firestore tombstone write failed")}
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(agent, bqRepo, wrapped).WithArchiveDir(dir).WithSink(&fakeSink{})

	entry := p.SaveArchivedFile("tenant-adeco", "batch_fs", "fs_fail.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 1)
	_, err := p.DeleteArchivedFile(context.Background(), "tenant-adeco", entry.ID)
	if err == nil {
		t.Fatal("expected firestore tombstone failure")
	}
	var ade *ArchiveDeleteError
	if !errors.As(err, &ade) || ade.Stage != "firestore" {
		t.Fatalf("expected ArchiveDeleteError stage=firestore, got %v", err)
	}
	list := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out")
	found := false
	for _, f := range list.Files {
		if f.ID == entry.ID {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("file must stay listed when firestore tombstone fails after BigQuery delete")
	}
}

package ingestion

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

func TestDeleteArchivedFileFailsWhenSinkFailsAndKeepsFileListed(t *testing.T) {
	dir := t.TempDir()
	fs := &fakeSink{fail: errors.New("bq permission denied")}
	p := newTestProcessor(t, dir).WithSink(fs)
	ctx := context.Background()

	res, err := p.ProcessUpload(ctx, "tenant-adeco", "fathalla_weekly.csv", sampleCSV)
	if err != nil {
		t.Fatal(err)
	}
	before := p.ListArchivedFiles(ctx, "tenant-adeco", "", "", "", "sell_out")
	if before.TotalCount == 0 {
		t.Fatal("expected archive entry before delete")
	}

	_, err = p.DeleteArchivedFile(ctx, "tenant-adeco", res.ArchiveID)
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
	res, err := p.ProcessUpload(ctx, "tenant-adeco", "gomla_weekly.csv", sampleCSV)
	if err != nil {
		t.Fatal(err)
	}
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

func TestDeleteLastSellOutFileDoesNotWipeTenant(t *testing.T) {
	// No durable sink: isolate the in-memory purge path that used to wipe the tenant
	// when the last Sell-Out archive was deleted (RemoveBatchRecords("", "") + ClearTenantData).
	dir := t.TempDir()
	p := newTestProcessor(t, dir)
	ctx := context.Background()

	bq, ok := p.bqRepo.(*bigquery.Client)
	if !ok {
		t.Fatal("expected *bigquery.Client")
	}
	facts := []domain.SellOutFact{
		{TenantID: "tenant-adeco", IngestionBatchID: "batch_keep", RetailerChain: "fathalla", Barcode: "1", NetRevenue: 10, RecordID: "keep-1"},
		{TenantID: "tenant-adeco", IngestionBatchID: "batch_delete", RetailerChain: "fathalla", Barcode: "2", NetRevenue: 20, RecordID: "del-1"},
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	if n := len(bq.SellOutFactsSnapshot("tenant-adeco")); n != 2 {
		t.Fatalf("setup: want 2 facts, got %d", n)
	}

	entry := p.SaveArchivedFile("tenant-adeco", "batch_delete", "last_out.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 20)
	if _, err := p.DeleteArchivedFile(ctx, "tenant-adeco", entry.ID); err != nil {
		t.Fatal(err)
	}

	snap := bq.SellOutFactsSnapshot("tenant-adeco")
	if len(snap) != 1 || snap[0].IngestionBatchID != "batch_keep" {
		t.Fatalf("last-file delete must only remove its batch, got %+v", snap)
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

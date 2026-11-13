package ingestion

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// The Sell-Out files table showed rows_ingested in both "المعاملات" and "الوحدات المباعة":
// the archive list carried no units. total_units must come from stored own-brand quantity_sold.
func TestListArchivedFilesOverlaysSellOutUnitsDistinctFromRows(t *testing.T) {
	p := newTestProcessor(t, t.TempDir())
	entry := p.SaveArchivedFile("tenant-adeco", "batch_out", "out26.xlsx", []byte("x"), "fathalla", "2026", "01", 900, 3, 100, 0, 0, 1234)
	if entry.TotalUnits != 1234 {
		t.Fatalf("parse-time units not recorded: %v", entry.TotalUnits)
	}
	p.WithSink(&countingSink{counts: []bqsink.ArchiveRows{
		{Kind: bqsink.KindSellOut, ArchiveID: entry.ID, SourceFile: "out26.xlsx", Rows: 81294, Units: 1532854},
	}})
	list := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_out")
	if list.TotalCount != 1 {
		t.Fatalf("want 1 file, got %d", list.TotalCount)
	}
	f := list.Files[0]
	if f.RowsIngested != 81294 || f.TotalUnits != 1532854 {
		t.Fatalf("rows=%d units=%v", f.RowsIngested, f.TotalUnits)
	}
	b, _ := json.Marshal(f)
	if !strings.Contains(string(b), `"total_units":1532854`) {
		t.Fatalf("total_units missing from JSON: %s", b)
	}
	// Response-only overlay: the stored entry keeps its parse-time units.
	p.archiveMu.RLock()
	got := p.archivedFiles[entry.ID].TotalUnits
	p.archiveMu.RUnlock()
	if got != 1234 {
		t.Fatalf("archive entry units must not be rewritten on list, got %v", got)
	}
}

func TestListArchivedFilesOverlaysSellInCasesAndTons(t *testing.T) {
	p := newTestProcessor(t, t.TempDir())
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_x", "in26.xlsx", []byte("y"), "fathalla", "2026", "01", 40927, 2, 100)
	if entry.TotalCases != 0 {
		t.Fatalf("setup: %v", entry.TotalCases)
	}
	p.WithSink(&countingSink{counts: []bqsink.ArchiveRows{
		{Kind: bqsink.KindSellIn, ArchiveID: entry.ID, SourceFile: "in26.xlsx", Rows: 40927, Cases: 609430, Tons: 7313.156},
	}})
	f := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in").Files[0]
	if f.RowsIngested != 40927 || f.TotalCases != 609430 || f.TotalWeightTons != 7313.16 {
		t.Fatalf("rows=%d cases=%v tons=%v", f.RowsIngested, f.TotalCases, f.TotalWeightTons)
	}
	if f.TotalUnits != 0 {
		t.Fatalf("sell-in must not carry sell-out units: %v", f.TotalUnits)
	}
}

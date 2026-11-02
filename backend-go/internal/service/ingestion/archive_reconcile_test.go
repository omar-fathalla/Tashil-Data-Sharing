package ingestion

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

func TestPlanArchiveSync(t *testing.T) {
	live := []*ArchivedFile{
		{ID: "arch_a", FileName: "2025 out.xlsx", FileType: "sell_out", RowsIngested: 28015},
		{ID: "arch_sellin_b", BatchID: "batch_sellin_1", FileName: "in25.xlsx", FileType: "sell_in", RowsIngested: 62681},
		{ID: "arch_sellin_c", BatchID: "batch_sellin_2", FileName: "plan.xlsx", FileType: "sell_in", RowsIngested: 10},
	}
	stored := []bqsink.ArchiveRows{
		{Kind: bqsink.KindSellOut, ArchiveID: "", SourceFile: "2025 out.xlsx", Rows: 28015}, // legacy, no archive id
		{Kind: bqsink.KindSellOut, ArchiveID: "", SourceFile: "Book3.xlsx", Rows: 4090},    // deleted file
		{Kind: bqsink.KindSellIn, ArchiveID: "arch_sellin_c", SourceFile: "plan.xlsx", Rows: 10},
		{Kind: bqsink.KindSellIn, ArchiveID: "arch_gone", SourceFile: "old.xlsx", Rows: 5},
	}
	rep := PlanArchiveSync("tenant-adeco", live, stored)
	got := map[string]ArchiveSyncFile{}
	for _, f := range rep.Files {
		got[f.ArchiveID] = f
	}
	if f := got["arch_a"]; f.Action != "write" || f.LegacyBefore != 28015 || f.StoredBefore != 0 {
		t.Fatalf("legacy-only file must be rewritten with its archive id: %+v", f)
	}
	if f := got["arch_sellin_b"]; f.Action != "write" || f.StoredBefore != 0 {
		t.Fatalf("missing file must be written: %+v", f)
	}
	if f := got["arch_sellin_c"]; f.Action != "ok" || f.StoredBefore != 10 {
		t.Fatalf("stored file must be left alone: %+v", f)
	}
	if rep.OrphanRows["sell_out"] != 4090 || rep.OrphanRows["sell_in"] != 5 {
		t.Fatalf("orphans: %+v", rep.OrphanRows)
	}
}

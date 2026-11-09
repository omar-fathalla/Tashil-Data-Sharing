package gemini

import (
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestBuildBranchStoreMetadataEnglishAbbrevSameID(t *testing.T) {
	ar := BuildBranchStoreMetadata("fathalla", "سموحة")
	en := BuildBranchStoreMetadata("fathalla", "Smouha")
	abbr := BuildBranchStoreMetadata("fathalla", "فر. سموحة")
	if ar.ID != en.ID || ar.ID != abbr.ID {
		t.Fatalf("IDs diverge: ar=%s en=%s abbr=%s", ar.ID, en.ID, abbr.ID)
	}
	if !strings.HasPrefix(ar.ID, "fat_smouha") {
		t.Fatalf("want fat_smouha*, got %s", ar.ID)
	}
}

func TestBuildBranchStoreMetadataHanovilleAlias(t *testing.T) {
	a := BuildBranchStoreMetadata("fathalla", "نهال فيل")
	b := BuildBranchStoreMetadata("fathalla", "هانوفيل")
	c := BuildBranchStoreMetadata("fathalla", "Hanoville")
	if a.ID != b.ID || a.ID != c.ID {
		t.Fatalf("hanoville ids: %s %s %s", a.ID, b.ID, c.ID)
	}
	if a.ID != "fat_hanoville" {
		t.Fatalf("got %s", a.ID)
	}
}

func TestBuildBranchStoreMetadataOctoberAbbrev(t *testing.T) {
	a := BuildBranchStoreMetadata("fathalla", "أكتوبر")
	b := BuildBranchStoreMetadata("fathalla", "6 اكتوبر")
	c := BuildBranchStoreMetadata("fathalla", "Oct")
	if a.ID != b.ID || a.ID != c.ID {
		t.Fatalf("october ids: %s %s %s", a.ID, b.ID, c.ID)
	}
}

func TestAttachBranchNormSummaryArabic(t *testing.T) {
	p := &domain.NormalizedRetailIngestionPayload{
		NormalizedRecords: []domain.NormalizedRecord{
			{RawStoreName: "سموحة"},
			{RawStoreName: "Smouha"},
			{RawStoreName: "فر. سموحة"},
			{RawStoreName: "Unknown Z"},
		},
		DiscoveredBranches: []string{"Gardenia", "نهال فيل"},
	}
	attachBranchNormSummary(p)
	if p.BranchNorm == nil {
		t.Fatal("nil BranchNorm")
	}
	if p.BranchNorm.Total < 5 {
		t.Fatalf("total=%d", p.BranchNorm.Total)
	}
	if p.BranchNorm.English < 1 {
		t.Fatalf("counters: %+v", p.BranchNorm)
	}
	if p.BranchNorm.Abbrev < 1 && p.BranchNorm.Alias < 1 {
		t.Fatalf("expected abbrev or alias: %+v", p.BranchNorm)
	}
	if !strings.Contains(p.BranchNorm.SummaryAR, "توحيد الفروع") {
		t.Fatalf("summary: %s", p.BranchNorm.SummaryAR)
	}
	if len(p.BranchNorm.Samples) == 0 {
		t.Fatal("expected samples")
	}
}

func TestPrefixesStillFrozenWithEnglish(t *testing.T) {
	id := BuildBranchStoreMetadata("gomla", "Smouha").ID
	if !strings.HasPrefix(id, "gom_") {
		t.Fatalf("gomla prefix broken: %s", id)
	}
	id = BuildBranchStoreMetadata("carrefour", "Maadi").ID
	if !strings.HasPrefix(id, "crf_") {
		t.Fatalf("carrefour prefix broken: %s", id)
	}
}

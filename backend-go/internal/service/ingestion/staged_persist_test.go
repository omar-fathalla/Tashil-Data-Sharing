package ingestion

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

type domainSellOutFact = domain.SellOutFact

func file15(t *testing.T) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", "livetest", "15_sellout_form_vs_sheet.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func sellOutCtx(choice string) context.Context {
	ctx := WithUploadGuards(context.Background(), UploadGuards{PeriodChoice: choice})
	return gemini.WithRequestedPeriodDate(ctx, "2026-01-15")
}

func archivedNames(p *Processor) []string {
	var out []string
	for _, f := range p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "").Files {
		out = append(out, f.FileName+"|"+f.TargetYear+"-"+f.TargetMonth)
	}
	return out
}

// Dry-run on instance A, commit on instance B (same archive mount): succeeds with the sheet months,
// the preview is never archived, and the archive month follows the "sheet" choice ("08-09").
func TestStagedCommitAcrossInstancesSheetChoice(t *testing.T) {
	dir := t.TempDir()
	a := newTestProcessor(t, dir)
	res, err := a.ProcessUploadWithDryRun(sellOutCtx("sheet"), "tenant-adeco", "15_sellout_form_vs_sheet.xlsx", file15(t), true, "qa_test")
	if err != nil {
		t.Fatal(err)
	}
	if got := archivedNames(a); len(got) != 0 {
		t.Fatalf("dry-run must not archive: %v", got)
	}
	for _, st := range res.DiscoveredBranches {
		if strings.HasPrefix(st.ID, "gom_") || !strings.HasPrefix(st.ID, "qa") {
			t.Fatalf("qa_test branch id: %s", st.ID)
		}
	}

	b := newTestProcessor(t, dir)
	// The commit request carries only the form date (as the UI does); the choice comes from staging.
	commitCtx := gemini.WithRequestedPeriodDate(WithUploadGuards(context.Background(), UploadGuards{}), "2026-01-15")
	out, err := b.CommitStagedUpload(commitCtx, "tenant-adeco", res.BatchID, "")
	if err != nil {
		t.Fatalf("commit on B: %v", err)
	}
	if out.ValidRows != 2 {
		t.Fatalf("rows = %d, want 2", out.ValidRows)
	}
	if out.ArchivedFile == nil || out.ArchivedFile.TargetMonth != "08-09" || out.ArchivedFile.TargetYear != "2026" {
		t.Fatalf("archive month = %+v, want 2026 08-09", out.ArchivedFile)
	}
	facts := b.bqRepoFactsForTest(t, "tenant-adeco")
	months := map[string]bool{}
	for _, f := range facts {
		if f.RetailerChain != "qa_test" {
			continue
		}
		months[f.TransactionDate[:7]] = true
		if !strings.HasPrefix(f.StoreID, "qa") {
			t.Fatalf("qa_test StoreID prefix: %s", f.StoreID)
		}
	}
	if !months["2026-08"] || !months["2026-09"] || months["2026-01"] {
		t.Fatalf("fact months = %v, want 08 and 09 only", months)
	}
	if _, _, err := b.loadStaged("tenant-adeco", res.BatchID); err == nil {
		t.Fatalf("staging must be cleared after commit")
	}
}

func TestStagedExpiredReturns410(t *testing.T) {
	dir := t.TempDir()
	a := newTestProcessor(t, dir)
	res, err := a.ProcessUploadWithDryRun(sellOutCtx("sheet"), "tenant-adeco", "15_sellout_form_vs_sheet.xlsx", file15(t), true, "qa_test")
	if err != nil {
		t.Fatal(err)
	}
	old := StagedTTL
	StagedTTL = time.Nanosecond
	defer func() { StagedTTL = old }()
	time.Sleep(2 * time.Millisecond)
	b := newTestProcessor(t, dir)
	_, err = b.CommitStagedUpload(sellOutCtx(""), "tenant-adeco", res.BatchID, "")
	if st, _ := IsStagedUploadError(err); st != 410 {
		t.Fatalf("expired commit: status %d err %v", st, err)
	}
	if n := len(archivedNames(b)); n != 0 {
		t.Fatalf("expired commit archived %d files", n)
	}
	// TTL sweep removed the files.
	if a.sweepStaged(time.Now()) != 0 {
		t.Fatalf("expired entry still on disk")
	}
	if _, err := os.Stat(filepath.Join(dir, "_staged", "adeco", res.BatchID+".json")); !os.IsNotExist(err) {
		t.Fatalf("expired staged meta not removed: %v", err)
	}
}

func TestStagedWrongTenantAndChanged(t *testing.T) {
	dir := t.TempDir()
	a := newTestProcessor(t, dir)
	res, err := a.ProcessUploadWithDryRun(sellOutCtx("sheet"), "tenant-adeco", "15_sellout_form_vs_sheet.xlsx", file15(t), true, "qa_test")
	if err != nil {
		t.Fatal(err)
	}
	b := newTestProcessor(t, dir)
	before := len(b.bqRepoFactsForTest(t, "tenant-adeco"))
	if _, err := b.CommitStagedUpload(sellOutCtx(""), "tenant-other", res.BatchID, ""); err == nil {
		t.Fatalf("other tenant committed adeco's preview")
	}
	// In memory too: another tenant gets 404 and the preview survives for its owner.
	if _, err := a.CommitStagedUpload(sellOutCtx(""), "tenant-other", res.BatchID, ""); err == nil {
		t.Fatalf("other tenant committed from memory")
	}
	// Tamper with the staged preview (value differs) -> 409, nothing saved.
	metaPath, _, _ := b.stagedPaths("tenant-adeco", res.BatchID)
	data, _ := os.ReadFile(metaPath)
	data = []byte(strings.Replace(string(data), `"valid_rows":2`, `"valid_rows":3`, 1))
	if err := os.WriteFile(metaPath, data, 0o644); err != nil {
		t.Fatal(err)
	}
	_, err = b.CommitStagedUpload(sellOutCtx(""), "tenant-adeco", res.BatchID, "")
	if st, _ := IsStagedUploadError(err); st != 409 {
		t.Fatalf("changed preview: status %d err %v", st, err)
	}
	if n := len(archivedNames(b)); n != 0 {
		t.Fatalf("mismatch archived %d files", n)
	}
	if len(b.bqRepoFactsForTest(t, "tenant-adeco")) != before {
		t.Fatalf("mismatch saved facts")
	}
}

func TestDryRunDoesNotArchiveAndDiscardClearsStaging(t *testing.T) {
	dir := t.TempDir()
	a := newTestProcessor(t, dir)
	res, err := a.ProcessUploadWithDryRun(sellOutCtx("sheet"), "tenant-adeco", "15_sellout_form_vs_sheet.xlsx", file15(t), true, "qa_test")
	if err != nil {
		t.Fatal(err)
	}
	if res.ArchiveID != "" || len(archivedNames(a)) != 0 {
		t.Fatalf("dry-run archived: %q %v", res.ArchiveID, archivedNames(a))
	}
	if err := a.DiscardStagedUpload(context.Background(), "tenant-adeco", res.BatchID); err != nil {
		t.Fatal(err)
	}
	if _, _, err := a.loadStaged("tenant-adeco", res.BatchID); err == nil {
		t.Fatalf("discard left staging on disk")
	}
	if _, err := a.CommitStagedUpload(sellOutCtx(""), "tenant-adeco", res.BatchID, ""); err == nil {
		t.Fatalf("discarded preview committed")
	}
}

func (p *Processor) bqRepoFactsForTest(t *testing.T, tenant string) []domainSellOutFact {
	t.Helper()
	snap, ok := p.bqRepo.(interface {
		SellOutFactsSnapshot(string) []domainSellOutFact
	})
	if !ok {
		t.Fatal("bq repo has no SellOutFactsSnapshot")
	}
	return snap.SellOutFactsSnapshot(tenant)
}

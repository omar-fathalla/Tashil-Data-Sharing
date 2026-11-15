package ingestion

import (
	"context"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func TestApplyCustomerAliasAttributionsRemapsLiveFatAutoAndUndoRestores(t *testing.T) {
	ctx := context.Background()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	reg := customers.New(&customers.MemoryStore{})
	p.SetCustomerRegistry(reg)
	tenant := "tenant-adeco"

	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	alias := "عائله فتح الله ماركت مواد عناية - كفر الدوار2"
	// The no-«2» pair must stay untouched even when present in the same snapshot.
	otherA := "عائله فتح الله ماركت - كفر الدوار"
	otherB := "عائله فتح الله ماركت مواد عناية - كفر الدوار"

	canCode := gemini.BuildBranchStoreMetadata("fathalla", canonical).ID
	aliasCode := gemini.BuildBranchStoreMetadata("fathalla", alias).ID
	otherACode := gemini.BuildBranchStoreMetadata("fathalla", otherA).ID
	otherBCode := gemini.BuildBranchStoreMetadata("fathalla", otherB).ID
	if !strings.HasPrefix(aliasCode, "fat_auto_") || !strings.HasPrefix(canCode, "fat_auto_") {
		t.Fatalf("expected fat_auto codes, got alias=%s can=%s", aliasCode, canCode)
	}

	const srcN, tgtN = 75, 20 // srcN matches live Kafr source rows; tgt kept small for unit speed
	seed := make([]domain.SellInRecord, 0, srcN+tgtN+5)
	for i := 0; i < srcN; i++ {
		seed = append(seed, domain.SellInRecord{
			RecordID: "src-" + itoa(i), TenantID: tenant, RetailerChain: "fathalla",
			Year: 2026, MonthNum: 3, CustomerName: alias, CustomerBranchCode: aliasCode,
			ItemName: "صنف", NetValueEGP: 100, NetQtyCases: 1, SourceFilename: "in26.xlsx",
		})
	}
	for i := 0; i < tgtN; i++ {
		seed = append(seed, domain.SellInRecord{
			RecordID: "tgt-" + itoa(i), TenantID: tenant, RetailerChain: "fathalla",
			Year: 2026, MonthNum: 3, CustomerName: canonical, CustomerBranchCode: canCode,
			ItemName: "صنف", NetValueEGP: 10, NetQtyCases: 1, SourceFilename: "in26.xlsx",
		})
	}
	seed = append(seed,
		domain.SellInRecord{RecordID: "oA", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			CustomerName: otherA, CustomerBranchCode: otherACode, ItemName: "x", NetValueEGP: 1, NetQtyCases: 1},
		domain.SellInRecord{RecordID: "oB", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			CustomerName: otherB, CustomerBranchCode: otherBCode, ItemName: "x", NetValueEGP: 1, NetQtyCases: 1},
	)
	bq.ReplaceSellInRecords(tenant, seed)

	if _, err := reg.Decide(ctx, tenant, canonical, customers.StatusApproved, "fathalla", "", "admin"); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Decide(ctx, tenant, alias, customers.StatusApproved, "fathalla", canonical, "admin"); err != nil {
		t.Fatal(err)
	}

	ar := p.ApplyCustomerAliasAttributions(ctx, tenant)
	if ar.Remapped != srcN || len(ar.Errors) != 0 {
		t.Fatalf("apply: %+v", ar)
	}
	// Idempotent: second apply must not double-count.
	if second := p.ApplyCustomerAliasAttributions(ctx, tenant); second.Remapped != 0 {
		t.Fatalf("second apply remapped %d", second.Remapped)
	}

	byName := map[string]int{}
	byCode := map[string]int{}
	var total float64
	for _, r := range bq.SellInRecordsSnapshot(tenant) {
		byName[r.CustomerName]++
		byCode[r.CustomerBranchCode]++
		total += r.NetValueEGP
	}
	if byName[alias] != 0 {
		t.Fatalf("source name still present: %d", byName[alias])
	}
	if byName[canonical] != srcN+tgtN {
		t.Fatalf("canonical rows=%d want %d", byName[canonical], srcN+tgtN)
	}
	if byCode[aliasCode] != 0 || byCode[canCode] != srcN+tgtN {
		t.Fatalf("branch codes alias=%d can=%d", byCode[aliasCode], byCode[canCode])
	}
	if byName[otherA] != 1 || byName[otherB] != 1 || byCode[otherACode] != 1 || byCode[otherBCode] != 1 {
		t.Fatalf("no-2 pair must stay untouched: names=%v codes=%v", byName, byCode)
	}
	wantTotal := float64(srcN*100 + tgtN*10 + 2)
	if total != wantTotal {
		t.Fatalf("global total changed: %v want %v", total, wantTotal)
	}

	var meta customers.Entry
	for _, e := range reg.List(ctx, tenant, "", false) {
		if e.Key == customers.NormalizeName(alias) {
			meta = e
		}
	}
	if len(meta.MergedRecordIDs) != srcN || meta.MergedFromBranch != aliasCode {
		t.Fatalf("merge meta: ids=%d branch=%q", len(meta.MergedRecordIDs), meta.MergedFromBranch)
	}

	// Undo: clear alias_of then restore attribution.
	if _, err := reg.Decide(ctx, tenant, alias, customers.StatusApproved, "fathalla", "", "admin"); err != nil {
		t.Fatal(err)
	}
	rest := p.RestoreCustomerAliasAttribution(ctx, tenant, alias)
	if rest.Restored != srcN {
		t.Fatalf("restore: %+v", rest)
	}
	byName = map[string]int{}
	byCode = map[string]int{}
	for _, r := range bq.SellInRecordsSnapshot(tenant) {
		byName[r.CustomerName]++
		byCode[r.CustomerBranchCode]++
	}
	if byName[alias] != srcN || byName[canonical] != tgtN {
		t.Fatalf("after undo names alias=%d can=%d", byName[alias], byName[canonical])
	}
	if byCode[aliasCode] != srcN || byCode[canCode] != tgtN {
		t.Fatalf("after undo codes alias=%d can=%d", byCode[aliasCode], byCode[canCode])
	}
}

func TestApplyCustomerAliasAttributionsNeverWithoutDecision(t *testing.T) {
	ctx := context.Background()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	reg := customers.New(&customers.MemoryStore{})
	p.SetCustomerRegistry(reg)
	tenant := "tenant-adeco"
	alias := "عائله فتح الله ماركت مواد عناية - كفر الدوار2"
	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	bq.ReplaceSellInRecords(tenant, []domain.SellInRecord{{
		RecordID: "1", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 1,
		CustomerName: alias, CustomerBranchCode: "fat_auto_x", NetValueEGP: 1, NetQtyCases: 1,
	}})
	// Approve both without alias_of — must not merge.
	if _, err := reg.Decide(ctx, tenant, canonical, customers.StatusApproved, "fathalla", "", "a"); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Decide(ctx, tenant, alias, customers.StatusApproved, "fathalla", "", "a"); err != nil {
		t.Fatal(err)
	}
	if ar := p.ApplyCustomerAliasAttributions(ctx, tenant); ar.Remapped != 0 {
		t.Fatalf("no alias_of must not remap: %+v", ar)
	}
	if got := bq.SellInRecordsSnapshot(tenant)[0].CustomerName; got != alias {
		t.Fatalf("name changed without decision: %s", got)
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [16]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

func TestKafrFatAutoCodesMatchLiveBug(t *testing.T) {
	alias := "عائله فتح الله ماركت مواد عناية - كفر الدوار2"
	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	otherA := "عائله فتح الله ماركت - كفر الدوار"
	otherB := "عائله فتح الله ماركت مواد عناية - كفر الدوار"
	if got := gemini.BuildBranchStoreMetadata("fathalla", alias).ID; got != "fat_auto_9d2597c8" {
		t.Fatalf("alias code %s", got)
	}
	if got := gemini.BuildBranchStoreMetadata("fathalla", canonical).ID; got != "fat_auto_71df0c37" {
		t.Fatalf("canonical code %s", got)
	}
	// Document the no-2 pair codes so we never confuse them with the merge pair.
	t.Logf("no-2 pair: %s=%s %s=%s", otherA, gemini.BuildBranchStoreMetadata("fathalla", otherA).ID,
		otherB, gemini.BuildBranchStoreMetadata("fathalla", otherB).ID)
}

// Live failure regression: BQ/UI may show «كفر الدوار 2» (spaced) while the registry decision
// recorded the in26 spelling «كفر الدوار2» (glued). NormalizeName + branch-code match must remap.
func TestApplyCustomerAliasAttributionsMatchesSpacedDigitVariant(t *testing.T) {
	ctx := context.Background()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	reg := customers.New(&customers.MemoryStore{})
	p.SetCustomerRegistry(reg)
	tenant := "tenant-adeco"

	canonical := "عائله فتح الله ماركت - كفر الدوار 2"
	aliasDecision := "عائله فتح الله ماركت مواد عناية - كفر الدوار2" // registry / in26 (glued)
	aliasLive := "عائله فتح الله ماركت مواد عناية - كفر الدوار 2"    // spaced digit in live rows
	canCode := gemini.BuildBranchStoreMetadata("fathalla", canonical).ID
	aliasCode := gemini.BuildBranchStoreMetadata("fathalla", aliasDecision).ID

	bq.ReplaceSellInRecords(tenant, []domain.SellInRecord{
		{RecordID: "live-1", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			CustomerName: aliasLive, CustomerBranchCode: aliasCode, ItemName: "صنف", NetValueEGP: 50, NetQtyCases: 1},
		{RecordID: "can-1", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			CustomerName: canonical, CustomerBranchCode: canCode, ItemName: "صنف", NetValueEGP: 10, NetQtyCases: 1},
	})
	if _, err := reg.Decide(ctx, tenant, canonical, customers.StatusApproved, "fathalla", "", "admin"); err != nil {
		t.Fatal(err)
	}
	if _, err := reg.Decide(ctx, tenant, aliasDecision, customers.StatusApproved, "fathalla", canonical, "admin"); err != nil {
		t.Fatal(err)
	}

	ar := p.ApplyCustomerAliasAttributions(ctx, tenant)
	if ar.Decisions != 1 || ar.Remapped != 1 || len(ar.Errors) != 0 {
		t.Fatalf("apply spaced variant: %+v", ar)
	}
	byName := map[string]int{}
	byCode := map[string]int{}
	for _, r := range bq.SellInRecordsSnapshot(tenant) {
		byName[r.CustomerName]++
		byCode[r.CustomerBranchCode]++
	}
	if byName[aliasLive] != 0 || byName[aliasDecision] != 0 {
		t.Fatalf("source spellings still present: %v", byName)
	}
	if byName[canonical] != 2 || byCode[canCode] != 2 || byCode[aliasCode] != 0 {
		t.Fatalf("after remap names=%v codes=%v", byName, byCode)
	}

	// Simulate OnRebuilt durable sync restoring pre-merge BQ rows, then re-apply.
	bq.ReplaceSellInRecords(tenant, []domain.SellInRecord{
		{RecordID: "live-1", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			CustomerName: aliasLive, CustomerBranchCode: aliasCode, ItemName: "صنف", NetValueEGP: 50, NetQtyCases: 1},
		{RecordID: "can-1", TenantID: tenant, RetailerChain: "fathalla", Year: 2026, MonthNum: 3,
			CustomerName: canonical, CustomerBranchCode: canCode, ItemName: "صنف", NetValueEGP: 10, NetQtyCases: 1},
	})
	ar2 := p.ApplyCustomerAliasAttributions(ctx, tenant)
	if ar2.Remapped != 1 {
		t.Fatalf("re-apply after durable wipe remapped=%d want 1", ar2.Remapped)
	}
}

func TestNormalizeNameUnifiesGluedBranchDigits(t *testing.T) {
	a := customers.NormalizeName("عائله فتح الله ماركت مواد عناية - كفر الدوار2")
	b := customers.NormalizeName("عائله فتح الله ماركت مواد عناية - كفر الدوار 2")
	if a != b {
		t.Fatalf("glued/spaced digits must share key:\n%q\n%q", a, b)
	}
	// Numbered branch stays distinct from the unnumbered sibling.
	if customers.NormalizeName("عائله فتح الله ماركت - كفر الدوار") == customers.NormalizeName("عائله فتح الله ماركت - كفر الدوار 2") {
		t.Fatal("كفر الدوار vs كفر الدوار 2 must stay distinct")
	}
}

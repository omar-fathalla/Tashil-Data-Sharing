package gemini

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

const testTenantA = "tenant-adeco"
const testTenantB = "tenant-other"

func withTenant(ctx context.Context, tenant string) context.Context {
	return WithMappingPlanTenant(ctx, tenant)
}

// Re-reading the same archived file (another instance, or after a restart with a shared plan dir) must reuse
// the stored mapping plan instead of calling Gemini again, and produce the same totals.
func TestMappingPlanReusedAcrossReadsAndInstances(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	ctx := withTenant(context.Background(), testTenantA)
	first, err := c.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	second, err := c.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 {
		t.Fatalf("second read must not call Gemini, calls=%v", calls)
	}
	if first.Validation.ExtractedValue != second.Validation.ExtractedValue || second.MappingSource != MappingSourceCache {
		t.Fatalf("cached plan changed the result: source=%s %+v vs %+v", second.MappingSource, first.Validation, second.Validation)
	}
	if first.MappingSource != MappingSourceAI {
		t.Fatalf("first read should be ai, got %s", first.MappingSource)
	}

	// A fresh client (another instance) sharing the plan directory also skips Gemini.
	var calls2 []string
	other := stubClient(map[string]string{}, &calls2).WithMappingPlanDir(dir)
	p, err := other.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls2) != 0 || p.Validation.ExtractedValue != first.Validation.ExtractedValue {
		t.Fatalf("shared plan not reused: calls=%v validation=%+v", calls2, p.Validation)
	}
}

func TestMappingPlanCacheKeyedByContent(t *testing.T) {
	if mappingPlanKey("a") == mappingPlanKey("b") || mappingPlanKey("a") != mappingPlanKey("a") {
		t.Fatal("key must be a stable content hash")
	}
}

func TestMappingPlanCacheWritesVersionedEnvelope(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	if _, err := c.AnalyzeAndNormalize(withTenant(context.Background(), testTenantA), "Book3.xlsx", x); err != nil {
		t.Fatal(err)
	}
	tenantDir := filepath.Join(dir, sanitizeTenantSegment(testTenantA))
	entries, err := os.ReadDir(tenantDir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one cache file under tenant dir, got %v err=%v", entries, err)
	}
	raw, err := os.ReadFile(filepath.Join(tenantDir, entries[0].Name()))
	if err != nil {
		t.Fatal(err)
	}
	var env cachedMappingPlan
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatal(err)
	}
	if env.Version != mappingPlanCacheVersion || env.Source != planCacheSourceAI || env.Plan.Layout != "wide" {
		t.Fatalf("unexpected envelope: %+v", env)
	}
	if !strings.Contains(string(raw), `"v":`) {
		t.Fatal("cache file must include version field")
	}
}

func book3MappingCacheKey(t *testing.T, filename string, rows [][]string) string {
	t.Helper()
	sample := rows
	if len(sample) > mappingSampleRows {
		sample = sample[:mappingSampleRows]
	}
	sample = guardrails.SanitizeSampleRows(sample)
	prompt := buildColumnMapPrompt(guardrails.FilenameForLog(filename), sample)
	return mappingPlanKey(prompt)
}

func TestLearnFromCorrectionOverwritesAIAndSkipsGemini(t *testing.T) {
	rows := book3LikeRows()
	x, _ := BuildSampleXLSX(rows)
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	ctx := withTenant(context.Background(), testTenantA)

	first, err := c.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if first.MappingSource != MappingSourceAI || len(calls) != 1 {
		t.Fatalf("setup: source=%s calls=%v", first.MappingSource, calls)
	}

	var corrected ColumnMapPlan
	if err := json.Unmarshal([]byte(book3Plan), &corrected); err != nil {
		t.Fatal(err)
	}
	for i := range corrected.Columns {
		if corrected.Columns[i].Branch == "سموحة" {
			corrected.Columns[i].Branch = "سموحة-corrected"
		}
	}
	corrected.Confidence = 0.8

	sample := rows
	if len(sample) > mappingSampleRows {
		sample = sample[:mappingSampleRows]
	}
	if err := c.RememberCorrectedPlan(testTenantA, "Book3.xlsx", sample, &corrected); err != nil {
		t.Fatal(err)
	}

	tenantDir := filepath.Join(dir, sanitizeTenantSegment(testTenantA))
	entries, err := os.ReadDir(tenantDir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one cache file after correction, got %v err=%v", entries, err)
	}
	raw, _ := os.ReadFile(filepath.Join(tenantDir, entries[0].Name()))
	var env cachedMappingPlan
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatal(err)
	}
	if env.Version != mappingPlanCacheVersion || env.Source != planCacheSourceCorrection || env.LearnedAt == "" {
		t.Fatalf("correction envelope: %+v", env)
	}
	if env.Plan.Confidence != 1 {
		t.Fatalf("learned confidence want 1, got %v", env.Plan.Confidence)
	}
	found := false
	for _, col := range env.Plan.Columns {
		if col.Branch == "سموحة-corrected" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("corrected branch not stored: %+v", env.Plan.Columns)
	}

	second, err := c.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 {
		t.Fatalf("correction cache hit must not call Gemini, calls=%v", calls)
	}
	if second.MappingSource != MappingSourceCache {
		t.Fatalf("expected cache after correction, got %s", second.MappingSource)
	}

	var calls2 []string
	other := stubClient(map[string]string{}, &calls2).WithMappingPlanDir(dir)
	third, err := other.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls2) != 0 || third.MappingSource != MappingSourceCache {
		t.Fatalf("peer must reuse correction: calls=%v source=%s", calls2, third.MappingSource)
	}
}

func TestMappingPlanCacheTenantIsolation(t *testing.T) {
	rows := book3LikeRows()
	x, _ := BuildSampleXLSX(rows)
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)

	ctxA := withTenant(context.Background(), testTenantA)
	if _, err := c.AnalyzeAndNormalize(ctxA, "Book3.xlsx", x); err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 {
		t.Fatalf("tenant A first read calls=%v", calls)
	}

	var corrected ColumnMapPlan
	_ = json.Unmarshal([]byte(book3Plan), &corrected)
	for i := range corrected.Columns {
		if corrected.Columns[i].Branch == "سموحة" {
			corrected.Columns[i].Branch = "tenant-a-only"
		}
	}
	sample := rows
	if len(sample) > mappingSampleRows {
		sample = sample[:mappingSampleRows]
	}
	if err := c.LearnFromCorrection(testTenantA, "Book3.xlsx", sample, &corrected); err != nil {
		t.Fatal(err)
	}

	// Tenant B must not see A's correction — Gemini is called again.
	ctxB := withTenant(context.Background(), testTenantB)
	pB, err := c.AnalyzeAndNormalize(ctxB, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 2 || pB.MappingSource != MappingSourceAI {
		t.Fatalf("tenant B must miss A's cache: calls=%v source=%s", calls, pB.MappingSource)
	}

	// Tenant A still hits correction cache.
	pA, err := c.AnalyzeAndNormalize(ctxA, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 2 || pA.MappingSource != MappingSourceCache {
		t.Fatalf("tenant A should stay on correction cache: calls=%v source=%s", calls, pA.MappingSource)
	}
}

func TestCorrectionThenReuploadReusesMapping(t *testing.T) {
	rows := book3LikeRows()
	x, _ := BuildSampleXLSX(rows)
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	ctx := withTenant(context.Background(), testTenantA)

	if _, err := c.AnalyzeAndNormalize(ctx, "Book3.xlsx", x); err != nil {
		t.Fatal(err)
	}

	var corrected ColumnMapPlan
	_ = json.Unmarshal([]byte(book3Plan), &corrected)
	for i := range corrected.Columns {
		if corrected.Columns[i].Role == "product_name" {
			corrected.Columns[i].Role = "ignore"
		}
	}
	// Keep barcode so plan.check still passes; product_name may be absent if barcode present.
	sample, ok := MappingSampleFromFile(x)
	if !ok {
		t.Fatal("sample from xlsx")
	}
	if err := c.RememberCorrectedPlan(testTenantA, "Book3.xlsx", sample, &corrected); err != nil {
		t.Fatal(err)
	}
	afterCorrect := len(calls)

	// Re-upload same bytes: must reuse correction, no new Gemini call.
	re, err := c.AnalyzeAndNormalize(ctx, "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != afterCorrect {
		t.Fatalf("re-upload must not call Gemini, calls before=%d after=%d", afterCorrect, len(calls))
	}
	if re.MappingSource != MappingSourceCache {
		t.Fatalf("re-upload source=%s", re.MappingSource)
	}
	plan, source, ok := c.LookupCachedMappingPlan(testTenantA, "Book3.xlsx", sample)
	if !ok || source != planCacheSourceCorrection {
		t.Fatalf("lookup: ok=%v source=%s", ok, source)
	}
	hasIgnoreProduct := false
	for _, col := range plan.Columns {
		if col.Index == 3 && col.Role == "ignore" {
			hasIgnoreProduct = true
		}
	}
	if !hasIgnoreProduct {
		t.Fatalf("corrected plan not what re-upload would use: %+v", plan.Columns)
	}
}

func TestMappingPlanCacheReadsLegacyBarePlan(t *testing.T) {
	rows := book3LikeRows()
	x, _ := BuildSampleXLSX(rows)
	dir := t.TempDir()
	key := book3MappingCacheKey(t, "Book3.xlsx", rows)
	tenantDir := filepath.Join(dir, sanitizeTenantSegment(testTenantA))
	if err := os.MkdirAll(tenantDir, 0o755); err != nil {
		t.Fatal(err)
	}

	var plan ColumnMapPlan
	if err := json.Unmarshal([]byte(book3Plan), &plan); err != nil {
		t.Fatal(err)
	}
	bare, err := json.Marshal(&plan)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tenantDir, key+".json"), bare, 0o644); err != nil {
		t.Fatal(err)
	}

	var calls []string
	c := stubClient(map[string]string{}, &calls).WithMappingPlanDir(dir)
	p, err := c.AnalyzeAndNormalize(withTenant(context.Background(), testTenantA), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 0 || p.MappingSource != MappingSourceCache {
		t.Fatalf("legacy bare plan must be reused: calls=%v source=%s", calls, p.MappingSource)
	}
}

func TestMappingPlanCacheIgnoresUnsupportedVersion(t *testing.T) {
	rows := book3LikeRows()
	x, _ := BuildSampleXLSX(rows)
	dir := t.TempDir()
	key := book3MappingCacheKey(t, "Book3.xlsx", rows)
	tenantDir := filepath.Join(dir, sanitizeTenantSegment(testTenantA))
	if err := os.MkdirAll(tenantDir, 0o755); err != nil {
		t.Fatal(err)
	}

	var plan ColumnMapPlan
	if err := json.Unmarshal([]byte(book3Plan), &plan); err != nil {
		t.Fatal(err)
	}
	env := cachedMappingPlan{Version: mappingPlanCacheVersion + 99, Source: planCacheSourceAI, Plan: plan}
	raw, err := json.Marshal(env)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tenantDir, key+".json"), raw, 0o644); err != nil {
		t.Fatal(err)
	}

	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	p, err := c.AnalyzeAndNormalize(withTenant(context.Background(), testTenantA), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 || p.MappingSource != MappingSourceAI {
		t.Fatalf("unsupported version must miss cache: calls=%v source=%s", calls, p.MappingSource)
	}
	updated, err := os.ReadFile(filepath.Join(tenantDir, key+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var stored cachedMappingPlan
	if err := json.Unmarshal(updated, &stored); err != nil {
		t.Fatal(err)
	}
	if stored.Version != mappingPlanCacheVersion {
		t.Fatalf("rewritten version=%d", stored.Version)
	}
}

func TestLearnFromCorrectionRejectsInvalidPlan(t *testing.T) {
	var calls []string
	c := stubClient(map[string]string{}, &calls).WithMappingPlanDir(t.TempDir())
	err := c.LearnFromCorrection(testTenantA, "x.xlsx", book3LikeRows(), &ColumnMapPlan{
		HeaderRowIndex: 0,
		Layout:         "wide",
		Confidence:     0.9,
		Columns:        nil,
	})
	if err == nil {
		t.Fatal("expected schema rejection")
	}
}

func TestLearnFromCorrectionRequiresTenant(t *testing.T) {
	var calls []string
	c := stubClient(map[string]string{}, &calls).WithMappingPlanDir(t.TempDir())
	var plan ColumnMapPlan
	_ = json.Unmarshal([]byte(book3Plan), &plan)
	if err := c.LearnFromCorrection("", "Book3.xlsx", book3LikeRows(), &plan); err == nil {
		t.Fatal("empty tenant must be rejected")
	}
}

func TestLearnFromCorrectionDiskWriteFailure(t *testing.T) {
	dir := t.TempDir()
	// Block the tenant subdirectory with a regular file so MkdirAll/WriteFile fails.
	blocker := filepath.Join(dir, sanitizeTenantSegment(testTenantA))
	if err := os.WriteFile(blocker, []byte("not-a-directory"), 0o644); err != nil {
		t.Fatal(err)
	}
	var calls []string
	c := stubClient(map[string]string{}, &calls).WithMappingPlanDir(dir)
	var plan ColumnMapPlan
	if err := json.Unmarshal([]byte(book3Plan), &plan); err != nil {
		t.Fatal(err)
	}
	err := c.LearnFromCorrection(testTenantA, "Book3.xlsx", book3LikeRows(), &plan)
	if err == nil {
		t.Fatal("disk write failure must not return success")
	}
	if !strings.Contains(err.Error(), "فشل حفظ تصحيح الربط") {
		t.Fatalf("expected clear Arabic failure, got %v", err)
	}
	// Must not leave a successful cache entry for this tenant key.
	if _, _, ok := c.LookupCachedMappingPlan(testTenantA, "Book3.xlsx", book3LikeRows()); ok {
		t.Fatal("failed write must not populate cache")
	}
}

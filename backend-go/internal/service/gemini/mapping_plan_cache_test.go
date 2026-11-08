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

// Re-reading the same archived file (another instance, or after a restart with a shared plan dir) must reuse
// the stored mapping plan instead of calling Gemini again, and produce the same totals.
func TestMappingPlanReusedAcrossReadsAndInstances(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	first, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	second, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
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
	p, err := other.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
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
	if _, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one cache file, got %v err=%v", entries, err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, entries[0].Name()))
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

	first, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
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
	if err := c.RememberCorrectedPlan("Book3.xlsx", sample, &corrected); err != nil {
		t.Fatal(err)
	}

	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one cache file after correction, got %v err=%v", entries, err)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, entries[0].Name()))
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

	second, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
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
	third, err := other.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls2) != 0 || third.MappingSource != MappingSourceCache {
		t.Fatalf("peer must reuse correction: calls=%v source=%s", calls2, third.MappingSource)
	}
}

func TestMappingPlanCacheReadsLegacyBarePlan(t *testing.T) {
	rows := book3LikeRows()
	x, _ := BuildSampleXLSX(rows)
	dir := t.TempDir()
	key := book3MappingCacheKey(t, "Book3.xlsx", rows)

	var plan ColumnMapPlan
	if err := json.Unmarshal([]byte(book3Plan), &plan); err != nil {
		t.Fatal(err)
	}
	bare, err := json.Marshal(&plan)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, key+".json"), bare, 0o644); err != nil {
		t.Fatal(err)
	}

	var calls []string
	c := stubClient(map[string]string{}, &calls).WithMappingPlanDir(dir)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
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

	var plan ColumnMapPlan
	if err := json.Unmarshal([]byte(book3Plan), &plan); err != nil {
		t.Fatal(err)
	}
	env := cachedMappingPlan{Version: mappingPlanCacheVersion + 99, Source: planCacheSourceAI, Plan: plan}
	raw, err := json.Marshal(env)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, key+".json"), raw, 0o644); err != nil {
		t.Fatal(err)
	}

	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 || p.MappingSource != MappingSourceAI {
		t.Fatalf("unsupported version must miss cache: calls=%v source=%s", calls, p.MappingSource)
	}
	updated, err := os.ReadFile(filepath.Join(dir, key+".json"))
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
	err := c.LearnFromCorrection("x.xlsx", book3LikeRows(), &ColumnMapPlan{
		HeaderRowIndex: 0,
		Layout:         "wide",
		Confidence:     0.9,
		Columns:        nil,
	})
	if err == nil {
		t.Fatal("expected schema rejection")
	}
}

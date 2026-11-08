package gemini

import (
	"bytes"
	"context"
	"log"
	"strings"
	"testing"
	"time"
)

func TestTelemetry_AISuccessRecordsSanitizeAndSchema(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	tel := p.GuardrailTelemetry
	if tel == nil {
		t.Fatal("expected guardrail telemetry")
	}
	if !tel.SampleSanitized || !tel.SchemaChecked || !tel.SchemaValid {
		t.Fatalf("AI path must record sanitize+schema: %+v", tel)
	}
	// Stub mapper bypasses HTTP — GeminiCallLogged stays false until logAICall runs.
	if tel.GeminiCallLogged {
		t.Fatalf("stub mapper must not invent HTTP call telemetry: %+v", tel)
	}
	if p.MappingSource != MappingSourceAI {
		t.Fatalf("source=%s", p.MappingSource)
	}
}

func TestTelemetry_CacheHitHasSchemaButNoCall(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	first, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if first.MappingSource != MappingSourceAI {
		t.Fatalf("first=%s", first.MappingSource)
	}
	second, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if second.MappingSource != MappingSourceCache {
		t.Fatalf("second=%s", second.MappingSource)
	}
	tel := second.GuardrailTelemetry
	if tel == nil || !tel.SampleSanitized || !tel.SchemaChecked || !tel.SchemaValid {
		t.Fatalf("cache must re-check schema + sanitize: %+v", tel)
	}
	if tel.GeminiCallLogged || tel.GeminiCallCount != 0 {
		t.Fatalf("cache hit must not log a Gemini call: %+v", tel)
	}
}

func TestTelemetry_SchemaFailureThenDeterministicFallbackKeepsFailure(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	var calls []string
	// Fails ValidateColumnMapPlanJSON (unknown role + confidence out of range).
	bad := `{"header_row_index":2,"layout":"wide","confidence":1.5,"columns":[{"index":0,"role":"not_a_role"}]}`
	c := stubClient(map[string]string{"tier1-model": bad, "tier2-model": bad}, &calls)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("expected deterministic fallback, got %s", p.MappingSource)
	}
	tel := p.GuardrailTelemetry
	if tel == nil || !tel.SampleSanitized || !tel.SchemaChecked || tel.SchemaValid {
		t.Fatalf("fallback must keep schema failure telemetry: %+v", tel)
	}
	if tel.GeminiCallLogged {
		t.Fatalf("stub mapper must not invent call telemetry: %+v", tel)
	}
}

func TestTelemetry_HTTPCallIncrementsCounters(t *testing.T) {
	f := &geminiHTTPFixture{}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	tel := p.GuardrailTelemetry
	if tel == nil || !tel.GeminiCallLogged || tel.GeminiCallCount < 1 || tel.GeminiLatencyMS < 0 {
		t.Fatalf("HTTP mapping must record call counters: %+v", tel)
	}
	if !tel.SampleSanitized || !tel.SchemaValid {
		t.Fatalf("HTTP AI path telemetry: %+v", tel)
	}
}

func TestSecondaryLogs_RedactPIIFromPlanAndErrors(t *testing.T) {
	var buf bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&buf)
	defer log.SetOutput(prev)

	x, _ := BuildSampleXLSX(book3LikeRows())
	// Model echoes email/phone into a branch field — must never appear in logs.
	leaky := `{"header_row_index":2,"skip_rows":[0,1],"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"category"},{"index":1,"role":"supplier"},{"index":2,"role":"barcode"},{"index":3,"role":"product_name"},
{"index":4,"role":"store_value","branch":"ops@tashil.example"},{"index":5,"role":"store_value","branch":"01012345678"},
{"index":6,"role":"total_value"},{"index":7,"role":"month"},
{"index":8,"role":"store_quantity","branch":"ops@tashil.example"},{"index":9,"role":"store_quantity","branch":"01012345678"},
{"index":10,"role":"total_quantity"},{"index":11,"role":"year"}]}`
	var calls []string
	c := stubClient(map[string]string{"tier1-model": leaky}, &calls)
	if _, err := c.AnalyzeAndNormalize(context.Background(), "/secret/path/Book3.xlsx", x); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if strings.Contains(out, "ops@tashil.example") || strings.Contains(out, "01012345678") {
		t.Fatalf("secondary logs leaked PII:\n%s", out)
	}
	if strings.Contains(out, "/secret/path/") {
		t.Fatalf("secondary logs leaked raw path:\n%s", out)
	}
	if !strings.Contains(out, "layout=wide") {
		t.Fatalf("expected allowlisted plan summary, got:\n%s", out)
	}
}

func TestSecondaryLogs_RedactPIIFromMapperErrors(t *testing.T) {
	var buf bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&buf)
	defer log.SetOutput(prev)

	x, _ := BuildSampleXLSX(book3LikeRows())
	c := NewAgent("test-key", "tier1-model", false).WithTier2Model("tier2-model")
	c.mapper = func(_ context.Context, model, prompt string) (string, error) {
		return "", &piiErr{msg: "upstream rejected user ops@tashil.example phone=01012345678"}
	}
	_, _ = c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	out := buf.String()
	if strings.Contains(out, "ops@tashil.example") || strings.Contains(out, "01012345678") {
		t.Fatalf("error logs leaked PII:\n%s", out)
	}
	if !strings.Contains(out, "[redacted-email]") && !strings.Contains(out, "[redacted-phone]") {
		t.Fatalf("expected redaction markers in logs:\n%s", out)
	}
}

type piiErr struct{ msg string }

func (e *piiErr) Error() string { return e.msg }

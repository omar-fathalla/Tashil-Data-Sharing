package guardrails

import (
	"strings"
	"testing"
	"time"
)

func TestRedactString(t *testing.T) {
	in := "fail key=AIzaSyA-test-key-abcdefghijklmnop user=ops@tashil.example phone=01012345678"
	out := RedactString(in)
	if strings.Contains(out, "AIza") || strings.Contains(out, "@") || strings.Contains(out, "01012345678") {
		t.Fatalf("PII leaked: %s", out)
	}
	if !strings.Contains(out, "[redacted-key]") || !strings.Contains(out, "[redacted-email]") {
		t.Fatalf("expected redaction markers: %s", out)
	}
}

func TestSanitizeSampleRows(t *testing.T) {
	rows := make([][]string, 20)
	for i := range rows {
		rows[i] = []string{strings.Repeat("س", 80), "short"}
	}
	got := SanitizeSampleRows(rows)
	if len(got) != MaxSampleRows {
		t.Fatalf("rows=%d", len(got))
	}
	if len([]rune(got[0][0])) != MaxCellRunes {
		t.Fatalf("cell runes=%d", len([]rune(got[0][0])))
	}
}

func TestRefuseMockInProduction(t *testing.T) {
	t.Setenv("ENVIRONMENT", "development")
	if err := RefuseMockInProduction(); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENVIRONMENT", "production")
	if err := RefuseMockInProduction(); err == nil {
		t.Fatal("expected production refusal")
	}
	if err := AssertNoMockMappingSource("mock"); err == nil {
		t.Fatal("expected mock source refusal")
	}
	if err := AssertNoMockMappingSource("ai"); err != nil {
		t.Fatal(err)
	}
}

func TestFormatCallLine_NoRawPathOrPII(t *testing.T) {
	line := FormatCallLine(CallRecord{
		Filename:  "/tmp/path/Book3.xlsx",
		Model:     "gemini-3.8-flash",
		Tier:      "tier1",
		LatencyMS: 12,
		OK:        false,
		Err:       "status 401 key=AIzaSyA-test-key-abcdefghijklmnop",
	})
	if strings.Contains(line, "/tmp") || strings.Contains(line, "AIza") {
		t.Fatalf("leaked path or key: %s", line)
	}
	if !strings.Contains(line, "[ingest-ai-call]") || !strings.Contains(line, "Book3.xlsx") {
		t.Fatalf("line=%s", line)
	}
	LogCallTimed("x.xlsx", "m", "tier1", time.Now().Add(-time.Millisecond), true, nil)
}

func TestBuildSuccessMetrics_FromObservedEvents(t *testing.T) {
	d := EvaluateApproval(Input{IsStaged: true, MappingSource: "ai", MappingConfidence: 0.9})

	var ai Events
	ai.MarkSampleSanitized()
	ai.MarkSchemaResult(true)
	ai.MarkGeminiCall(42)
	mAI := BuildSuccessMetrics(ai, "ai", 0.9, d)
	if !mAI.SchemaValid || !mAI.SchemaChecked || !mAI.PerCallLogged || !mAI.PIIMinimized || mAI.GeminiLatencyMS != 42 {
		t.Fatalf("ai events: %+v", mAI)
	}
	if mAI.MockBlockedInProd {
		t.Fatal("mock blocked must not be inferred from ENVIRONMENT alone")
	}

	var cache Events
	cache.MarkSampleSanitized()
	cache.MarkSchemaResult(true)
	// no MarkGeminiCall — cache hit
	mCache := BuildSuccessMetrics(cache, "cache", 0.9, d)
	if !mCache.SchemaValid || mCache.PerCallLogged || mCache.GeminiCallCount != 0 {
		t.Fatalf("cache hit must not count as a Gemini call: %+v", mCache)
	}

	var det Events
	mDet := BuildSuccessMetrics(det, "deterministic", 0, d)
	if mDet.SchemaValid || mDet.PerCallLogged || mDet.PIIMinimized || mDet.MockBlockedInProd {
		t.Fatalf("empty events must stay false: %+v", mDet)
	}

	var refused Events
	refused.MarkMockRefused()
	mRef := BuildSuccessMetrics(refused, "mock", 0, d)
	if !mRef.MockBlockedInProd {
		t.Fatal("MockBlockedInProd only when mock refusal ran")
	}
}

func TestSummarizeColumnMapJSON_NoBranchPII(t *testing.T) {
	raw := []byte(`{"header_row_index":2,"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"barcode"},
{"index":1,"role":"store_value","branch":"ops@tashil.example / 01012345678"}]}`)
	sum := SummarizeColumnMapJSON(raw)
	if strings.Contains(sum, "@") || strings.Contains(sum, "01012345678") || strings.Contains(sum, "branch") {
		t.Fatalf("summary leaked PII: %s", sum)
	}
	if !strings.Contains(sum, "layout=wide") || !strings.Contains(sum, "store_value") {
		t.Fatalf("summary=%s", sum)
	}
}

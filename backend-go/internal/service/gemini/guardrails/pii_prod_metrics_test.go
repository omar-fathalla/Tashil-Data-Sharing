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

func TestBuildSuccessMetrics_FromEvents(t *testing.T) {
	t.Setenv("ENVIRONMENT", "production")
	d := EvaluateApproval(Input{IsStaged: true, MappingSource: "ai", MappingConfidence: 0.9})

	ai := BuildSuccessMetrics(EventsFromMappingSource("ai"), "ai", 0.9, d)
	if !ai.SchemaValid || !ai.SchemaChecked || !ai.PerCallLogged || !ai.PIIMinimized {
		t.Fatalf("ai events: %+v", ai)
	}

	cache := BuildSuccessMetrics(EventsFromMappingSource("cache"), "cache", 0.9, d)
	if !cache.SchemaValid || cache.PerCallLogged {
		t.Fatalf("cache hit must not count as a Gemini call: %+v", cache)
	}

	det := BuildSuccessMetrics(EventsFromMappingSource("deterministic"), "deterministic", 0, d)
	if det.SchemaValid || det.PerCallLogged || det.PIIMinimized {
		t.Fatalf("deterministic must not hardcode schema/call/pii true: %+v", det)
	}
}

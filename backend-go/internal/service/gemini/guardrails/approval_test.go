package guardrails

import (
	"errors"
	"strings"
	"testing"
)

func TestEvaluateApproval_StagedAI(t *testing.T) {
	d := EvaluateApproval(Input{
		MappingSource:     "ai",
		MappingConfidence: 0.8,
		IsStaged:          true,
		ValidationStatus:  "ok",
		AnomalyCount:      1,
	})
	if !d.RequiresHumanApproval {
		t.Fatal("expected human approval")
	}
	if len(d.ArabicReasons) == 0 {
		t.Fatal("expected Arabic reasons")
	}
	joined := strings.Join(d.Reasons, ",")
	for _, need := range []string{"staged_preview", "ai_mapping", "ai_confidence_borderline", "anomalies_present"} {
		if !strings.Contains(joined, need) {
			t.Fatalf("missing reason %s in %v", need, d.Reasons)
		}
	}
}

func TestEvaluateApproval_CommittedStillRecordsReasons(t *testing.T) {
	d := EvaluateApproval(Input{
		IsCommitted:   true,
		HumanApproved: true,
		MappingSource: "ai",
		AnomalyCount:  2,
	})
	if d.RequiresHumanApproval {
		t.Fatalf("committed+approved must not still require approval: %+v", d)
	}
	if !strings.Contains(strings.Join(d.Reasons, ","), "ai_mapping") {
		t.Fatalf("committed results must still record gate reasons, got %v", d.Reasons)
	}
	if !strings.Contains(strings.Join(d.Reasons, ","), "anomalies_present") {
		t.Fatalf("expected anomalies reason on committed result: %v", d.Reasons)
	}
}

func TestEvaluateApproval_Mock(t *testing.T) {
	d := EvaluateApproval(Input{MappingSource: "mock", IsStaged: true})
	if !strings.Contains(strings.Join(d.Reasons, ","), "mock_sample") {
		t.Fatalf("reasons=%v", d.Reasons)
	}
}

func TestNeedsWriteApproval_Sources(t *testing.T) {
	if !NeedsWriteApproval(Input{MappingSource: "ai"}) {
		t.Fatal("ai")
	}
	if !NeedsWriteApproval(Input{MappingSource: "cache"}) {
		t.Fatal("cache")
	}
	if !NeedsWriteApproval(Input{MappingSource: "mock"}) {
		t.Fatal("mock")
	}
	if !NeedsWriteApproval(Input{MappingSource: "deterministic", ValidationStatus: "flagged"}) {
		t.Fatal("flagged")
	}
	if NeedsWriteApproval(Input{MappingSource: "deterministic", ValidationStatus: "ok"}) {
		t.Fatal("clean deterministic must not require write approval")
	}
}

func TestBlockDurableWrite(t *testing.T) {
	err := BlockDurableWrite(Input{MappingSource: "ai"})
	if !errors.Is(err, ErrHumanApprovalRequired) {
		t.Fatalf("got %v", err)
	}
	if err := BlockDurableWrite(Input{MappingSource: "ai", HumanApproved: true}); err != nil {
		t.Fatal(err)
	}
	if err := BlockDurableWrite(Input{MappingSource: "deterministic"}); err != nil {
		t.Fatal(err)
	}
}

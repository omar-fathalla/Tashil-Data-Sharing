package guardrails

import (
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

func TestEvaluateApproval_Committed(t *testing.T) {
	d := EvaluateApproval(Input{IsCommitted: true, IsStaged: false, MappingSource: "ai"})
	if d.RequiresHumanApproval {
		t.Fatalf("committed must not require approval: %+v", d)
	}
}

func TestEvaluateApproval_Mock(t *testing.T) {
	d := EvaluateApproval(Input{MappingSource: "mock", IsStaged: true})
	if !strings.Contains(strings.Join(d.Reasons, ","), "mock_sample") {
		t.Fatalf("reasons=%v", d.Reasons)
	}
}

package branchmaster

import "context"

// StaticAI is a no-op proposer used when Gemini is unavailable (tests / mock).
// Production can wrap a Gemini client that implements AIProposer.
type StaticAI struct{}

func (StaticAI) Propose(_ context.Context, _ string, _ []Branch) (string, float64, string, error) {
	return "", 0, "", nil
}

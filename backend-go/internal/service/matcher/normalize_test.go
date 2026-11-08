package matcher

import "testing"

func TestJaccardUniqueTokenIntersection(t *testing.T) {
	// Identical unique sets → 1
	if g := jaccard([]string{"كلوريل", "مبيض"}, []string{"كلوريل", "مبيض"}); g != 1 {
		t.Fatalf("identical sets: got %v", g)
	}
	// Repeated tokens must not inflate intersection beyond unique count.
	// a={كلوريل}, b unique={كلوريل} → jaccard 1 even if b lists كلوريل thrice.
	if g := jaccard([]string{"كلوريل"}, []string{"كلوريل", "كلوريل", "كلوريل"}); g != 1 {
		t.Fatalf("repeated tokens inflated score: got %v want 1", g)
	}
	// a={a,b} b={a,a,a} → inter=1 union=2 → 0.5 (not 3/4)
	if g := jaccard([]string{"a", "b"}, []string{"a", "a", "a"}); g != 0.5 {
		t.Fatalf("unique intersection: got %v want 0.5", g)
	}
	// Disjoint
	if g := jaccard([]string{"فيبا"}, []string{"كلوريل"}); g != 0 {
		t.Fatalf("disjoint: got %v", g)
	}
	// Empty
	if g := jaccard(nil, []string{"x"}); g != 0 {
		t.Fatalf("empty: got %v", g)
	}
}

func TestCoreTokensDropsStopWordsButKeepsRepeatsForJaccardCaller(t *testing.T) {
	toks := coreTokens(tokenizeArabic("كلوريل كلوريل مبيض عادي"))
	// stop word عادي dropped; كلوريل may still appear twice in the slice —
	// jaccard must still treat them as one unique token.
	if g := jaccard(toks, []string{"كلوريل", "مبيض"}); g != 1 {
		t.Fatalf("core+jaccard with repeats: toks=%v score=%v", toks, g)
	}
}

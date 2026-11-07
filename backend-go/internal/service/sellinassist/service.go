package sellinassist

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

const (
	defaultModel     = "gemini-3.8-flash"
	defaultTier2     = "gemini-pro-latest"
	minLayoutAIConf  = 0.7
	sampleRowLimit   = 12
)

// Service proposes Sell-In layout and customer→chain suggestions with human approval.
type Service struct {
	apiKey     string
	model      string
	tier2Model string
	apiBase    string
	httpClient *http.Client
	useMock    bool
	store      *Store
	caller     jsonCaller // tests inject; nil → real Gemini
}

// New creates a Sell-In assist service. Empty apiKey enables mock/deterministic-only mode.
func New(apiKey, model string, useMock bool) *Service {
	apiKey = strings.TrimSpace(apiKey)
	model = strings.TrimSpace(model)
	if model == "" {
		model = defaultModel
	}
	return &Service{
		apiKey:     apiKey,
		model:      model,
		tier2Model: defaultTier2,
		apiBase:    defaultGeminiBase,
		httpClient: &http.Client{Timeout: 60 * time.Second},
		useMock:    useMock || apiKey == "",
		store:      NewStore(),
	}
}

// WithTier2Model sets the escalation model.
func (s *Service) WithTier2Model(m string) *Service {
	if strings.TrimSpace(m) != "" {
		s.tier2Model = strings.TrimSpace(m)
	}
	return s
}

// WithCaller injects a Gemini JSON caller (tests).
func (s *Service) WithCaller(c jsonCaller) *Service {
	s.caller = c
	return s
}

// WithAPIBase overrides the Gemini API host (tests).
func (s *Service) WithAPIBase(base string) *Service {
	s.apiBase = strings.TrimRight(strings.TrimSpace(base), "/")
	return s
}

// SuggestLayout inspects sample rows and returns a pending layout suggestion.
// Prefer deterministic header scoring; escalate to Gemini only when confidence is low
// and a caller/API key is available. Never applies the mapping.
func (s *Service) SuggestLayout(ctx context.Context, tenantID, filename string, sample [][]string) (*Suggestion, error) {
	if strings.TrimSpace(tenantID) == "" {
		return nil, fmt.Errorf("tenant_id مطلوب")
	}
	if len(sample) > sampleRowLimit {
		sample = sample[:sampleRowLimit]
	}
	guess := guessLayoutFromSample(filename, sample)
	if guess == nil {
		return nil, fmt.Errorf("مفيش صفوف نقدر نقرأها من الملف")
	}

	sug := &Suggestion{
		TenantID:       tenantID,
		Kind:           KindLayout,
		Status:         StatusPending,
		Filename:       filename,
		HeaderRowIndex: guess.HeaderRowIndex,
		Layout:         guess.Layout,
		Columns:        guess.Columns,
		MissingRoles:   guess.Missing,
		Confidence:     guess.Confidence,
		MappingSource:  SourceDeterministic,
		ReasonAR:       guess.ReasonAR,
	}

	needAI := guess.Confidence < minLayoutAIConf || guess.Layout == "unknown" || len(guess.Missing) > 0
	if needAI && !s.useMock {
		if ai, tier, model, err := s.inferLayoutAI(ctx, filename, sample); err == nil && ai != nil && ai.Confidence >= guess.Confidence {
			sug.HeaderRowIndex = ai.HeaderRowIndex
			sug.Layout = ai.Layout
			sug.Columns = ai.Columns
			sug.MissingRoles = ai.MissingRoles
			sug.Confidence = ai.Confidence
			sug.ReasonAR = ai.ReasonAR
			if sug.ReasonAR == "" {
				sug.ReasonAR = "اقتراح تخطيط من Gemini — محتاج موافقة قبل الاستخدام"
			}
			sug.MappingSource = SourceAI
			sug.AiTierUsed = tier
			sug.ModelUsed = model
		}
	} else if needAI && s.useMock && !isProduction() {
		// Deterministic already filled; label stays deterministic/mock only when we invent.
		if guess.Layout == "unknown" {
			sug.MappingSource = SourceMock
			sug.ModelUsed = "mock"
			sug.ReasonAR = "وضع تجريبي: مفيش مفتاح Gemini — الاقتراح تقريبي ومحتاج مراجعة"
		}
	}

	return s.store.put(sug), nil
}

func (s *Service) inferLayoutAI(ctx context.Context, filename string, sample [][]string) (*layoutAIResponse, string, string, error) {
	caller := s.caller
	if caller == nil {
		caller = func(ctx context.Context, model, prompt string) (string, error) {
			return s.callGeminiJSON(ctx, model, prompt, sellInLayoutSchemaJSON, filename)
		}
	}
	prompt := buildSellInLayoutPrompt(filename, sample)
	attempts := []struct{ tier, model string }{{"tier1", s.model}}
	if s.tier2Model != "" && s.tier2Model != s.model {
		attempts = append(attempts, struct{ tier, model string }{"tier2", s.tier2Model})
	}
	var lastErr error
	for _, a := range attempts {
		raw, err := caller(ctx, a.model, prompt)
		if err != nil {
			lastErr = err
			continue
		}
		var parsed layoutAIResponse
		if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
			lastErr = err
			continue
		}
		if parsed.Confidence < minLayoutAIConf {
			lastErr = fmt.Errorf("low confidence %.2f", parsed.Confidence)
			continue
		}
		return &parsed, a.tier, a.model, nil
	}
	return nil, "", "", lastErr
}

// SuggestCustomerChains proposes SELLIN_CUSTOMER_CHAIN_MAP entries for unresolved customers.
// Suggestions are never applied automatically.
func (s *Service) SuggestCustomerChains(ctx context.Context, tenantID, uploadChain string, customers []string) ([]*Suggestion, error) {
	_ = ctx
	if strings.TrimSpace(tenantID) == "" {
		return nil, fmt.Errorf("tenant_id مطلوب")
	}
	cands := proposeCustomerChains(customers, uploadChain)
	out := make([]*Suggestion, 0, len(cands))
	for _, c := range cands {
		sug := &Suggestion{
			TenantID:        tenantID,
			Kind:            KindCustomerChain,
			Status:          StatusPending,
			Confidence:      c.Conf,
			MappingSource:   SourceDeterministic,
			ReasonAR:        c.ReasonAR,
			CustomerNeedle:  c.Needle,
			SuggestedChain:  c.Chain,
			SampleCustomers: c.Samples,
			UploadChain:     uploadChain,
			EnvFragment:     envFragment(c.Needle, c.Chain),
		}
		out = append(out, s.store.put(sug))
	}
	return out, nil
}

// List returns suggestions for a tenant, optionally filtered by status.
func (s *Service) List(tenantID, status string) []Suggestion {
	return s.store.list(tenantID, status)
}

// Approve records human approval. It does NOT mutate SELLIN_CUSTOMER_CHAIN_MAP, BigQuery, or uploads.
func (s *Service) Approve(id, actor string) (*Suggestion, error) {
	return s.store.decide(id, StatusApproved, actor)
}

// Reject records human rejection.
func (s *Service) Reject(id, actor string) (*Suggestion, error) {
	return s.store.decide(id, StatusRejected, actor)
}

// GetMetrics returns funnel success metrics for the in-memory store.
func (s *Service) GetMetrics() Metrics {
	pending, approved, rejected, layoutSug, layoutApp, chainSug, chainApp := s.store.snapshotCounts()
	m := Metrics{
		Suggested:       pending + approved + rejected,
		Approved:        approved,
		Rejected:        rejected,
		Pending:         pending,
		LayoutSuggested: layoutSug,
		LayoutApproved:  layoutApp,
		ChainSuggested:  chainSug,
		ChainApproved:   chainApp,
	}
	decided := approved + rejected
	if decided > 0 {
		m.ApprovalRate = float64(approved) / float64(decided)
	}
	if layoutSug > 0 {
		m.LayoutApprovalRate = float64(layoutApp) / float64(layoutSug)
	}
	if chainSug > 0 {
		m.ChainApprovalRate = float64(chainApp) / float64(chainSug)
	}
	return m
}

// ApprovedEnvFragments returns approved customer→chain fragments for ops copy/paste
// into SELLIN_CUSTOMER_CHAIN_MAP. Does not apply them.
func (s *Service) ApprovedEnvFragments(tenantID string) []string {
	var out []string
	for _, sug := range s.store.list(tenantID, StatusApproved) {
		if sug.Kind == KindCustomerChain && sug.EnvFragment != "" {
			out = append(out, sug.EnvFragment)
		}
	}
	return out
}

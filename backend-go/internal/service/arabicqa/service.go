package arabicqa

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

const (
	defaultModel = "gemini-3.8-flash"
	sourceDet    = "deterministic"
	sourceAI     = "ai"
)

// DataReader is the read-only BigQuery surface Arabic Q&A may call.
// Write methods (Insert/Replace/Set/Clear/Upsert/Delete) are intentionally absent.
type DataReader interface {
	GetExecutiveKPIs(ctx context.Context, tenantID, period string, dateRange ...string) (*domain.ExecutiveKPIs, error)
	GetChainShares(ctx context.Context, tenantID, period string, dateRange ...string) ([]domain.ChainShareSummary, error)
	GetSellInRecords(ctx context.Context, tenantID string, filter bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error)
}

// Service answers Arabic questions from tenant-scoped BigQuery reads.
type Service struct {
	data       DataReader
	apiKey     string
	model      string
	apiBase    string
	httpClient *http.Client
	useMock    bool
	caller     jsonCaller
}

// New builds an Arabic Q&A service. Empty apiKey → deterministic answers only.
func New(data DataReader, apiKey, model string, useMock bool) *Service {
	apiKey = strings.TrimSpace(apiKey)
	model = strings.TrimSpace(model)
	if model == "" {
		model = defaultModel
	}
	return &Service{
		data:       data,
		apiKey:     apiKey,
		model:      model,
		apiBase:    defaultGeminiBase,
		httpClient: &http.Client{Timeout: 45 * time.Second},
		useMock:    useMock || apiKey == "",
	}
}

// WithCaller injects a Gemini JSON caller (tests).
func (s *Service) WithCaller(c jsonCaller) *Service {
	s.caller = c
	return s
}

// WithAPIBase overrides the Gemini host (tests).
func (s *Service) WithAPIBase(base string) *Service {
	s.apiBase = strings.TrimRight(strings.TrimSpace(base), "/")
	return s
}

// Ask answers one Arabic question for tenantID using read-only BQ data.
func (s *Service) Ask(ctx context.Context, tenantID, question string) (*Answer, error) {
	tenantID = strings.TrimSpace(tenantID)
	question = strings.TrimSpace(question)
	if tenantID == "" {
		return nil, fmt.Errorf("tenant_id مطلوب")
	}
	if question == "" {
		return nil, fmt.Errorf("السؤال مطلوب")
	}
	if s == nil || s.data == nil {
		return nil, fmt.Errorf("خدمة الأسئلة العربية مش متاحة")
	}

	intent := classifyIntent(question)
	period := detectPeriod(question)

	ans := &Answer{
		QuestionAR:    question,
		Intent:        intent,
		Period:        period,
		TenantID:      tenantID,
		ReadOnly:      true,
		MappingSource: sourceDet,
		Evidence:      map[string]interface{}{},
		Sources:       []string{},
	}

	var (
		text string
		ev   map[string]interface{}
		err  error
	)

	switch intent {
	case IntentExecutiveKPIs:
		kpis, e := s.data.GetExecutiveKPIs(ctx, tenantID, period)
		err = e
		text, ev = answerExecutive(kpis, period)
		ans.Sources = []string{"bigquery.executive_kpis"}
		ans.Confidence = 0.92
	case IntentChainShares:
		shares, e := s.data.GetChainShares(ctx, tenantID, period)
		err = e
		if err == nil && len(shares) == 0 {
			// Fall back to KPIs chain shares when dedicated call is empty.
			if kpis, e2 := s.data.GetExecutiveKPIs(ctx, tenantID, period); e2 == nil && kpis != nil {
				shares = kpis.ChainShares
			}
		}
		text, ev = answerChainShares(shares, period)
		ans.Sources = []string{"bigquery.chain_shares"}
		ans.Confidence = 0.9
	case IntentTopSKUs:
		kpis, e := s.data.GetExecutiveKPIs(ctx, tenantID, period)
		err = e
		text, ev = answerTopSKUs(kpis, period)
		ans.Sources = []string{"bigquery.pareto_skus"}
		ans.Confidence = 0.88
	case IntentCategories:
		kpis, e := s.data.GetExecutiveKPIs(ctx, tenantID, period)
		err = e
		text, ev = answerCategories(kpis, period)
		ans.Sources = []string{"bigquery.category_contributions"}
		ans.Confidence = 0.88
	case IntentSellIn:
		filter, okPeriod := sellInFilterForPeriod(period, time.Now())
		if !okPeriod {
			// Sell-In is monthly — TODAY has no day grain; do not fake MTD.
			text, ev = unsupportedTodaySellIn()
			ans.Intent = IntentUnsupported
			ans.Confidence = 0.35
			ans.Sources = []string{"bigquery.sell_in_records"}
			break
		}
		recs, total, e := s.data.GetSellInRecords(ctx, tenantID, filter)
		err = e
		var rev, units float64
		for _, r := range recs {
			rev += r.NetValueEGP
			if r.TotalUnitsSupplied > 0 {
				units += float64(r.TotalUnitsSupplied)
			} else {
				units += r.NetQtyCases
			}
		}
		count := total
		if count == 0 {
			count = len(recs)
		}
		text, ev = answerSellIn(rev, units, count, period)
		if ev == nil {
			ev = map[string]interface{}{}
		}
		ev["filter_year"] = filter.Year
		ev["filter_month"] = filter.Month
		ev["aggregated_rows"] = len(recs)
		ans.Sources = []string{"bigquery.sell_in_records"}
		ans.Confidence = 0.9
	default:
		text, ev = unsupportedAnswer()
		ans.Confidence = 0.4
		ans.Capabilities = capabilityTitles()
	}

	if err != nil {
		return nil, fmt.Errorf("تعذّر قراءة بيانات BigQuery: %w", err)
	}
	ans.AnswerAR = text
	ans.Evidence = ev

	// Optional Gemini claim subset → server-side NarrateFromClaims only (never model prose).
	if ans.Intent != IntentUnsupported && !s.useMock {
		evidenceClaims := claimsFromEvidence(ev)
		if used, freeText, ok := s.askGeminiClaims(ctx, question, evidenceClaims); ok {
			_ = freeText // never shipped
			if sanitized, ok := acceptAIClaims(used, evidenceClaims); ok {
				intro, _ := ev["intro_ar"].(string)
				if intro == "" {
					intro = "الإجابة"
				}
				ans.AnswerAR = NarrateFromClaims(period, intro, sanitized)
				ans.MappingSource = sourceAI
				ans.Evidence = claimsToEvidence(period, sanitized, map[string]interface{}{
					"intro_ar":      intro,
					"ai_claim_path": true,
				})
			}
		}
	}

	return ans, nil
}

func capabilityTitles() []string {
	caps := Capabilities()
	out := make([]string, 0, len(caps))
	for _, c := range caps {
		out = append(out, c.TitleAR)
	}
	return out
}

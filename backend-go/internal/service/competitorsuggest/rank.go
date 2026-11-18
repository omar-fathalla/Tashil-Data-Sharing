package competitorsuggest

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

const defaultGeminiBase = "https://generativelanguage.googleapis.com"

// RankedSuggestion is one AI-ranked competitor from the pre-filtered list only.
type RankedSuggestion struct {
	CompetitorBarcode string  `json:"competitor_barcode"`
	ReasonAR          string  `json:"reason_ar"`
	Confidence        float64 `json:"confidence"`
	Rank              int     `json:"rank"`
}

// TokenUsage captures Gemini token counters for cost logging (0 when unknown/mock).
type TokenUsage struct {
	PromptTokens     int
	CompletionTokens int
}

// Ranker ranks up to MaxRank competitors for one own SKU from a candidate list.
type Ranker interface {
	Rank(ctx context.Context, own SkuCandidate, candidates []PrefScore) ([]RankedSuggestion, TokenUsage, error)
}

// GeminiRanker calls Gemini with a JSON schema; injectable HTTP for tests.
type GeminiRanker struct {
	APIKey     string
	Model      string
	// Tier2Model is used when the primary model fails (404, timeout, 5xx, etc.).
	Tier2Model string
	APIBase    string
	HTTPClient *http.Client
	UseMock    bool
	// CallJSON overrides the live HTTP path (tests).
	CallJSON func(ctx context.Context, model, prompt string) (string, TokenUsage, error)
}

type geminiRequest struct {
	Contents         []geminiContent         `json:"contents"`
	GenerationConfig *geminiGenerationConfig `json:"generationConfig,omitempty"`
}

type geminiContent struct {
	Role  string       `json:"role,omitempty"`
	Parts []geminiPart `json:"parts"`
}

type geminiPart struct {
	Text string `json:"text"`
}

type geminiGenerationConfig struct {
	ResponseMimeType string                `json:"responseMimeType,omitempty"`
	// Temperature omitted for Gemini 3.x (deprecated sampling param; can stall/reject).
	Temperature    *float64              `json:"temperature,omitempty"`
	ThinkingConfig *geminiThinkingConfig `json:"thinkingConfig,omitempty"`
}

// geminiThinkingConfig sets Gemini 3.x reasoning effort (low|medium|high).
type geminiThinkingConfig struct {
	ThinkingLevel string `json:"thinkingLevel,omitempty"`
}

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	UsageMetadata *struct {
		PromptTokenCount     int `json:"promptTokenCount"`
		CandidatesTokenCount int `json:"candidatesTokenCount"`
		TotalTokenCount      int `json:"totalTokenCount"`
	} `json:"usageMetadata"`
}

type aiPayload struct {
	Suggestions []RankedSuggestion `json:"suggestions"`
}

// Rank returns up to MaxRank suggestions. Hallucinated barcodes outside the
// candidate set are stripped server-side. Empty candidates → no AI call.
func (r *GeminiRanker) Rank(ctx context.Context, own SkuCandidate, candidates []PrefScore) ([]RankedSuggestion, TokenUsage, error) {
	if len(candidates) == 0 {
		return nil, TokenUsage{}, nil
	}
	allowed := map[string]bool{}
	var lines []string
	for i, c := range candidates {
		bc := strings.TrimSpace(c.Candidate.Barcode)
		allowed[bc] = true
		lines = append(lines, fmt.Sprintf(
			"%d) barcode=%s name=%q supplier=%q price=%.2f units=%d size_similar=%v variant_bonus=%v",
			i+1, bc, c.Candidate.SKUName, c.Candidate.Supplier, c.Candidate.UnitPrice, c.Candidate.Units,
			c.SizeSimilar, c.VariantBonus,
		))
	}
	prompt := fmt.Sprintf(`أنت مساعد لترتيب منافسي أصناف شركة ادكو من قائمة مرشحين فقط.
أرجع JSON فقط:
{"suggestions":[{"competitor_barcode":"...","reason_ar":"...","confidence":0.0,"rank":1}]}

القواعد:
1) اختر حتى %d منافسين من القائمة فقط — ممنوع اختراع باركود خارج القائمة.
2) reason_ar جملة عربية قصيرة (لماذا هذا المنافس مناسب).
3) confidence بين 0 و 1.
4) rank من 1 إلى عدد المقترحات (الأفضل = 1).
5) لا تستخدم ملفات Plan — المصدر Sell-Out فقط.

صنف الشركة:
barcode=%s name=%q category=%q price=%.2f

المرشحون:
%s`, MaxRank, own.Barcode, own.SKUName, own.Category, own.UnitPrice, strings.Join(lines, "\n"))

	var raw string
	var usage TokenUsage
	var err error
	if r.CallJSON != nil {
		raw, usage, err = r.CallJSON(ctx, r.Model, prompt)
	} else if r.UseMock || r.apiKey() == "" {
		raw, usage, err = r.mockRank(own, candidates), TokenUsage{}, nil
	} else {
		raw, usage, err = r.callGeminiJSON(ctx, r.model(), prompt)
	}
	if err != nil {
		return nil, usage, err
	}
	ranked, err := ParseAndValidateRank(raw, allowed)
	return ranked, usage, err
}

func (r *GeminiRanker) model() string {
	if m := strings.TrimSpace(r.Model); m != "" {
		return m
	}
	return "gemini-pro-latest"
}

func (r *GeminiRanker) tier2() string {
	if m := strings.TrimSpace(r.Tier2Model); m != "" {
		return m
	}
	return "gemini-pro-latest"
}

func (r *GeminiRanker) apiKey() string {
	return strings.TrimSpace(r.APIKey)
}

func (r *GeminiRanker) mockRank(own SkuCandidate, candidates []PrefScore) string {
	n := len(candidates)
	if n > MaxRank {
		n = MaxRank
	}
	sugs := make([]RankedSuggestion, 0, n)
	for i := 0; i < n; i++ {
		c := candidates[i].Candidate
		sugs = append(sugs, RankedSuggestion{
			CompetitorBarcode: c.Barcode,
			ReasonAR:          fmt.Sprintf("مرشح تجريبي لنفس الفئة مقابل %s", own.SKUName),
			Confidence:        0.55 + float64(n-i)*0.1,
			Rank:              i + 1,
		})
	}
	b, _ := json.Marshal(aiPayload{Suggestions: sugs})
	return string(b)
}

func (r *GeminiRanker) callGeminiJSON(ctx context.Context, model, prompt string) (string, TokenUsage, error) {
	primaryCtx, cancel := context.WithTimeout(ctx, primaryAttemptBudget(ctx))
	raw, usage, err := r.doGeminiJSON(primaryCtx, model, prompt)
	cancel()
	if err == nil {
		return raw, usage, nil
	}
	fallback := r.tier2()
	// Fall back on any primary failure (404, timeout, 5xx) while parent ctx remains usable.
	if fallback == "" || fallback == model || ctx.Err() != nil {
		return "", usage, err
	}
	log.Printf("[competitor-suggest] model %q failed (%v); falling back to GEMINI_TIER2_MODEL=%q", model, err, fallback)
	return r.doGeminiJSON(ctx, fallback, prompt)
}

// primaryAttemptBudget leaves room for Tier2 when the parent deadline is generous.
func primaryAttemptBudget(ctx context.Context) time.Duration {
	const defaultPrimary = 18 * time.Second
	deadline, ok := ctx.Deadline()
	if !ok {
		return defaultPrimary
	}
	remain := time.Until(deadline)
	if remain <= 0 {
		return time.Millisecond
	}
	// Reserve ~10s for Tier2 when possible.
	if remain > 20*time.Second {
		return remain - 10*time.Second
	}
	// Otherwise split so a slow primary cannot consume the whole parent deadline.
	half := remain / 2
	if half < 20*time.Millisecond {
		return remain
	}
	return half
}

func (r *GeminiRanker) doGeminiJSON(ctx context.Context, model, prompt string) (string, TokenUsage, error) {
	started := time.Now()
	genCfg := &geminiGenerationConfig{
		ResponseMimeType: "application/json",
		// Competitor ranking is latency-critical; pin thinking to low for Gemini 3.x.
		ThinkingConfig: &geminiThinkingConfig{ThinkingLevel: "low"},
	}
	body, err := json.Marshal(geminiRequest{
		Contents:         []geminiContent{{Role: "user", Parts: []geminiPart{{Text: prompt}}}},
		GenerationConfig: genCfg,
	})
	if err != nil {
		return "", TokenUsage{}, err
	}
	base := strings.TrimRight(r.APIBase, "/")
	if base == "" {
		base = defaultGeminiBase
	}
	endpoint := fmt.Sprintf("%s/v1beta/models/%s:generateContent", base, model)
	client := r.HTTPClient
	if client == nil {
		// Upper bound; request ctx deadline is the real guard (handler ~30s).
		client = &http.Client{Timeout: 30 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "", TokenUsage{}, err
	}
	apiKey := r.apiKey()
	req.Header.Set("Content-Type", "application/json")
	// Trim again at the wire boundary: Secret Manager newlines make Go reject the header.
	req.Header.Set("x-goog-api-key", apiKey)
	resp, err := client.Do(req)
	if err != nil {
		safe := fmt.Errorf("gemini competitor suggest failed: %s", redactKey(err.Error(), apiKey))
		log.Printf("[competitor-suggest] gemini err after %s: %v", time.Since(started), safe)
		return "", TokenUsage{}, safe
	}
	defer resp.Body.Close()
	rawBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		log.Printf("[competitor-suggest] gemini status=%d model=%s latency=%s", resp.StatusCode, model, time.Since(started))
		err := fmt.Errorf("gemini competitor suggest status %d", resp.StatusCode)
		if isModelNotFoundStatus(resp.StatusCode, rawBody) {
			err = fmt.Errorf("%w: model not found", err)
		}
		return "", TokenUsage{}, err
	}
	var gr geminiResponse
	if err := json.Unmarshal(rawBody, &gr); err != nil {
		return "", TokenUsage{}, err
	}
	usage := TokenUsage{}
	if gr.UsageMetadata != nil {
		usage.PromptTokens = gr.UsageMetadata.PromptTokenCount
		usage.CompletionTokens = gr.UsageMetadata.CandidatesTokenCount
		log.Printf("[competitor-suggest] tokens prompt=%d completion=%d total=%d latency=%s",
			usage.PromptTokens, usage.CompletionTokens, gr.UsageMetadata.TotalTokenCount, time.Since(started))
	} else {
		log.Printf("[competitor-suggest] gemini ok latency=%s (no usage metadata)", time.Since(started))
	}
	if len(gr.Candidates) == 0 || len(gr.Candidates[0].Content.Parts) == 0 {
		return "", usage, fmt.Errorf("gemini competitor suggest returned no candidates")
	}
	return gr.Candidates[0].Content.Parts[0].Text, usage, nil
}

func isModelNotFoundStatus(status int, body []byte) bool {
	if status == http.StatusNotFound {
		return true
	}
	lower := strings.ToLower(string(body))
	return strings.Contains(lower, "not found") && strings.Contains(lower, "model")
}

func isGeminiModelNotFound(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(strings.ToLower(err.Error()), "model not found")
}

func redactKey(msg, apiKey string) string {
	if apiKey == "" {
		return msg
	}
	return strings.ReplaceAll(msg, apiKey, "[REDACTED]")
}

// ParseAndValidateRank unmarshals AI JSON and drops any barcode outside allowed.
func ParseAndValidateRank(raw string, allowed map[string]bool) ([]RankedSuggestion, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, fmt.Errorf("empty ai payload")
	}
	if strings.HasPrefix(raw, "```") {
		raw = strings.TrimPrefix(raw, "```json")
		raw = strings.TrimPrefix(raw, "```JSON")
		raw = strings.TrimPrefix(raw, "```")
		raw = strings.TrimSuffix(raw, "```")
		raw = strings.TrimSpace(raw)
	}
	var p aiPayload
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		return nil, err
	}
	out := make([]RankedSuggestion, 0, MaxRank)
	seen := map[string]bool{}
	for _, s := range p.Suggestions {
		bc := strings.TrimSpace(s.CompetitorBarcode)
		if bc == "" || !allowed[bc] || seen[bc] {
			continue // reject hallucinated / duplicate
		}
		seen[bc] = true
		conf := s.Confidence
		if conf < 0 {
			conf = 0
		}
		if conf > 1 {
			conf = 1
		}
		reason := strings.TrimSpace(s.ReasonAR)
		if reason == "" {
			reason = "مقترح من الذكاء الاصطناعي لنفس الفئة"
		}
		out = append(out, RankedSuggestion{
			CompetitorBarcode: bc,
			ReasonAR:          reason,
			Confidence:        conf,
			Rank:              len(out) + 1,
		})
		if len(out) >= MaxRank {
			break
		}
	}
	return out, nil
}

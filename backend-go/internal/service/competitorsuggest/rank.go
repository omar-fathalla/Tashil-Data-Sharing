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
	ResponseMimeType string  `json:"responseMimeType,omitempty"`
	Temperature      float64 `json:"temperature"`
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
	prompt := fmt.Sprintf(`أنت مساعد لترتيب منافسي أصناف شركة أديكو من قائمة مرشحين فقط.
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
	} else if r.UseMock || strings.TrimSpace(r.APIKey) == "" {
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
	if strings.TrimSpace(r.Model) == "" {
		return "gemini-pro-latest"
	}
	return r.Model
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
	started := time.Now()
	body, err := json.Marshal(geminiRequest{
		Contents: []geminiContent{{Role: "user", Parts: []geminiPart{{Text: prompt}}}},
		GenerationConfig: &geminiGenerationConfig{
			ResponseMimeType: "application/json",
			Temperature:      0,
		},
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
		client = &http.Client{Timeout: 45 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "", TokenUsage{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-goog-api-key", r.APIKey)
	resp, err := client.Do(req)
	if err != nil {
		safe := fmt.Errorf("gemini competitor suggest failed: %s", redactKey(err.Error(), r.APIKey))
		log.Printf("[competitor-suggest] gemini err after %s: %v", time.Since(started), safe)
		return "", TokenUsage{}, safe
	}
	defer resp.Body.Close()
	rawBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		log.Printf("[competitor-suggest] gemini status=%d latency=%s", resp.StatusCode, time.Since(started))
		return "", TokenUsage{}, fmt.Errorf("gemini competitor suggest status %d", resp.StatusCode)
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

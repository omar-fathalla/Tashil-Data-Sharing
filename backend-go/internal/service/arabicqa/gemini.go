package arabicqa

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

type jsonCaller func(ctx context.Context, model, prompt string) (string, error)

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
}

// polishPayload is the only accepted AI shape. answer_ar is never shipped —
// the server rebuilds Arabic exclusively via NarrateFromClaims.
type polishPayload struct {
	AnswerAR string  `json:"answer_ar"`
	Claims   []Claim `json:"claims"`
}

func redactKey(msg, apiKey string) string {
	if apiKey == "" {
		return msg
	}
	return strings.ReplaceAll(msg, apiKey, "[REDACTED]")
}

// askGeminiClaims asks Gemini for a structured claim subset. Free text is ignored.
func (s *Service) askGeminiClaims(ctx context.Context, question string, evidence []Claim) ([]Claim, string, bool) {
	claimsJSON, _ := json.Marshal(evidence)
	prompt := fmt.Sprintf(`أنت مساعد عربي لبيانات مبيعات بالتجزئة.
أرجع JSON فقط (بدون Markdown):
{"answer_ar":"...","claims":[{"metric":"...","entity":"...","value":0}]}

القواعد:
1) claims لازم تكون subset من claims الأدلة — نفس metric + entity + value حرفياً.
2) ممنوع اختراع أرقام أو نقل قيمة من entity لـ entity تانية.
3) answer_ar للتحقق فقط ولن يُعرض للمستخدم — النص النهائي يُبنى من claims على الخادم.
4) لا تعتمد على حقل display؛ الخادم يعيد حسابه.
5) claims فارغة = مرفوض.

السؤال: %s
claims الأدلة: %s`, question, string(claimsJSON))

	raw, err := s.callGeminiJSON(ctx, s.model, prompt)
	if err != nil {
		return nil, "", false
	}
	p, err := parsePolishPayload(raw)
	if err != nil {
		return nil, "", false
	}
	return p.Claims, p.AnswerAR, true
}

func parsePolishPayload(raw string) (polishPayload, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return polishPayload{}, fmt.Errorf("empty ai payload")
	}
	if strings.HasPrefix(raw, "```") {
		raw = strings.TrimPrefix(raw, "```json")
		raw = strings.TrimPrefix(raw, "```JSON")
		raw = strings.TrimPrefix(raw, "```")
		raw = strings.TrimSuffix(raw, "```")
		raw = strings.TrimSpace(raw)
	}
	var p polishPayload
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		return polishPayload{}, err
	}
	p.AnswerAR = strings.TrimSpace(p.AnswerAR)
	if len(p.Claims) == 0 {
		return polishPayload{}, fmt.Errorf("ai payload missing claims")
	}
	return p, nil
}

// acceptAIClaims validates used claims as a metric+entity+value subset of
// evidence. Empty used → reject. Display is recomputed from evidence (model
// Display is ignored). Returns sanitized claims ready for NarrateFromClaims.
func acceptAIClaims(used, evidence []Claim) ([]Claim, bool) {
	if len(used) == 0 {
		return nil, false
	}
	idx := claimIndex(evidence)
	if len(idx) == 0 {
		return nil, false
	}
	out := make([]Claim, 0, len(used))
	seen := map[string]bool{}
	for _, u := range used {
		key := u.key()
		if key == "|" || strings.TrimSpace(u.Metric) == "" {
			return nil, false
		}
		ev, ok := idx[key]
		if !ok || !sameValue(ev.Value, u.Value) {
			return nil, false
		}
		if seen[key] {
			continue
		}
		seen[key] = true
		// Recompute Display server-side — never trust model Display.
		sanitized := Claim{
			Metric:  ev.Metric,
			Entity:  ev.Entity,
			Value:   ev.Value,
			Display: displayForMetric(ev.Metric, ev.Value),
		}
		out = append(out, sanitized)
	}
	if len(out) == 0 {
		return nil, false
	}
	return out, true
}

func displayForMetric(metric string, value float64) string {
	switch metric {
	case "total_units", "total_units_sold", "active_stores_count", "record_count":
		return claimDisplayInt(value)
	case "tenant_market_share_pct", "share_pct", "revenue_mom_pct":
		return claimDisplayPct(value)
	default:
		return claimDisplayEGP(value)
	}
}

func (s *Service) callGeminiJSON(ctx context.Context, model, prompt string) (string, error) {
	if s.caller != nil {
		return s.caller(ctx, model, prompt)
	}
	started := time.Now()
	body, err := json.Marshal(geminiRequest{
		Contents: []geminiContent{{Role: "user", Parts: []geminiPart{{Text: prompt}}}},
		GenerationConfig: &geminiGenerationConfig{
			ResponseMimeType: "application/json",
			Temperature:      0,
		},
	})
	if err != nil {
		return "", err
	}
	base := strings.TrimRight(s.apiBase, "/")
	if base == "" {
		base = defaultGeminiBase
	}
	endpoint := fmt.Sprintf("%s/v1beta/models/%s:generateContent", base, model)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-goog-api-key", s.apiKey)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		safe := fmt.Errorf("gemini arabic qa failed: %s", redactKey(err.Error(), s.apiKey))
		logQACall(model, started, false, safe)
		return "", safe
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, resp.Body)
		callErr := fmt.Errorf("gemini arabic qa status %d", resp.StatusCode)
		logQACall(model, started, false, callErr)
		return "", callErr
	}
	var gr geminiResponse
	if err := json.NewDecoder(resp.Body).Decode(&gr); err != nil {
		logQACall(model, started, false, err)
		return "", err
	}
	if len(gr.Candidates) == 0 || len(gr.Candidates[0].Content.Parts) == 0 {
		callErr := fmt.Errorf("gemini arabic qa returned no candidates")
		logQACall(model, started, false, callErr)
		return "", callErr
	}
	logQACall(model, started, true, nil)
	return gr.Candidates[0].Content.Parts[0].Text, nil
}

func logQACall(model string, started time.Time, ok bool, err error) {
	status := "ok"
	errMsg := ""
	if !ok {
		status = "fail"
		if err != nil {
			errMsg = err.Error()
		}
	}
	log.Printf("[arabic-qa-ai-call] model=%s latency_ms=%d status=%s err=%s",
		model, time.Since(started).Milliseconds(), status, errMsg)
}

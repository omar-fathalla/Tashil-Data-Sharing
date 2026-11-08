package arabicqa

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var numberToken = regexp.MustCompile(`\d+(?:\.\d+)?`)

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

// polishArabic asks Gemini to narrate only from metric+entity claims.
func (s *Service) polishArabic(ctx context.Context, question, grounded string, evidence map[string]interface{}) (string, []Claim, bool) {
	claims := claimsFromEvidence(evidence)
	claimsJSON, _ := json.Marshal(claims)
	prompt := fmt.Sprintf(`أنت مساعد عربي لبيانات مبيعات بالتجزئة.
اكتب إجابة عربية من الـ claims فقط. كل claim مربوط بـ metric + entity + value.
ممنوع اختراع أرقام أو نقل قيمة من entity لـ entity تانية.
أرجع JSON فقط:
{"answer_ar":"...","claims":[{"metric":"...","entity":"...","value":0,"display":"..."}]}
claims في الرد لازم تكون subset من claims الأدلة (نفس metric+entity+value).

السؤال: %s
الإجابة المؤسسة: %s
claims الأدلة: %s`, question, grounded, string(claimsJSON))

	raw, err := s.callGeminiJSON(ctx, s.model, prompt)
	if err != nil {
		return "", nil, false
	}
	var p polishPayload
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		raw = strings.TrimSpace(raw)
		raw = strings.TrimPrefix(raw, "```json")
		raw = strings.TrimPrefix(raw, "```")
		raw = strings.TrimSuffix(raw, "```")
		raw = strings.TrimSpace(raw)
		if err2 := json.Unmarshal([]byte(raw), &p); err2 != nil {
			return "", nil, false
		}
	}
	out := strings.TrimSpace(p.AnswerAR)
	if out == "" {
		return "", nil, false
	}
	return out, p.Claims, true
}

// polishPreservesClaims requires Gemini's used claims to be an exact metric+entity
// subset of evidence claims (same value), and the narrative numbers to come only
// from those bound claims — so entity/value swaps are rejected.
func polishPreservesClaims(polished string, used, evidence []Claim) bool {
	if strings.TrimSpace(polished) == "" {
		return false
	}
	idx := claimIndex(evidence)
	if len(idx) == 0 {
		return false
	}
	if len(used) == 0 {
		// No structured claims returned — fall back to number-only check against evidence values.
		return numbersOnlyFromClaims(polished, evidence)
	}
	allowedNums := map[string]bool{}
	for _, u := range used {
		ev, ok := idx[u.key()]
		if !ok || !sameValue(ev.Value, u.Value) {
			return false // unknown metric+entity or swapped value
		}
		for _, n := range numbersFromValue(u.Value) {
			allowedNums[canonicalizeNumber(n)] = true
		}
		for _, n := range numberToken.FindAllString(u.Display, -1) {
			allowedNums[canonicalizeNumber(n)] = true
		}
	}
	for _, n := range numberToken.FindAllString(polished, -1) {
		if !allowedNums[canonicalizeNumber(n)] {
			return false
		}
	}
	// At least one used claim value must appear in the narrative.
	for _, u := range used {
		for _, n := range numbersFromValue(u.Value) {
			if strings.Contains(polished, n) || strings.Contains(polished, fmt.Sprintf("%.2f", u.Value)) {
				return true
			}
			if canonicalizeNumber(n) != n && strings.Contains(polished, canonicalizeNumber(n)) {
				return true
			}
		}
	}
	return false
}

func numbersOnlyFromClaims(polished string, evidence []Claim) bool {
	allowed := map[string]bool{}
	for _, c := range evidence {
		for _, n := range numbersFromValue(c.Value) {
			allowed[canonicalizeNumber(n)] = true
		}
	}
	if len(allowed) == 0 {
		return false
	}
	nums := numberToken.FindAllString(polished, -1)
	if len(nums) == 0 {
		return false
	}
	for _, n := range nums {
		if !allowed[canonicalizeNumber(n)] {
			return false
		}
	}
	return true
}

func numbersFromValue(v interface{}) []string {
	switch x := v.(type) {
	case float64:
		return []string{strconv.FormatFloat(x, 'f', -1, 64), fmt.Sprintf("%.2f", x)}
	case float32:
		return []string{strconv.FormatFloat(float64(x), 'f', -1, 64), fmt.Sprintf("%.2f", float64(x))}
	case int:
		return []string{strconv.Itoa(x)}
	case int64:
		return []string{strconv.FormatInt(x, 10)}
	case json.Number:
		return []string{x.String()}
	case string:
		return numberToken.FindAllString(x, -1)
	default:
		return nil
	}
}

func canonicalizeNumber(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		if f == float64(int64(f)) {
			return strconv.FormatInt(int64(f), 10)
		}
		return strconv.FormatFloat(f, 'f', -1, 64)
	}
	return s
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

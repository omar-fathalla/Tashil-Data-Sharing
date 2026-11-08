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
	AnswerAR string `json:"answer_ar"`
}

func redactKey(msg, apiKey string) string {
	if apiKey == "" {
		return msg
	}
	return strings.ReplaceAll(msg, apiKey, "[REDACTED]")
}

// polishArabic asks Gemini to rephrase a grounded Arabic answer without changing numbers.
func (s *Service) polishArabic(ctx context.Context, question, grounded string, evidence map[string]interface{}) (string, bool) {
	evJSON, _ := json.Marshal(evidence)
	prompt := fmt.Sprintf(`أنت مساعد عربي لبيانات مبيعات بالتجزئة.
أعد صياغة الإجابة التالية بالعربية الفصحى المبسطة دون تغيير أي رقم أو اسم سلسلة أو منتج.
لو مفيش أرقام في الأدلة، ارفض الاختراع وارجّع نفس النص.
أرجع JSON فقط بالشكل: {"answer_ar":"..."}.

السؤال: %s
الإجابة المؤسسة: %s
الأدلة (JSON): %s`, question, grounded, string(evJSON))

	raw, err := s.callGeminiJSON(ctx, s.model, prompt)
	if err != nil {
		return "", false
	}
	var p polishPayload
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		// Some models wrap JSON in fences — try a light trim.
		raw = strings.TrimSpace(raw)
		raw = strings.TrimPrefix(raw, "```json")
		raw = strings.TrimPrefix(raw, "```")
		raw = strings.TrimSuffix(raw, "```")
		raw = strings.TrimSpace(raw)
		if err2 := json.Unmarshal([]byte(raw), &p); err2 != nil {
			return "", false
		}
	}
	out := strings.TrimSpace(p.AnswerAR)
	if out == "" {
		return "", false
	}
	return out, true
}

// polishPreservesClaims rejects Gemini output that invents numbers absent from
// the grounded answer / evidence, or drops every key evidence figure.
func polishPreservesClaims(polished, grounded string, evidence map[string]interface{}) bool {
	allowed := map[string]bool{}
	for _, n := range numberToken.FindAllString(grounded, -1) {
		allowed[canonicalizeNumber(n)] = true
	}
	collectEvidenceNumbers(evidence, allowed)
	if len(allowed) == 0 {
		// No numeric claims to check — accept non-empty polish.
		return strings.TrimSpace(polished) != ""
	}

	polishedNums := numberToken.FindAllString(polished, -1)
	for _, n := range polishedNums {
		if !allowed[canonicalizeNumber(n)] {
			return false // fabricated
		}
	}

	// At least one key evidence number must still appear when evidence has keys.
	keys := []string{"total_revenue", "total_net_value", "total_units_sold", "total_units", "record_count", "active_stores_count"}
	required := map[string]bool{}
	for _, k := range keys {
		if v, ok := evidence[k]; ok {
			for _, n := range numbersFromValue(v) {
				required[canonicalizeNumber(n)] = true
			}
		}
	}
	if len(required) == 0 {
		return true
	}
	seen := map[string]bool{}
	for _, n := range polishedNums {
		seen[canonicalizeNumber(n)] = true
	}
	for n := range required {
		if seen[n] {
			return true
		}
	}
	return false
}

func collectEvidenceNumbers(v interface{}, into map[string]bool) {
	switch x := v.(type) {
	case map[string]interface{}:
		for _, child := range x {
			collectEvidenceNumbers(child, into)
		}
	case []interface{}:
		for _, child := range x {
			collectEvidenceNumbers(child, into)
		}
	case []map[string]interface{}:
		for _, child := range x {
			collectEvidenceNumbers(child, into)
		}
	default:
		for _, n := range numbersFromValue(x) {
			into[canonicalizeNumber(n)] = true
		}
	}
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
		// Collapse 120000.00 and 120000.
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

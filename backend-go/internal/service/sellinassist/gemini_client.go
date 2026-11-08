package sellinassist

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultGeminiBase = "https://generativelanguage.googleapis.com"

// jsonCaller is injectable for tests (model, prompt) → raw JSON text.
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
	ResponseMimeType string      `json:"responseMimeType,omitempty"`
	ResponseSchema   interface{} `json:"responseSchema,omitempty"`
	Temperature      float64     `json:"temperature"`
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

type layoutAIResponse struct {
	HeaderRowIndex int          `json:"header_row_index"`
	Layout         string       `json:"layout"`
	Confidence     float64      `json:"confidence"`
	ReasonAR       string       `json:"reason_ar"`
	MissingRoles   []string     `json:"missing_roles"`
	Columns        []ColumnRole `json:"columns"`
}

func redactKey(msg, apiKey string) string {
	if apiKey == "" {
		return msg
	}
	return strings.ReplaceAll(msg, apiKey, "[REDACTED]")
}

func (s *Service) callGeminiJSON(ctx context.Context, model, prompt, schemaJSON, filename string) (string, error) {
	started := time.Now()
	var schemaObj interface{}
	if err := json.Unmarshal([]byte(schemaJSON), &schemaObj); err != nil {
		return "", err
	}
	body, err := json.Marshal(geminiRequest{
		Contents: []geminiContent{{Role: "user", Parts: []geminiPart{{Text: prompt}}}},
		GenerationConfig: &geminiGenerationConfig{
			ResponseMimeType: "application/json",
			ResponseSchema:   schemaObj,
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
		safe := fmt.Errorf("gemini sell-in assist failed: %s", redactKey(err.Error(), s.apiKey))
		logAssistCall(filename, model, started, false, safe)
		return "", safe
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, resp.Body)
		callErr := fmt.Errorf("gemini sell-in assist status %d", resp.StatusCode)
		logAssistCall(filename, model, started, false, callErr)
		return "", callErr
	}
	var gr geminiResponse
	if err := json.NewDecoder(resp.Body).Decode(&gr); err != nil {
		logAssistCall(filename, model, started, false, err)
		return "", err
	}
	if len(gr.Candidates) == 0 || len(gr.Candidates[0].Content.Parts) == 0 {
		callErr := fmt.Errorf("gemini sell-in assist returned no candidates")
		logAssistCall(filename, model, started, false, callErr)
		return "", callErr
	}
	logAssistCall(filename, model, started, true, nil)
	return gr.Candidates[0].Content.Parts[0].Text, nil
}

func logAssistCall(filename, model string, started time.Time, ok bool, err error) {
	status := "ok"
	errMsg := ""
	if !ok {
		status = "fail"
		if err != nil {
			errMsg = err.Error()
		}
	}
	log.Printf("[sellin-assist-ai-call] file=%q model=%s latency_ms=%d status=%s err=%s",
		filename, model, time.Since(started).Milliseconds(), status, errMsg)
}

func isProduction() bool {
	return strings.EqualFold(strings.TrimSpace(os.Getenv("ENVIRONMENT")), "production")
}

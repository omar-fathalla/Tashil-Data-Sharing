package monthlysummary

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const defaultGeminiBase = "https://generativelanguage.googleapis.com"

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
	Temperature float64 `json:"temperature"`
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

// NewGeminiGenerator returns a TextGenerator that calls Gemini generateContent.
// apiKey empty → returns nil (caller should use deterministic path).
func NewGeminiGenerator(apiKey, apiBase string, httpClient *http.Client) TextGenerator {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return nil
	}
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 45 * time.Second}
	}
	base := strings.TrimRight(strings.TrimSpace(apiBase), "/")
	if base == "" {
		base = defaultGeminiBase
	}
	return func(ctx context.Context, model, prompt string) (string, error) {
		model = strings.TrimSpace(model)
		if model == "" {
			return "", fmt.Errorf("monthlysummary: empty gemini model")
		}
		body, err := json.Marshal(geminiRequest{
			Contents: []geminiContent{{Role: "user", Parts: []geminiPart{{Text: prompt}}}},
			GenerationConfig: &geminiGenerationConfig{
				Temperature: 0.2,
			},
		})
		if err != nil {
			return "", err
		}
		endpoint := fmt.Sprintf("%s/v1beta/models/%s:generateContent", base, model)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
		if err != nil {
			return "", err
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("x-goog-api-key", apiKey)
		resp, err := httpClient.Do(req)
		if err != nil {
			return "", fmt.Errorf("monthlysummary gemini: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			_, _ = io.Copy(io.Discard, resp.Body)
			return "", fmt.Errorf("monthlysummary gemini status %d", resp.StatusCode)
		}
		var gr geminiResponse
		if err := json.NewDecoder(resp.Body).Decode(&gr); err != nil {
			return "", err
		}
		if len(gr.Candidates) == 0 || len(gr.Candidates[0].Content.Parts) == 0 {
			return "", fmt.Errorf("monthlysummary gemini: no candidates")
		}
		return gr.Candidates[0].Content.Parts[0].Text, nil
	}
}

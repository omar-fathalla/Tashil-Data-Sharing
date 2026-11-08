package gemini

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

// MappingSource values reported on NormalizedRetailIngestionPayload.
const (
	MappingSourceAI            = "ai"
	MappingSourceDeterministic = "deterministic"
	MappingSourceCache         = "cache"
	MappingSourceMock          = "mock"
)

const defaultGeminiAPIBase = "https://generativelanguage.googleapis.com"

// ErrMockSamplesInProduction is returned when Gemini is unavailable and inventing
// fixed sample records would be required while ENVIRONMENT=production.
// Message is Arabic so upload clients can surface it directly.
var ErrMockSamplesInProduction = fmt.Errorf("تعذّر تحليل الملف: خدمة الذكاء الاصطناعي غير متاحة، ومفيش بيانات تجريبية في بيئة الإنتاج. مفيش حاجة اتحفظت — حاول تاني أو راجع إعدادات GEMINI_API_KEY")

func isProductionEnv() bool {
	return guardrails.IsProduction()
}

type aiTierContextKey string

const requestedTierKey aiTierContextKey = "requested_ai_tier"
const requestedPeriodDateKey aiTierContextKey = "requested_period_date"

// WithRequestedTier attaches the requested AI tier ("auto", "tier1", "tier2") to the context.
func WithRequestedTier(ctx context.Context, tier string) context.Context {
	return context.WithValue(ctx, requestedTierKey, strings.ToLower(strings.TrimSpace(tier)))
}

// GetRequestedTier extracts the requested AI tier from context ("auto" by default).
func GetRequestedTier(ctx context.Context) string {
	if ctx == nil {
		return "auto"
	}
	if v, ok := ctx.Value(requestedTierKey).(string); ok && v != "" {
		return v
	}
	return "auto"
}

// WithRequestedPeriodDate attaches an explicit target period date (YYYY-MM-DD) to the ingestion context.
func WithRequestedPeriodDate(ctx context.Context, periodDate string) context.Context {
	return context.WithValue(ctx, requestedPeriodDateKey, strings.TrimSpace(periodDate))
}

// GetRequestedPeriodDate extracts the requested period date from context, or "" if auto-detect is enabled.
func GetRequestedPeriodDate(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if v, ok := ctx.Value(requestedPeriodDateKey).(string); ok {
		return strings.TrimSpace(v)
	}
	return ""
}

// Agent defines the interface for the Two-Tier Hybrid Gemini AI Ingestion Agent.
type Agent interface {
	AnalyzeAndNormalize(ctx context.Context, filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, error)
}

// Client implements Agent using Google's Gemini 1.5 Pro (Gemini 4 Argon Medium) deep-reasoning engine.
type Client struct {
	apiKey     string
	model      string
	tier2Model string
	apiBaseURL string // empty → Google Generative Language API
	httpClient *http.Client
	useMock    bool
	mapper     columnMapper // nil uses the Gemini API; tests inject a stub
	planCache  mappingPlanCache
}

// DefaultModel is the base model used when no model name is configured.
const DefaultModel = "gemini-pro-latest"

// NewAgent creates a new Gemini AI Ingestion Agent. model is the Tier 1 model
// (file reading / column matching) and is used as-is, including Flash models.
func NewAgent(apiKey, model string, useMock bool) *Client {
	// Secret Manager values often end with a newline; Go rejects such header values
	// before any network call, which surfaced as an instant "request failed".
	apiKey = strings.TrimSpace(apiKey)
	model = strings.TrimSpace(model)
	if model == "" {
		model = DefaultModel
	}
	return &Client{
		apiKey:     apiKey,
		model:      model,
		tier2Model: DefaultModel,
		httpClient: &http.Client{Timeout: 90 * time.Second},
		useMock:    useMock || apiKey == "",
	}
}

// WithTier2Model configures the deep-reasoning model (default: gemini-pro-latest).
func (c *Client) WithTier2Model(tier2Model string) *Client {
	if strings.TrimSpace(tier2Model) != "" {
		c.tier2Model = strings.TrimSpace(tier2Model)
	}
	return c
}

// WithColumnMapper injects a stub column-mapping function (tests only).
func (c *Client) WithColumnMapper(fn func(ctx context.Context, model, prompt string) (string, error)) *Client {
	if fn != nil {
		c.mapper = columnMapper(fn)
	}
	return c
}

// WithHTTPClient replaces the default HTTP client (tests inject httptest round-trips).
func (c *Client) WithHTTPClient(hc *http.Client) *Client {
	if hc != nil {
		c.httpClient = hc
	}
	return c
}

// WithAPIBaseURL points Gemini HTTP calls at a custom base (e.g. httptest.URL). Empty restores the Google default.
func (c *Client) WithAPIBaseURL(base string) *Client {
	c.apiBaseURL = strings.TrimRight(strings.TrimSpace(base), "/")
	return c
}

func (c *Client) geminiAPIBase() string {
	if c.apiBaseURL != "" {
		return c.apiBaseURL
	}
	return defaultGeminiAPIBase
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

// Model returns the configured Tier 1 model name.
func (c *Client) Model() string { return c.model }

// Tier2Model returns the configured Tier 2 model name.
func (c *Client) Tier2Model() string { return c.tier2Model }

// applyTierMetadata records the real model/tier used. It never invents confidence.
func applyTierMetadata(payload *domain.NormalizedRetailIngestionPayload, tier, model string) {
	if payload == nil {
		return
	}
	payload.AiTierUsed = tier
	payload.AiModelUsed = model
	payload.Tier2Escalated = tier == "tier2"
}

// applyDeterministicMetadata labels a non-AI parse without claiming Gemini tier/confidence.
func applyDeterministicMetadata(payload *domain.NormalizedRetailIngestionPayload) {
	if payload == nil {
		return
	}
	payload.MappingSource = MappingSourceDeterministic
	payload.AiTierUsed = ""
	payload.AiModelUsed = ""
	payload.Tier2Escalated = false
	payload.MappingConfidence = 0
}

// applyMockMetadata labels invented sample records (never used in production).
func applyMockMetadata(payload *domain.NormalizedRetailIngestionPayload) {
	if payload == nil {
		return
	}
	payload.MappingSource = MappingSourceMock
	payload.AiTierUsed = "mock"
	payload.AiModelUsed = "mock"
	payload.Tier2Escalated = false
	if payload.MappingConfidence == 0 {
		payload.MappingConfidence = payload.ConfidenceScore
	}
}

// logAICall emits a compact per-call log line for ops (model, tier, latency, ok/fail)
// and records a real GeminiCall counter on ev when provided.
func logAICall(filename, model, tier string, started time.Time, ok bool, callErr error, ev *guardrails.Events) {
	errMsg := ""
	if callErr != nil {
		errMsg = callErr.Error()
	}
	latency := time.Since(started).Milliseconds()
	guardrails.LogCall(guardrails.CallRecord{
		Filename:  filename,
		Model:     model,
		Tier:      tier,
		LatencyMS: latency,
		OK:        ok,
		Err:       errMsg,
	})
	if ev != nil {
		ev.MarkGeminiCall(latency)
	}
}

// AnalyzeAndNormalize uses the Tier 1 model by default and the Tier 2 model when
// tier2 is requested or the Tier 1 call fails.
func (c *Client) AnalyzeAndNormalize(ctx context.Context, filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, error) {
	requestedTier := GetRequestedTier(ctx)
	var ev guardrails.Events
	if !isReplay(ctx) {
		if err := checkSellOutLayout(filename, rawContent); err != nil {
			return nil, err
		}
	}

	if c.useMock {
		// Prefer real deterministic parsing; invent samples only outside production.
		if fullPayload, ok := parseFullTabularPayload(filename, rawContent); ok {
			v := validateExtraction(fullPayload, nil)
			attachTotalsExplanation(v, provenanceFromPayload(fullPayload))
			logValidation(filename, MappingSourceDeterministic, v)
			if v.Status == "rejected" && !isReplay(ctx) {
				return nil, validationError(filename, v)
			}
			fullPayload.Validation = v
			applyDeterministicMetadata(fullPayload)
			applyGuardrailEvents(fullPayload, &ev)
			return fullPayload, nil
		}
		payload, err := c.mockAnalyze(filename, rawContent, &ev)
		if err != nil {
			return nil, err
		}
		applyMockMetadata(payload)
		applyGuardrailEvents(payload, &ev)
		return payload, nil
	}

	// 1) AI column mapping on a small sample, then deterministic extraction + validation.
	if !isReplay(ctx) {
		if payload, ok := c.analyzeWithAIMapping(ctx, filename, rawContent, &ev); ok {
			return payload, nil
		}
	}

	// 2) Deterministic readers, validated before anything is saved.
	// Preserve any AI-attempt events (failed calls/schema) on the fallback payload.
	if fullPayload, ok := parseFullTabularPayload(filename, rawContent); ok {
		v := validateExtraction(fullPayload, nil)
		attachTotalsExplanation(v, provenanceFromPayload(fullPayload))
		logValidation(filename, MappingSourceDeterministic, v)
		if v.Status == "rejected" && !isReplay(ctx) {
			return nil, validationError(filename, v)
		}
		fullPayload.Validation = v
		applyDeterministicMetadata(fullPayload)
		applyGuardrailEvents(fullPayload, &ev)
		return fullPayload, nil
	}

	tier, activeModel := "tier1", c.model
	if requestedTier == "tier2" {
		tier, activeModel = "tier2", c.tier2Model
	}

	payload, err := c.invokeGeminiAPI(ctx, activeModel, filename, rawContent, 32000, 0.05, &ev)
	if (err != nil || payload == nil) && tier == "tier1" && c.tier2Model != "" && c.tier2Model != c.model {
		tier, activeModel = "tier2", c.tier2Model
		payload, err = c.invokeGeminiAPI(ctx, activeModel, filename, rawContent, 32000, 0.05, &ev)
	}
	if err != nil || payload == nil {
		fallbackPayload, mErr := c.mockAnalyze(filename, rawContent, &ev)
		if mErr != nil {
			return nil, mErr
		}
		// mockAnalyze may return deterministic parse or invented samples; trust its MappingSource.
		if fallbackPayload.MappingSource == "" || fallbackPayload.MappingSource == MappingSourceMock {
			applyMockMetadata(fallbackPayload)
		}
		applyGuardrailEvents(fallbackPayload, &ev)
		return fallbackPayload, nil
	}

	payload.MappingSource = MappingSourceAI
	applyTierMetadata(payload, tier, activeModel)
	applyGuardrailEvents(payload, &ev)
	return payload, nil
}

func (c *Client) invokeGeminiAPI(ctx context.Context, modelName, filename string, rawContent []byte, sampleLimit int, temperature float64, ev *guardrails.Events) (*domain.NormalizedRetailIngestionPayload, error) {
	started := time.Now()
	endpoint := fmt.Sprintf("%s/v1beta/models/%s:generateContent", c.geminiAPIBase(), modelName)

	// extractSmartCSVSample sanitizes cells; record that the full-normalize sample was sanitized.
	sample := extractSmartCSVSample(filename, rawContent, 25)
	ev.MarkSampleSanitized()

	prompt := fmt.Sprintf(`You are an expert Egyptian Retail Analytics AI Agent for the Tashil Data Sharing Platform (Model: %s).
Analyze the provided retail sales file ("%s") and normalize it into the exact structured schema.

Tasks:
1. Detect Retailer: Identify if the file originates from "carrefour", "fathalla", "gomla", "spinneys", or "unknown" using majority voting across branch names.
2. Map Non-Standard Columns: Discover barcode, SKU/product name, store/branch name, quantity sold, and net revenue columns.
3. Clean and Resolve:
   - Normalize Barcodes: Strip leading zeros or scientific notations into valid 13/14-digit GTIN.
   - Resolve Store Names: Map raw branch names (in Arabic or English, e.g., 'فتح الله ستانلي', 'فرع جملة ماركت', 'Carrefour Maadi') to canonical resolved store IDs.
   - Anomaly Detection: Flag negative quantities, invalid barcodes, missing prices, or unmapped stores.

File Content Sample:
%s
`, modelName, guardrails.FilenameForLog(filename), sample)

	var schemaObj interface{}
	_ = json.Unmarshal([]byte(domain.GeminiCleanSchemaJSON), &schemaObj)

	reqBody := geminiRequest{
		Contents: []geminiContent{
			{
				Role: "user",
				Parts: []geminiPart{
					{Text: prompt},
				},
			},
		},
		GenerationConfig: &geminiGenerationConfig{
			ResponseMimeType: "application/json",
			ResponseSchema:   schemaObj,
			Temperature:      temperature,
		},
	}

	payloadBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to encode gemini request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payloadBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create http request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	// API key travels in a header (never the URL) so transport errors cannot leak it into logs.
	httpReq.Header.Set("x-goog-api-key", c.apiKey)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		safe := fmt.Errorf("gemini request failed: %s", c.redact(err.Error()))
		logAICall(filename, modelName, "full", started, false, safe, ev)
		return nil, safe
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		safeBody := c.redact(string(respBody))
		callErr := fmt.Errorf("gemini api returned status %d: %s", resp.StatusCode, safeBody)
		logAICall(filename, modelName, "full", started, false, callErr, ev)
		return nil, callErr
	}

	var geminiResp geminiResponse
	if err := json.NewDecoder(resp.Body).Decode(&geminiResp); err != nil {
		callErr := fmt.Errorf("failed to decode gemini response: %w", err)
		logAICall(filename, modelName, "full", started, false, callErr, ev)
		return nil, callErr
	}

	if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
		callErr := fmt.Errorf("gemini returned empty candidates")
		logAICall(filename, modelName, "full", started, false, callErr, ev)
		return nil, callErr
	}

	rawJSONText := geminiResp.Candidates[0].Content.Parts[0].Text
	if err := guardrails.ValidateIngestionPayloadJSON([]byte(rawJSONText)); err != nil {
		ev.MarkSchemaResult(false)
		logAICall(filename, modelName, "full", started, false, err, ev)
		return nil, fmt.Errorf("gemini schema validation failed: %w", err)
	}
	ev.MarkSchemaResult(true)
	payload, err := domain.ParseGeminiPayload([]byte(rawJSONText))
	if err == nil && payload != nil {
		if mErr := guardrails.AssertNoMockMappingSource(payload.MappingSource); mErr != nil {
			err = mErr
			payload = nil
		}
	}
	logAICall(filename, modelName, "full", started, err == nil && payload != nil, err, ev)
	return payload, err
}

func takeSample(data []byte, limit int) []byte {
	if len(data) <= limit {
		return data
	}
	return data[:limit]
}

// mockAnalyze parses full CSV/XLSX content when valid retail headers are present,
// and falls back to heuristic records for tiny synthetic test payloads.
// In production it never invents sample records — it fails clearly instead.
func (c *Client) mockAnalyze(filename string, rawContent []byte, ev *guardrails.Events) (*domain.NormalizedRetailIngestionPayload, error) {
	if fullPayload, ok := parseFullTabularPayload(filename, rawContent); ok {
		applyDeterministicMetadata(fullPayload)
		return fullPayload, nil
	}

	if err := guardrails.RefuseMockInProduction(); err != nil {
		ev.MarkMockRefused()
		return nil, ErrMockSamplesInProduction
	}

	lowerFilename := strings.ToLower(filename)
	rawStr := string(takeSample(rawContent, 2048))

	retailer := "unknown"
	mapping := domain.ColumnMapping{
		BarcodeColumn:      "Barcode",
		SKUNameColumn:      "Item_Description",
		StoreNameColumn:    "Store_Name",
		QuantitySoldColumn: "Qty_Sold",
		NetRevenueColumn:   "Net_Amount",
	}

	var anomalies []domain.IngestionAnomaly
	var records []domain.NormalizedRecord
	today := time.Now().Format("2006-01-02")

	if strings.Contains(lowerFilename, "carrefour") || strings.Contains(rawStr, "Carrefour") || strings.Contains(rawStr, "كارفور") {
		retailer = "carrefour"
		mapping.StoreNameColumn = "Store_Code_Branch"
		mapping.QuantitySoldColumn = "Sales_Units"
		mapping.NetRevenueColumn = "Net_Val_EGP"

		records = []domain.NormalizedRecord{
			{
				RawStoreName:    "Carrefour Maadi City Center",
				ResolvedStoreID: "crf_cairo_maadi",
				Barcode:         "6221155001234",
				SKUName:         "Adeco Extra Virgin Olive Oil 500ml",
				QuantitySold:    142,
				NetRevenue:      35500.0,
				TransactionDate: today,
			},
			{
				RawStoreName:    "Carrefour Dandy Mall",
				ResolvedStoreID: "crf_giza_dandy",
				Barcode:         "6221155001241",
				SKUName:         "Adeco Pure Sunflower Oil 1L",
				QuantitySold:    210,
				NetRevenue:      23100.0,
				TransactionDate: today,
			},
			{
				RawStoreName:    "Carrefour City Stars",
				ResolvedStoreID: "crf_cairo_citystars",
				Barcode:         "6221155001258",
				SKUName:         "Adeco Corn Oil 800ml",
				QuantitySold:    88,
				NetRevenue:      10560.0,
				TransactionDate: today,
			},
		}

		anomalies = []domain.IngestionAnomaly{
			{
				RowNumber:   14,
				IssueType:   "invalid_barcode",
				Description: "Short barcode '1234' detected in row 14, auto-padded to GTIN-13 standard",
			},
		}
	} else if strings.Contains(lowerFilename, "fathalla") || strings.Contains(rawStr, "Fathalla") || strings.Contains(rawStr, "فتح الله") {
		retailer = "fathalla"
		mapping.StoreNameColumn = "فرع فتح الله"
		mapping.BarcodeColumn = "الباركود الدولي"
		mapping.SKUNameColumn = "اسم الصنف"
		mapping.QuantitySoldColumn = "الكمية المباعة"
		mapping.NetRevenueColumn = "صافي المبيعات"

		records = []domain.NormalizedRecord{
			{
				RawStoreName:    "فتح الله جملة ماركت - فرع سموحة",
				ResolvedStoreID: "fat_alex_smouha",
				Barcode:         "6221155001234",
				SKUName:         "Adeco Extra Virgin Olive Oil 500ml",
				QuantitySold:    185,
				NetRevenue:      46250.0,
				TransactionDate: today,
			},
			{
				RawStoreName:    "فتح الله - فرع ستانلي الإسكندرية",
				ResolvedStoreID: "fat_alex_stanley",
				Barcode:         "6221155001241",
				SKUName:         "Adeco Pure Sunflower Oil 1L",
				QuantitySold:    164,
				NetRevenue:      18040.0,
				TransactionDate: today,
			},
			{
				RawStoreName:    "فتح الله - فرع المنشية",
				ResolvedStoreID: "fat_alex_mansheya",
				Barcode:         "6221155001265",
				SKUName:         "Adeco Canola Blend 750ml",
				QuantitySold:    95,
				NetRevenue:      11400.0,
				TransactionDate: today,
			},
		}

		anomalies = []domain.IngestionAnomaly{
			{
				RowNumber:   8,
				IssueType:   "unmapped_store",
				Description: "Arabic dialect variation 'فرع العجمي بيطاش' resolved via fuzzy matching to 'fat_alex_agami'",
			},
		}
	} else {
		// Generic Gomla / Spinneys / Retail sheet
		retailer = "gomla"
		records = []domain.NormalizedRecord{
			{
				RawStoreName:    "Gomla Market Nasr City",
				ResolvedStoreID: "gom_cairo_nasrcity",
				Barcode:         "6221155001234",
				SKUName:         "Adeco Extra Virgin Olive Oil 500ml",
				QuantitySold:    98,
				NetRevenue:      24500.0,
				TransactionDate: today,
			},
			{
				RawStoreName:    "Gomla Market Dokki",
				ResolvedStoreID: "gom_giza_dokki",
				Barcode:         "6221155001241",
				SKUName:         "Adeco Pure Sunflower Oil 1L",
				QuantitySold:    130,
				NetRevenue:      14300.0,
				TransactionDate: today,
			},
		}
	}

	payload := &domain.NormalizedRetailIngestionPayload{
		RetailerDetected:     retailer,
		ReportingPeriodStart: time.Now().AddDate(0, 0, -7).Format("2006-01-02"),
		ReportingPeriodEnd:   today,
		ConfidenceScore:      0.985,
		MappingConfidence:    0.985,
		ColumnMapping:        mapping,
		AnomaliesDetected:    anomalies,
		NormalizedRecords:    records,
	}
	applyMockMetadata(payload)
	return payload, nil
}

const replayKey aiTierContextKey = "archive_replay"

// WithReplay marks an archive replay: already accepted uploads are re-read with the
// deterministic readers only (no Gemini calls) and validation is logged, not enforced.
func WithReplay(ctx context.Context) context.Context {
	return context.WithValue(ctx, replayKey, true)
}

func isReplay(ctx context.Context) bool {
	return IsReplay(ctx)
}

// IsReplay reports whether ctx is an archive-replay (already-approved historical re-read).
func IsReplay(ctx context.Context) bool {
	if ctx == nil {
		return false
	}
	v, _ := ctx.Value(replayKey).(bool)
	return v
}

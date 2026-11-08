package gemini

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// mappingSampleRows is the maximum number of leading rows sent to Gemini for column mapping.
// Only this sample is ever sent; the AI never sees (or produces) the full data.
const mappingSampleRows = 15

// minMappingConfidence is the lowest AI mapping confidence accepted before falling back.
const minMappingConfidence = 0.7

// ErrUploadValidation marks an upload that failed the pre-save totals check.
var ErrUploadValidation = errors.New("upload validation failed")

// ColumnRole is the semantic role Gemini assigns to one column.
type ColumnRole struct {
	Index  int    `json:"index"`
	Role   string `json:"role"`
	Branch string `json:"branch,omitempty"`
}

// ColumnMapPlan is the structured mapping Gemini returns for a sheet sample.
type ColumnMapPlan struct {
	HeaderRowIndex int          `json:"header_row_index"`
	SkipRows       []int        `json:"skip_rows,omitempty"`
	Layout         string       `json:"layout"` // "wide" or "long"
	Columns        []ColumnRole `json:"columns"`
	Confidence     float64      `json:"confidence"`
}

// Supported column roles.
const (
	roleBarcode       = "barcode"
	roleProductName   = "product_name"
	roleCategory      = "category"
	roleSupplier      = "supplier"
	roleStore         = "store"
	roleStoreValue    = "store_value"
	roleStoreQuantity = "store_quantity"
	roleQuantity      = "quantity"
	roleValue         = "value"
	roleReturn        = "return"
	roleMonth         = "month"
	roleYear          = "year"
	roleDate          = "date"
	roleTotalValue    = "total_value"
	roleTotalQuantity = "total_quantity"
	roleIgnore        = "ignore"
)

const columnMapSchemaJSON = `{"type":"OBJECT","properties":{
"header_row_index":{"type":"INTEGER"},
"skip_rows":{"type":"ARRAY","items":{"type":"INTEGER"}},
"layout":{"type":"STRING","enum":["wide","long"]},
"confidence":{"type":"NUMBER"},
"columns":{"type":"ARRAY","items":{"type":"OBJECT","properties":{
"index":{"type":"INTEGER"},
"role":{"type":"STRING","enum":["barcode","product_name","category","supplier","store","store_value","store_quantity","quantity","value","return","month","year","date","total_value","total_quantity","ignore"]},
"branch":{"type":"STRING"}},"required":["index","role"]}}},
"required":["header_row_index","layout","columns","confidence"]}`

// columnMapper sends a mapping prompt to a model and returns the raw JSON text.
type columnMapper func(ctx context.Context, model, prompt string) (string, error)

func buildColumnMapPrompt(filename string, sample [][]string) string {
	var b strings.Builder
	b.WriteString(`You map the columns of an Egyptian retail sell-out spreadsheet. You see only the first rows.
Return JSON only. Rows and columns are 0-based.
- header_row_index: the row holding column headers (title rows or blank rows may come first).
- skip_rows: rows above or around the header that are not data.
- layout: "wide" when each branch/store has its own value column and quantity column; "long" when one row = one store/item line.
- columns: a role per column. Wide layout: per-branch money columns are "store_value" and per-branch quantity columns are "store_quantity", each with "branch" set to the branch name (same spelling for its value and quantity pair). Sheet total columns are "total_value"/"total_quantity". Long layout: "store", "quantity", "value", "return".
- Use "month", "year", "date" for period columns (month cells may be codes like jan, seb, aug). Anything else is "ignore".
- confidence: 0..1.
File: ` + filename + "\nRows:\n")
	for i, r := range sample {
		cells := make([]string, len(r))
		for j, c := range r {
			c = strings.TrimSpace(c)
			if len([]rune(c)) > 40 {
				c = string([]rune(c)[:40])
			}
			cells[j] = fmt.Sprintf("%d:%s", j, c)
		}
		fmt.Fprintf(&b, "row %d | %s\n", i, strings.Join(cells, " | "))
	}
	return b.String()
}

// callGeminiForMapping is the default columnMapper. The API key travels in a header
// (never the URL) so transport errors cannot leak it into logs.
func (c *Client) callGeminiForMapping(ctx context.Context, model, prompt, filename string) (string, error) {
	started := time.Now()
	var schemaObj interface{}
	_ = json.Unmarshal([]byte(columnMapSchemaJSON), &schemaObj)
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
	endpoint := fmt.Sprintf("%s/v1beta/models/%s:generateContent", c.geminiAPIBase(), model)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-goog-api-key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil {
		safe := fmt.Errorf("gemini mapping request failed: %s", c.redact(err.Error()))
		logAICall(filename, model, "mapping", started, false, safe)
		return "", safe
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, resp.Body)
		callErr := fmt.Errorf("gemini mapping returned status %d", resp.StatusCode)
		logAICall(filename, model, "mapping", started, false, callErr)
		return "", callErr
	}
	var gr geminiResponse
	if err := json.NewDecoder(resp.Body).Decode(&gr); err != nil {
		logAICall(filename, model, "mapping", started, false, err)
		return "", err
	}
	if len(gr.Candidates) == 0 || len(gr.Candidates[0].Content.Parts) == 0 {
		callErr := fmt.Errorf("gemini mapping returned no candidates")
		logAICall(filename, model, "mapping", started, false, callErr)
		return "", callErr
	}
	logAICall(filename, model, "mapping", started, true, nil)
	return gr.Candidates[0].Content.Parts[0].Text, nil
}

// inferColumnMapping asks the Tier 1 model for a mapping and escalates to Tier 2 on error,
// invalid JSON or low confidence.
func (c *Client) inferColumnMapping(ctx context.Context, filename string, sample [][]string) (*ColumnMapPlan, string, string, error) {
	mapper := c.mapper
	if mapper == nil {
		mapper = func(ctx context.Context, model, prompt string) (string, error) {
			return c.callGeminiForMapping(ctx, model, prompt, filename)
		}
	}
	prompt := buildColumnMapPrompt(filename, sample)
	key := mappingPlanKey(prompt)
	if plan, ok := c.planCache.get(key); ok && plan.check(sample) == nil {
		log.Printf("[ingest-mapping] file=%q reusing stored mapping plan (no Gemini call)", filename)
		return plan, MappingSourceCache, "stored-plan", nil
	}
	type attempt struct{ tier, model string }
	attempts := []attempt{{"tier1", c.model}}
	if GetRequestedTier(ctx) == "tier2" {
		attempts = nil
	}
	if c.tier2Model != "" && (len(attempts) == 0 || c.tier2Model != c.model) {
		attempts = append(attempts, attempt{"tier2", c.tier2Model})
	}
	var lastErr error
	for _, a := range attempts {
		text, err := mapper(ctx, a.model, prompt)
		if err != nil {
			lastErr = err
			log.Printf("[ingest-mapping] file=%q tier=%s model=%s error=%v", filename, a.tier, a.model, err)
			continue
		}
		plan := &ColumnMapPlan{}
		if err := json.Unmarshal([]byte(text), plan); err != nil {
			lastErr = fmt.Errorf("invalid mapping json: %w", err)
			continue
		}
		if err := plan.check(sample); err != nil {
			lastErr = err
			log.Printf("[ingest-mapping] file=%q tier=%s model=%s rejected plan: %v", filename, a.tier, a.model, err)
			continue
		}
		if plan.Confidence < minMappingConfidence {
			lastErr = fmt.Errorf("low mapping confidence %.2f", plan.Confidence)
			log.Printf("[ingest-mapping] file=%q tier=%s model=%s low confidence %.2f", filename, a.tier, a.model, plan.Confidence)
			continue
		}
		c.planCache.put(key, plan)
		return plan, a.tier, a.model, nil
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no mapping model configured")
	}
	return nil, "", "", lastErr
}

func (p *ColumnMapPlan) rolesOf(role string) []ColumnRole {
	var out []ColumnRole
	for _, c := range p.Columns {
		if c.Role == role {
			out = append(out, c)
		}
	}
	return out
}

func (p *ColumnMapPlan) firstIdx(role string) int {
	for _, c := range p.Columns {
		if c.Role == role {
			return c.Index
		}
	}
	return -1
}

// check rejects structurally impossible plans before any data is extracted.
func (p *ColumnMapPlan) check(sample [][]string) error {
	if p.HeaderRowIndex < 0 || p.HeaderRowIndex >= len(sample) {
		return fmt.Errorf("header row %d out of range", p.HeaderRowIndex)
	}
	width := len(sample[p.HeaderRowIndex])
	for _, c := range p.Columns {
		if c.Index < 0 || c.Index >= width {
			return fmt.Errorf("column %d out of range", c.Index)
		}
	}
	if p.firstIdx(roleBarcode) < 0 && p.firstIdx(roleProductName) < 0 {
		return fmt.Errorf("no barcode or product column")
	}
	switch p.Layout {
	case "wide":
		if len(p.rolesOf(roleStoreValue)) == 0 && len(p.rolesOf(roleStoreQuantity)) == 0 {
			return fmt.Errorf("wide layout without branch columns")
		}
	case "long":
		if p.firstIdx(roleQuantity) < 0 && p.firstIdx(roleValue) < 0 {
			return fmt.Errorf("long layout without quantity or value column")
		}
	default:
		return fmt.Errorf("unknown layout %q", p.Layout)
	}
	return nil
}

// readSingleSheetRows returns all rows of the only data sheet of an xlsx, or the CSV rows.
// Multi-sheet workbooks return ok=false and keep using the deterministic readers.
func readSingleSheetRows(rawContent []byte) ([][]string, bool) {
	if !isZipArchive(rawContent) {
		rows, err := parseCSVRows(rawContent)
		return rows, err == nil && len(rows) >= 2
	}
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return nil, false
	}
	var shared []string
	byName := make(map[string]*zip.File)
	for _, f := range zr.File {
		lower := strings.ToLower(f.Name)
		byName[lower] = f
		if lower == "xl/sharedstrings.xml" {
			shared = readSharedStringsXML(f)
		}
	}
	var dataRows [][]string
	sheets := 0
	for _, e := range listOrderedWorkbookSheets(zr, byName) {
		rows, err := readWorksheetXML(e.file, shared)
		if err != nil || len(rows) < 2 {
			continue
		}
		sheets++
		dataRows = rows
	}
	return dataRows, sheets == 1
}

// mappingSourceTotals are sums taken directly from the mapped source cells.
type mappingSourceTotals struct {
	units, value           float64 // positive mapped cells (the extraction rule)
	sheetUnits, sheetValue float64 // the sheet's own total columns, if any
	hasPeriodColumn        bool
}

// extractWithMapping deterministically builds the payload from the rows using the AI plan.
func extractWithMapping(filename string, rows [][]string, plan *ColumnMapPlan) (*domain.NormalizedRetailIngestionPayload, mappingSourceTotals, error) {
	var src mappingSourceTotals
	rows = rows[plan.HeaderRowIndex:]
	if len(rows) < 2 {
		return nil, src, fmt.Errorf("no data rows below header")
	}
	src.hasPeriodColumn = plan.firstIdx(roleMonth) >= 0 || plan.firstIdx(roleYear) >= 0 || plan.firstIdx(roleDate) >= 0
	sum := func(idx int, positiveOnly bool) float64 {
		var t float64
		if idx < 0 {
			return 0
		}
		for _, r := range rows[1:] {
			v := parseRevenueFloat(getCell(r, idx))
			if positiveOnly && v < 0 {
				continue
			}
			t += v
		}
		return t
	}
	src.sheetValue = sum(plan.firstIdx(roleTotalValue), false)
	src.sheetUnits = sum(plan.firstIdx(roleTotalQuantity), false)

	if plan.Layout == "wide" {
		layout := wideMatrixLayout{
			categoryIdx: plan.firstIdx(roleCategory),
			supplierIdx: plan.firstIdx(roleSupplier),
			barcodeIdx:  plan.firstIdx(roleBarcode),
			skuIdx:      plan.firstIdx(roleProductName),
			totalRevIdx: plan.firstIdx(roleTotalValue),
			monthIdx:    plan.firstIdx(roleMonth),
			yearIdx:     plan.firstIdx(roleYear),
			dateIdx:     plan.firstIdx(roleDate),
		}
		qtyByBranch := map[string]int{}
		var qtyOrder []int
		for _, c := range plan.rolesOf(roleStoreQuantity) {
			qtyByBranch[normalizeBranchKey(c.Branch)] = c.Index
			qtyOrder = append(qtyOrder, c.Index)
			src.units += sum(c.Index, true)
		}
		for i, c := range plan.rolesOf(roleStoreValue) {
			raw := strings.TrimSpace(c.Branch)
			if raw == "" {
				raw = strings.TrimSpace(getCell(rows[0], c.Index))
			}
			q, ok := qtyByBranch[normalizeBranchKey(raw)]
			if !ok {
				q = -1
				if i < len(qtyOrder) {
					q = qtyOrder[i]
				}
			}
			meta := BuildBranchStoreMetadata("fathalla", raw)
			layout.branches = append(layout.branches, branchColumnPair{rawBranchName: raw, storeID: meta.ID, displayName: meta.BranchName, revColIdx: c.Index, qtyColIdx: q})
			src.value += sum(c.Index, true)
		}
		if len(layout.branches) == 0 {
			return nil, src, fmt.Errorf("wide mapping has no branch value columns")
		}
		subs := splitWideSheetByRowPeriods(filename, "Sheet1", "visible", rows, layout)
		if len(subs) == 0 {
			fileYear := inferYearFromText(filename, 0)
			date := tryParseArabicSheetMonthDate(filename, fileYear)
			if date == "" {
				return nil, src, fmt.Errorf("no month detected")
			}
			one := parsedSheetSummary{sheetName: "Sheet1", sheetDate: date, state: "visible", rows: rows, layout: layout, isWide: true, storeCount: len(layout.branches)}
			computeQuickSheetTotals(&one)
			subs = []parsedSheetSummary{one}
			src.hasPeriodColumn = true
		}
		var entries []wbSheetEntry
		for _, s := range subs {
			entries = append(entries, wbSheetEntry{name: s.sheetName, state: "visible"})
		}
		payload, ok := buildPayloadFromWideMatrix(filename, subs[len(subs)-1], subs, subs, entries)
		if !ok {
			return nil, src, fmt.Errorf("wide extraction failed")
		}
		return payload, src, nil
	}

	// Long layout: rename the mapped headers to canonical names and reuse the deterministic tabular reader.
	canon := map[string]string{
		roleBarcode: "Barcode", roleProductName: "Item_Description", roleStore: "Store_Name",
		roleQuantity: "Qty_Sold", roleValue: "Net_Amount", roleMonth: "Month", roleYear: "Year",
		roleDate: "Date", roleCategory: "Category", roleSupplier: "Supplier",
	}
	header := make([]string, len(rows[0]))
	for i := range header {
		header[i] = fmt.Sprintf("col_%d", i)
	}
	for _, c := range plan.Columns {
		if name, ok := canon[c.Role]; ok {
			header[c.Index] = name
		}
	}
	src.units = sum(plan.firstIdx(roleQuantity), true)
	src.value = sum(plan.firstIdx(roleValue), true)
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	_ = w.Write(header)
	_ = w.WriteAll(rows[1:])
	payload, ok := parseFullTabularPayload(filename, buf.Bytes())
	if !ok {
		return nil, src, fmt.Errorf("long extraction failed")
	}
	return payload, src, nil
}

func relDiff(a, b float64) float64 {
	if b == 0 {
		if a == 0 {
			return 0
		}
		return 1
	}
	return math.Abs(a-b) / math.Abs(b)
}

// validateExtraction checks the extracted totals before anything is saved.
// src may be nil when the deterministic readers were used without an AI mapping.
func validateExtraction(payload *domain.NormalizedRetailIngestionPayload, src *mappingSourceTotals) *domain.IngestionValidation {
	v := &domain.IngestionValidation{Status: "ok", RecordCount: len(payload.NormalizedRecords)}
	months := map[string]bool{}
	for _, r := range payload.NormalizedRecords {
		v.ExtractedUnits += r.QuantitySold
		v.ExtractedValue += r.NetRevenue
		if len(r.TransactionDate) >= 7 {
			months[r.TransactionDate[:7]] = true
		}
	}
	for m := range months {
		v.MonthsDetected = append(v.MonthsDetected, m)
	}
	sort.Strings(v.MonthsDetected)
	reject := func(msg string) { v.Status = "rejected"; v.Issues = append(v.Issues, msg) }
	flag := func(msg string) {
		if v.Status == "ok" {
			v.Status = "flagged"
		}
		v.Issues = append(v.Issues, msg)
	}
	if v.RecordCount == 0 {
		reject("no records extracted")
		return v
	}
	// Small synthetic or sample uploads are not judged by the bulk heuristics.
	if v.RecordCount >= 20 {
		if v.ExtractedValue == 0 && v.ExtractedUnits == 0 {
			reject("all quantities and values are zero")
		} else if v.ExtractedValue == 0 && v.ExtractedUnits == v.RecordCount {
			reject("quantity equals the row count and value is zero: columns were not read")
		} else if v.ExtractedValue == 0 {
			flag("value total is zero")
		}
	}
	if src != nil {
		v.SourceUnits, v.SourceValue = src.units, src.value
		v.SheetTotalUnits, v.SheetTotalValue = src.sheetUnits, src.sheetValue
		if !src.hasPeriodColumn {
			reject("no month detected")
		}
		if src.value > 0 && relDiff(v.ExtractedValue, src.value) > 0.01 {
			reject(fmt.Sprintf("extracted value %.2f differs from source cells %.2f", v.ExtractedValue, src.value))
		}
		if src.units > 0 && relDiff(float64(v.ExtractedUnits), src.units) > 0.01 {
			reject(fmt.Sprintf("extracted units %d differ from source cells %.0f", v.ExtractedUnits, src.units))
		}
		for _, chk := range []struct {
			name      string
			got, want float64
		}{{"value", v.ExtractedValue, src.sheetValue}, {"units", float64(v.ExtractedUnits), src.sheetUnits}} {
			if chk.want == 0 {
				continue
			}
			d := relDiff(chk.got, chk.want)
			switch {
			case d > 0.10:
				reject(fmt.Sprintf("%s total %.2f is %.1f%% off the sheet total column %.2f", chk.name, chk.got, d*100, chk.want))
			case d > 0.01:
				flag(fmt.Sprintf("%s total %.2f is %.1f%% off the sheet total column %.2f", chk.name, chk.got, d*100, chk.want))
			}
		}
	}
	return v
}

// validationError builds the user-facing error for a rejected upload.
func validationError(filename string, v *domain.IngestionValidation) error {
	detail := ""
	if v != nil {
		detail = strings.Join(v.Issues, "; ")
		if ar := strings.TrimSpace(v.ExplanationAR); ar != "" {
			if detail != "" {
				detail = detail + " — " + ar
			} else {
				detail = ar
			}
		}
	}
	return fmt.Errorf("%w: تعذّر قراءة الملف %q بشكل صحيح ولم يتم حفظه (%s)", ErrUploadValidation, filename, detail)
}

func logValidation(filename, source string, v *domain.IngestionValidation) {
	log.Printf("[ingest-validation] file=%q source=%s status=%s records=%d units=%d value=%.2f source_units=%.0f source_value=%.2f sheet_units=%.0f sheet_value=%.2f months=%v issues=%v",
		filename, source, v.Status, v.RecordCount, v.ExtractedUnits, v.ExtractedValue, v.SourceUnits, v.SourceValue, v.SheetTotalUnits, v.SheetTotalValue, v.MonthsDetected, v.Issues)
}

// analyzeWithAIMapping runs the AI-mapping path. ok=false means fall back to the deterministic readers.
func (c *Client) analyzeWithAIMapping(ctx context.Context, filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, bool) {
	rows, single := readSingleSheetRows(rawContent)
	if !single {
		return nil, false
	}
	sample := rows
	if len(sample) > mappingSampleRows {
		sample = sample[:mappingSampleRows]
	}
	plan, tier, model, err := c.inferColumnMapping(ctx, filename, sample)
	if err != nil {
		log.Printf("[ingest-mapping] file=%q falling back to deterministic readers: %v", filename, err)
		return nil, false
	}
	planJSON, _ := json.Marshal(plan)
	log.Printf("[ingest-mapping] file=%q tier=%s model=%s confidence=%.2f plan=%s", filename, tier, model, plan.Confidence, planJSON)
	payload, src, err := extractWithMapping(filename, rows, plan)
	if err != nil {
		log.Printf("[ingest-mapping] file=%q extraction with AI mapping failed: %v", filename, err)
		return nil, false
	}
	v := validateExtraction(payload, &src)
	attachTotalsExplanation(v, provenanceFromPlan(rows, plan))
	logValidation(filename, "ai", v)
	if v.Status == "rejected" {
		return nil, false
	}
	payload.Validation = v
	if tier == MappingSourceCache {
		payload.MappingSource = MappingSourceCache
		payload.AiTierUsed = MappingSourceCache
		payload.AiModelUsed = model
		payload.Tier2Escalated = false
	} else {
		payload.MappingSource = MappingSourceAI
		payload.AiTierUsed, payload.AiModelUsed, payload.Tier2Escalated = tier, model, tier == "tier2"
	}
	payload.MappingConfidence = plan.Confidence
	payload.ConfidenceScore = plan.Confidence
	return payload, true
}

// redact strips the API key from an error string before it is logged.
func (c *Client) redact(msg string) string {
	if c.apiKey != "" {
		msg = strings.ReplaceAll(msg, c.apiKey, "[redacted]")
	}
	return msg
}

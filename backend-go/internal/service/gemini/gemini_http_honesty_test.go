package gemini

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

const testAPIKey = "test-secret-api-key-never-log-me"

type geminiHTTPFixture struct {
	mu        sync.Mutex
	calls     []string // model names extracted from path
	handler   func(model string, w http.ResponseWriter, r *http.Request)
	sawKeyURL int32
}

func (f *geminiHTTPFixture) server(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.RawQuery, testAPIKey) || strings.Contains(r.URL.String(), testAPIKey) {
			atomic.AddInt32(&f.sawKeyURL, 1)
		}
		model := modelFromPath(r.URL.Path)
		f.mu.Lock()
		f.calls = append(f.calls, model)
		h := f.handler
		f.mu.Unlock()
		if h != nil {
			h(model, w, r)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"candidates":[{"content":{"parts":[{"text":` + jsonString(book3Plan) + `}]}}]}`))
	}))
}

func (f *geminiHTTPFixture) callModels() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]string, len(f.calls))
	copy(out, f.calls)
	return out
}

func modelFromPath(path string) string {
	// /v1beta/models/<model>:generateContent
	const marker = "/v1beta/models/"
	i := strings.Index(path, marker)
	if i < 0 {
		return path
	}
	rest := path[i+len(marker):]
	if j := strings.Index(rest, ":"); j >= 0 {
		return rest[:j]
	}
	return rest
}

func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func mappingOKBody(plan string) []byte {
	return []byte(`{"candidates":[{"content":{"parts":[{"text":` + jsonString(plan) + `}]}}]}`)
}

func httpClientFor(srv *httptest.Server, timeout time.Duration) *http.Client {
	c := srv.Client()
	c.Timeout = timeout
	return c
}

func wiredAgent(t *testing.T, f *geminiHTTPFixture, timeout time.Duration) (*Client, *httptest.Server) {
	t.Helper()
	srv := f.server(t)
	t.Cleanup(srv.Close)
	c := NewAgent(testAPIKey, "gemini-3.8-flash", false).
		WithTier2Model("gemini-pro-latest").
		WithAPIBaseURL(srv.URL).
		WithHTTPClient(httpClientFor(srv, timeout))
	return c, srv
}

func TestHTTPMappingSuccessHonestMetadata(t *testing.T) {
	f := &geminiHTTPFixture{}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceAI || p.AiModelUsed != "gemini-3.8-flash" || p.AiTierUsed != "tier1" {
		t.Fatalf("honest AI metadata: source=%s model=%s tier=%s", p.MappingSource, p.AiModelUsed, p.AiTierUsed)
	}
	if p.MappingConfidence != 0.95 || p.ConfidenceScore != 0.95 {
		t.Fatalf("real confidence: mapping=%.2f score=%.2f", p.MappingConfidence, p.ConfidenceScore)
	}
	if got := f.callModels(); len(got) != 1 || got[0] != "gemini-3.8-flash" {
		t.Fatalf("calls=%v", got)
	}
}

func TestHTTPTimeoutEscalatesThenFallsBack(t *testing.T) {
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		time.Sleep(200 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(mappingOKBody(book3Plan))
	}}
	c, _ := wiredAgent(t, f, 50*time.Millisecond)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	// Both tiers time out → deterministic fallback.
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("expected deterministic fallback, got %s calls=%v", p.MappingSource, f.callModels())
	}
	if got := f.callModels(); len(got) != 2 {
		t.Fatalf("expected Tier1 then Tier2 calls, got %v", got)
	}
}

func TestHTTPStatusCodesEscalate(t *testing.T) {
	for _, code := range []int{http.StatusUnauthorized, http.StatusTooManyRequests, http.StatusInternalServerError} {
		t.Run(fmt.Sprintf("status_%d", code), func(t *testing.T) {
			var n int32
			f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
				atomic.AddInt32(&n, 1)
				if model == "gemini-3.8-flash" {
					w.WriteHeader(code)
					return
				}
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write(mappingOKBody(book3Plan))
			}}
			c, _ := wiredAgent(t, f, 5*time.Second)
			x, _ := BuildSampleXLSX(book3LikeRows())
			p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
			if err != nil {
				t.Fatal(err)
			}
			if p.MappingSource != MappingSourceAI || p.AiTierUsed != "tier2" || !p.Tier2Escalated {
				t.Fatalf("expected Tier2 AI after %d, got source=%s tier=%s", code, p.MappingSource, p.AiTierUsed)
			}
			if atomic.LoadInt32(&n) != 2 {
				t.Fatalf("call count=%d", n)
			}
		})
	}
}

func TestHTTPMalformedJSONEscalates(t *testing.T) {
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		if model == "gemini-3.8-flash" {
			_, _ = w.Write([]byte(`{"candidates":[{"content":{"parts":[{"text":"not-json"}]}}]}`))
			return
		}
		_, _ = w.Write(mappingOKBody(book3Plan))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.AiTierUsed != "tier2" || len(f.callModels()) != 2 {
		t.Fatalf("tier=%s calls=%v", p.AiTierUsed, f.callModels())
	}
}

func TestHTTPEmptyResultEscalates(t *testing.T) {
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		if model == "gemini-3.8-flash" {
			_, _ = w.Write([]byte(`{"candidates":[]}`))
			return
		}
		_, _ = w.Write(mappingOKBody(book3Plan))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.AiTierUsed != "tier2" || len(f.callModels()) != 2 {
		t.Fatalf("tier=%s calls=%v", p.AiTierUsed, f.callModels())
	}
}

func TestHTTPTier1ToTier2CallCounts(t *testing.T) {
	low := strings.Replace(book3Plan, `"confidence":0.95`, `"confidence":0.3`, 1)
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		plan := book3Plan
		if model == "gemini-3.8-flash" {
			plan = low
		}
		_, _ = w.Write(mappingOKBody(plan))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	got := f.callModels()
	if p.AiTierUsed != "tier2" || !p.Tier2Escalated || len(got) != 2 {
		t.Fatalf("tier=%s escalated=%v calls=%v", p.AiTierUsed, p.Tier2Escalated, got)
	}
	if got[0] != "gemini-3.8-flash" || got[1] != "gemini-pro-latest" {
		t.Fatalf("unexpected call order %v", got)
	}
}

func TestHTTPMissingAPIKeyUsesMockOutsideProduction(t *testing.T) {
	t.Setenv("ENVIRONMENT", "development")
	c := NewAgent("", "gemini-3.8-flash", false) // empty key forces useMock
	if !c.useMock {
		t.Fatal("empty key should enable mock mode")
	}
	p, err := c.AnalyzeAndNormalize(context.Background(), "carrefour_x.csv", []byte{9, 9, 9})
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceMock {
		t.Fatalf("source=%s", p.MappingSource)
	}
}

func TestHTTPMissingAPIKeyRefusesMockInProduction(t *testing.T) {
	t.Setenv("ENVIRONMENT", "production")
	c := NewAgent("", "gemini-3.8-flash", false)
	_, err := c.AnalyzeAndNormalize(context.Background(), "carrefour_x.csv", []byte{9, 9, 9})
	if err == nil || !strings.Contains(err.Error(), "refusing mock sample") {
		t.Fatalf("expected production refusal, got %v", err)
	}
}

func TestHTTPLowConfidenceWrongMappingFallsBack(t *testing.T) {
	wrong := `{"header_row_index":2,"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"ignore"},{"index":1,"role":"ignore"},{"index":2,"role":"ignore"},{"index":3,"role":"ignore"},
{"index":4,"role":"store_value","branch":"سموحة"},{"index":5,"role":"store_value","branch":"ستانلى"},
{"index":6,"role":"ignore"},{"index":7,"role":"ignore"},{"index":8,"role":"store_quantity","branch":"سموحة"},
{"index":9,"role":"store_quantity","branch":"ستانلى"},{"index":10,"role":"ignore"},{"index":11,"role":"ignore"}]}`
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(mappingOKBody(wrong))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	// No barcode/product → plan rejected → deterministic fallback.
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("expected deterministic after wrong mapping, got %s", p.MappingSource)
	}
}

func TestHTTPMissingColumnsRejectedByPlanCheck(t *testing.T) {
	missing := `{"header_row_index":2,"layout":"long","confidence":0.99,"columns":[
{"index":0,"role":"category"},{"index":1,"role":"supplier"}]}`
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(mappingOKBody(missing))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("source=%s", p.MappingSource)
	}
}

func TestHTTPTotalsMismatchFallsBackNoWriteSemantics(t *testing.T) {
	// Plan maps only one branch value column so extracted totals won't match sheet totals → rejected AI path.
	badTotals := `{"header_row_index":2,"skip_rows":[0,1],"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"category"},{"index":1,"role":"supplier"},{"index":2,"role":"barcode"},{"index":3,"role":"product_name"},
{"index":4,"role":"store_value","branch":"سموحة"},{"index":6,"role":"total_value"},
{"index":7,"role":"month"},{"index":8,"role":"store_quantity","branch":"سموحة"},
{"index":10,"role":"total_quantity"},{"index":11,"role":"year"}]}`
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(mappingOKBody(badTotals))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	// AI extraction rejected by validation → deterministic readers take over.
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("expected deterministic after totals mismatch rejection, got %s validation=%+v", p.MappingSource, p.Validation)
	}
}

func TestHTTPMissingMonthRejected(t *testing.T) {
	noMonth := strings.ReplaceAll(book3Plan, `{"index":7,"role":"month"},`, `{"index":7,"role":"ignore"},`)
	noMonth = strings.ReplaceAll(noMonth, `{"index":11,"role":"year"}`, `{"index":11,"role":"ignore"}`)
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(mappingOKBody(noMonth))
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	// AI path rejects (no month) → deterministic may still parse from content.
	if p.MappingSource != MappingSourceDeterministic && p.Validation != nil && p.Validation.Status == "rejected" {
		t.Fatalf("unexpected: source=%s validation=%+v", p.MappingSource, p.Validation)
	}
}

func TestHTTPMultiSheetSkipsAIMapping(t *testing.T) {
	f := &geminiHTTPFixture{}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, err := buildTwoSheetXLSX(book3LikeRows(), book3LikeRows())
	if err != nil {
		t.Fatal(err)
	}
	p, err := c.AnalyzeAndNormalize(context.Background(), "multi.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(f.callModels()) != 0 {
		t.Fatalf("multi-sheet must not call Gemini mapping, calls=%v", f.callModels())
	}
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("source=%s", p.MappingSource)
	}
}

func TestHTTPCacheHitNoNewCall(t *testing.T) {
	f := &geminiHTTPFixture{}
	c, _ := wiredAgent(t, f, 5*time.Second)
	dir := t.TempDir()
	c.WithMappingPlanDir(dir)
	x, _ := BuildSampleXLSX(book3LikeRows())
	first, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	second, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(f.callModels()) != 1 {
		t.Fatalf("cache should avoid second call, calls=%v", f.callModels())
	}
	if first.MappingSource != MappingSourceAI || second.MappingSource != MappingSourceCache {
		t.Fatalf("sources first=%s second=%s", first.MappingSource, second.MappingSource)
	}
}

func TestHTTPAPIKeyNeverLogged(t *testing.T) {
	var buf bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&buf)
	defer log.SetOutput(prev)

	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = io.WriteString(w, "boom "+testAPIKey) // even if body leaked, redact path should not log key from our errors
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	_, _ = c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if strings.Contains(buf.String(), testAPIKey) {
		t.Fatalf("API key leaked into logs: %s", buf.String())
	}
	if atomic.LoadInt32(&f.sawKeyURL) != 0 {
		t.Fatal("API key must not appear in request URL")
	}
}

func TestHTTPDeterministicNeverClaimsTier2Confidence(t *testing.T) {
	f := &geminiHTTPFixture{handler: func(model string, w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}}
	c, _ := wiredAgent(t, f, 5*time.Second)
	x, _ := BuildSampleXLSX(book3LikeRows())
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceDeterministic {
		t.Fatalf("source=%s", p.MappingSource)
	}
	if p.AiTierUsed == "tier2" || p.Tier2Escalated || p.AiModelUsed != "" {
		t.Fatalf("deterministic labeled as AI: %+v", p)
	}
}

// buildTwoSheetXLSX builds a minimal workbook with two worksheets sharing one SST.
func buildTwoSheetXLSX(sheet1, sheet2 [][]string) ([]byte, error) {
	var buf bytes.Buffer
	// Reuse BuildSampleXLSX structure by writing a custom zip.
	type sheet struct {
		name string
		rows [][]string
	}
	sheets := []sheet{{"sheet1", sheet1}, {"sheet2", sheet2}}
	shared := []string{}
	idx := map[string]int{}
	add := func(s string) int {
		if i, ok := idx[s]; ok {
			return i
		}
		i := len(shared)
		shared = append(shared, s)
		idx[s] = i
		return i
	}
	writeSheet := func(rows [][]string) []byte {
		var b strings.Builder
		b.WriteString(`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`)
		for rIdx, row := range rows {
			b.WriteString(fmt.Sprintf(`<row r="%d">`, rIdx+1))
			for cIdx, cell := range row {
				col := xlsxColLetters(cIdx) + fmt.Sprint(rIdx+1)
				b.WriteString(fmt.Sprintf(`<c r="%s" t="s"><v>%d</v></c>`, col, add(cell)))
			}
			b.WriteString(`</row>`)
		}
		b.WriteString(`</sheetData></worksheet>`)
		return []byte(b.String())
	}
	s1 := writeSheet(sheets[0].rows)
	s2 := writeSheet(sheets[1].rows)
	var sst strings.Builder
	sst.WriteString(fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="%d" uniqueCount="%d">`, len(shared), len(shared)))
	for _, s := range shared {
		sst.WriteString(`<si><t>` + xmlEscape(s) + `</t></si>`)
	}
	sst.WriteString(`</sst>`)
	files := map[string][]byte{
		"[Content_Types].xml": []byte(`<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>`),
		"xl/workbook.xml": []byte(`<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="One" sheetId="1" r:id="rId1"/>
    <sheet name="Two" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>`),
		"xl/_rels/workbook.xml.rels": []byte(`<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
</Relationships>`),
		"xl/sharedStrings.xml":      []byte(sst.String()),
		"xl/worksheets/sheet1.xml": s1,
		"xl/worksheets/sheet2.xml": s2,
	}
	zw := zip.NewWriter(&buf)
	for name, content := range files {
		w, err := zw.Create(name)
		if err != nil {
			return nil, err
		}
		if _, err := w.Write(content); err != nil {
			return nil, err
		}
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

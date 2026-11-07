package guardrails

import (
	"fmt"
	"log"
	"time"
)

// CallRecord is the minimal per-Gemini-call audit line (no prompt body, no PII cells).
type CallRecord struct {
	Filename  string
	Model     string
	Tier      string // tier1 | tier2 | mapping | full | mock
	LatencyMS int64
	OK        bool
	Err       string
}

// FormatCallLine builds the stable ops log line used across mapping + full invoke paths.
func FormatCallLine(r CallRecord) string {
	status := "ok"
	errMsg := ""
	if !r.OK {
		status = "fail"
		errMsg = RedactString(r.Err)
	}
	return fmt.Sprintf("[ingest-ai-call] file=%q model=%s tier=%s latency_ms=%d status=%s err=%q",
		FilenameForLog(r.Filename), r.Model, r.Tier, r.LatencyMS, status, errMsg)
}

// LogCall emits FormatCallLine via the standard logger.
func LogCall(r CallRecord) {
	log.Print(FormatCallLine(r))
}

// LogCallTimed fills latency from started and logs.
func LogCallTimed(filename, model, tier string, started time.Time, ok bool, callErr error) {
	errMsg := ""
	if callErr != nil {
		errMsg = callErr.Error()
	}
	LogCall(CallRecord{
		Filename:  filename,
		Model:     model,
		Tier:      tier,
		LatencyMS: time.Since(started).Milliseconds(),
		OK:        ok,
		Err:       errMsg,
	})
}

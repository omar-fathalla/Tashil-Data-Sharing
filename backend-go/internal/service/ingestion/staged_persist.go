package ingestion

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// StagedTTL is how long a Sell-Out preview (dry-run) can still be committed on any instance.
var StagedTTL = 6 * time.Hour

// StagedUploadError is a commit failure with an HTTP status (404 / 409 / 410) and an Arabic message.
// Nothing is saved when it is returned.
type StagedUploadError struct {
	Status  int
	Message string
}

func (e *StagedUploadError) Error() string { return e.Message }

var errStagedGone = &StagedUploadError{Status: http.StatusGone, Message: "المعاينة انتهت، ارفع الملف تاني. مفيش حاجة اتحفظت."}

// stagedDiskMeta is what a dry-run leaves on the archive mount so another instance can commit it.
// The file bytes sit next to it; the commit re-parses them and must get the same preview.
type stagedDiskMeta struct {
	BatchID         string    `json:"batch_id"`
	TenantID        string    `json:"tenant_id"`
	Filename        string    `json:"filename"`
	TargetChain     string    `json:"target_chain"`
	RequestedPeriod string    `json:"requested_period,omitempty"`
	PeriodChoice    string    `json:"period_choice,omitempty"`
	Interactive     bool      `json:"interactive"`
	ValidRows       int       `json:"valid_rows"`
	TotalRevenue    float64   `json:"total_revenue"`
	CreatedAt       time.Time `json:"created_at"`
}

type noDiskStageKey struct{}

func stagedTenantSlug(t string) string {
	return normalizeArchiveTenantID(t)
}

func (p *Processor) stagedRoot() string {
	if strings.TrimSpace(p.archiveDir) == "" {
		return ""
	}
	return filepath.Join(p.archiveDir, "_staged")
}

func safeBatchID(id string) bool {
	if id == "" || len(id) > 128 {
		return false
	}
	for _, c := range id {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

func (p *Processor) stagedPaths(tenantID, batchID string) (string, string, bool) {
	root := p.stagedRoot()
	if root == "" || !safeBatchID(batchID) {
		return "", "", false
	}
	dir := filepath.Join(root, stagedTenantSlug(tenantID))
	return filepath.Join(dir, batchID+".json"), filepath.Join(dir, batchID+".bin"), true
}

// persistStaged writes the preview metadata and the file bytes under _staged/<tenant>/ and sweeps
// expired entries. It never touches the archive index.
func (p *Processor) persistStaged(ctx context.Context, meta stagedDiskMeta, fileBytes []byte) {
	if ctx != nil && ctx.Value(noDiskStageKey{}) != nil {
		return
	}
	metaPath, binPath, ok := p.stagedPaths(meta.TenantID, meta.BatchID)
	if !ok {
		return
	}
	p.sweepStaged(time.Now())
	if err := os.MkdirAll(filepath.Dir(metaPath), 0o755); err != nil {
		log.Printf("[staged] mkdir: %v", err)
		return
	}
	data, _ := json.Marshal(meta)
	if err := os.WriteFile(binPath, fileBytes, 0o644); err != nil {
		log.Printf("[staged] write bytes %s: %v", meta.BatchID, err)
		return
	}
	if err := os.WriteFile(metaPath, data, 0o644); err != nil {
		log.Printf("[staged] write meta %s: %v", meta.BatchID, err)
		_ = os.Remove(binPath)
	}
}

func (p *Processor) removeStaged(tenantID, batchID string) {
	if metaPath, binPath, ok := p.stagedPaths(tenantID, batchID); ok {
		_ = os.Remove(metaPath)
		_ = os.Remove(binPath)
	}
}

// sweepStaged deletes staged previews older than StagedTTL (all tenants). Only _staged is touched.
func (p *Processor) sweepStaged(now time.Time) int {
	root := p.stagedRoot()
	if root == "" {
		return 0
	}
	removed := 0
	tenants, _ := os.ReadDir(root)
	for _, t := range tenants {
		if !t.IsDir() {
			continue
		}
		dir := filepath.Join(root, t.Name())
		files, _ := os.ReadDir(dir)
		for _, f := range files {
			if !strings.HasSuffix(f.Name(), ".json") {
				continue
			}
			path := filepath.Join(dir, f.Name())
			data, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			var m stagedDiskMeta
			if json.Unmarshal(data, &m) != nil || now.Sub(m.CreatedAt) > StagedTTL {
				_ = os.Remove(path)
				_ = os.Remove(strings.TrimSuffix(path, ".json") + ".bin")
				removed++
			}
		}
	}
	return removed
}

// loadStaged reads a staged preview for tenantID. Missing or expired -> 410; another tenant's -> 404.
func (p *Processor) loadStaged(tenantID, batchID string) (*stagedDiskMeta, []byte, error) {
	metaPath, binPath, ok := p.stagedPaths(tenantID, batchID)
	if !ok {
		return nil, nil, errStagedGone
	}
	data, err := os.ReadFile(metaPath)
	if err != nil {
		return nil, nil, errStagedGone
	}
	var m stagedDiskMeta
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, nil, errStagedGone
	}
	if stagedTenantSlug(m.TenantID) != stagedTenantSlug(tenantID) || m.BatchID != batchID {
		return nil, nil, &StagedUploadError{Status: http.StatusNotFound, Message: "المعاينة دي مش تبع الحساب ده. مفيش حاجة اتحفظت."}
	}
	if time.Since(m.CreatedAt) > StagedTTL {
		p.removeStaged(tenantID, batchID)
		return nil, nil, errStagedGone
	}
	b, err := os.ReadFile(binPath)
	if err != nil || len(b) == 0 {
		return nil, nil, errStagedGone
	}
	return &m, b, nil
}

// restageFromDisk rebuilds a staged Sell-Out upload on an instance that did not run the dry-run:
// it re-parses the saved bytes with the same chain, period and choice, and refuses (409, nothing
// saved) when the result differs from the preview the user confirmed (rows, value or chain).
func (p *Processor) restageFromDisk(ctx context.Context, tenantID, batchID string) (*StagedUpload, error) {
	meta, b, err := p.loadStaged(tenantID, batchID)
	if err != nil {
		return nil, err
	}
	rctx := context.WithValue(ctx, noDiskStageKey{}, true)
	rctx = gemini.WithRequestedPeriodDate(rctx, meta.RequestedPeriod)
	if meta.Interactive {
		g, _ := uploadGuards(ctx)
		g.PeriodChoice = meta.PeriodChoice
		rctx = WithUploadGuards(rctx, g)
	}
	res, perr := p.ProcessUploadWithDryRun(rctx, tenantID, meta.Filename, b, true, meta.TargetChain)
	if perr != nil {
		return nil, &StagedUploadError{Status: http.StatusConflict, Message: "مقدرناش نعيد قراية الملف زي المعاينة: " + perr.Error() + ". مفيش حاجة اتحفظت."}
	}
	p.stagedMu.Lock()
	st := p.staged[res.BatchID]
	delete(p.staged, res.BatchID)
	p.stagedMu.Unlock()
	round := func(v float64) float64 { return math.Round(v*100) / 100 }
	if st == nil || res.ValidRows != meta.ValidRows || round(res.TotalRevenue) != round(meta.TotalRevenue) ||
		!strings.EqualFold(strings.TrimSpace(st.TargetChain), strings.TrimSpace(meta.TargetChain)) {
		got := "?"
		if st != nil {
			got = fmt.Sprintf("%d صف / %.2f ج.م / %s", res.ValidRows, res.TotalRevenue, st.TargetChain)
		}
		return nil, &StagedUploadError{Status: http.StatusConflict, Message: fmt.Sprintf(
			"الملف لما اتقرا تاني طلع مختلف عن المعاينة (المعاينة %d صف / %.2f ج.م / %s، دلوقتي %s). مفيش حاجة اتحفظت، ارفع الملف تاني.",
			meta.ValidRows, meta.TotalRevenue, meta.TargetChain, got)}
	}
	st.BatchID = batchID
	st.Result.BatchID = batchID
	st.PeriodChoice = meta.PeriodChoice
	log.Printf("[staged] batch %s restored from disk for %s (%d rows)", batchID, meta.Filename, meta.ValidRows)
	return st, nil
}

// IsStagedUploadError maps a commit error to its HTTP status (0 when it is not one).
func IsStagedUploadError(err error) (int, string) {
	var se *StagedUploadError
	if errors.As(err, &se) {
		return se.Status, se.Message
	}
	return 0, ""
}

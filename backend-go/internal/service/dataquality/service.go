package dataquality

import (
	"context"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// Store persists issues + statuses per tenant (Firestore).
type Store interface {
	GetDataQualityState(ctx context.Context, tenantID string) (*domain.DataQualityState, error)
	SaveDataQualityState(ctx context.Context, d *domain.DataQualityState) error
}

// SalesSource gives Sell-Out / Sell-In records used to size an issue's impact.
type SalesSource interface {
	GetSellOutRecords(ctx context.Context, tenantID string, filter bigquery.RecordFilter) ([]domain.SellOutFact, int, error)
	GetSellInRecords(ctx context.Context, tenantID string, filter bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error)
}

// MasterSource is the live product master (after in-app edits).
type MasterSource interface {
	GetProductMasterItems(tenantID string) []domain.ProductMasterItem
}

type sourceFile struct {
	name string
	raw  []byte
}

// Service runs checks, reconciles them with persisted statuses and serves reads.
type Service struct {
	store  Store
	sales  SalesSource
	master MasterSource
	mu     sync.Mutex // serializes read-modify-write of a tenant's state
	now    func() time.Time

	filesMu sync.Mutex
	pmFiles map[string]sourceFile // tenant -> latest uploaded Product Master
	timer   *time.Timer
}

// RerunDelay debounces bursts of source changes before checks re-run.
var RerunDelay = 2 * time.Second

func NewService(store Store, sales SalesSource) *Service {
	return &Service{store: store, sales: sales, now: func() time.Time { return time.Now().UTC() }, pmFiles: map[string]sourceFile{}}
}

// WithMaster lets re-checks see in-app master edits.
func (s *Service) WithMaster(m MasterSource) *Service { s.master = m; return s }

// SetProductMasterFile remembers the tenant's latest Product Master (re-checked on every change).
func (s *Service) SetProductMasterFile(tenantID, filename string, raw []byte) {
	s.filesMu.Lock()
	s.pmFiles[tenantID] = sourceFile{name: filename, raw: append([]byte(nil), raw...)}
	s.filesMu.Unlock()
}

// OnSourceChanged is called on any source change (master upload/edit, sell-in/out, chain
// discounts, ...). Checks re-run after RerunDelay so bursts collapse into one run.
func (s *Service) OnSourceChanged() {
	s.filesMu.Lock()
	defer s.filesMu.Unlock()
	if s.timer != nil {
		s.timer.Stop()
	}
	s.timer = time.AfterFunc(RerunDelay, func() { s.RerunAll(context.Background()) })
}

// RerunAll re-checks every known source file for every tenant.
func (s *Service) RerunAll(ctx context.Context) {
	s.filesMu.Lock()
	files := make(map[string]sourceFile, len(s.pmFiles))
	for t, f := range s.pmFiles {
		files[t] = f
	}
	s.filesMu.Unlock()
	for t, f := range files {
		if _, err := s.RunProductMaster(ctx, t, f.name, f.raw); err != nil {
			log.Printf("ERROR [data-quality] tenant=%s re-check failed: %v", t, err)
		}
	}
}

type salesTotals struct{ sellOut, sellIn map[string]float64 }

func (s *Service) loadSales(ctx context.Context, tenant string) salesTotals {
	t := salesTotals{sellOut: map[string]float64{}, sellIn: map[string]float64{}}
	if s.sales == nil {
		return t
	}
	if recs, _, err := s.sales.GetSellOutRecords(ctx, tenant, bigquery.RecordFilter{Limit: math.MaxInt32}); err == nil {
		for _, r := range recs {
			if c := domain.NormalizeItemCode(r.ItemCode); c != "" {
				t.sellOut["c:"+c] += r.NetRevenue
			}
			if b := domain.CleanBarcode(r.Barcode); b != "" {
				t.sellOut["b:"+b] += r.NetRevenue
			}
		}
	}
	if recs, _, err := s.sales.GetSellInRecords(ctx, tenant, bigquery.SellInRecordFilter{Limit: math.MaxInt32}); err == nil {
		for _, r := range recs {
			if c := domain.NormalizeItemCode(r.ItemCode); c != "" {
				t.sellIn["c:"+c] += r.NetValueEGP
			}
			if b := domain.CleanBarcode(r.Barcode); b != "" {
				t.sellIn["b:"+b] += r.NetValueEGP
			}
		}
	}
	return t
}

// impact = Sell-Out sales of the SKU (by code, else barcode); else its Sell-In value; else unknown.
// For a duplicated barcode the barcode total is shared by several SKUs, so only the code is used.
func (t salesTotals) impact(iss domain.DataQualityIssue) (*float64, string) {
	keys := []string{}
	if iss.ItemCode != "" {
		keys = append(keys, "c:"+iss.ItemCode)
	}
	if iss.Barcode != "" && iss.Type != domain.DQTypeDuplicateBarcode {
		keys = append(keys, "b:"+domain.CleanBarcode(iss.Barcode))
	}
	for _, src := range []struct {
		m     map[string]float64
		basis string
	}{{t.sellOut, "مبيعات Sell-Out للصنف"}, {t.sellIn, "قيمة Sell-In للصنف"}} {
		for _, k := range keys {
			if v, ok := src.m[k]; ok && v != 0 {
				r := math.Round(v*100) / 100
				return &r, src.basis
			}
		}
	}
	return nil, ""
}

// RunProductMaster checks an uploaded Product Master and merges results into the tenant's issues.
func (s *Service) RunProductMaster(ctx context.Context, tenantID, filename string, raw []byte) (*domain.DataQualityRun, error) {
	var current []domain.ProductMasterItem
	if s.master != nil {
		current = s.master.GetProductMasterItems(tenantID)
	}
	res, err := CheckProductMaster(filename, raw, current...)
	if err != nil {
		return nil, err
	}
	sales := s.loadSales(ctx, tenantID)
	for i := range res.Issues {
		res.Issues[i].ImpactEGP, res.Issues[i].ImpactBasis = sales.impact(res.Issues[i])
	}
	run := domain.DataQualityRun{Source: domain.DQSourceProductMaster, SourceFile: filename, Sheet: res.Sheet,
		TotalRows: res.TotalRows, CriticalRows: res.CriticalRows, RanAt: s.now()}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.store.GetDataQualityState(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	Reconcile(st, domain.DQSourceProductMaster, res.Issues, s.now())
	replaced := false
	for i := range st.Runs {
		if st.Runs[i].Source == run.Source {
			st.Runs[i] = run
			replaced = true
		}
	}
	if !replaced {
		st.Runs = append(st.Runs, run)
	}
	st.TenantID = tenantID
	if err := s.store.SaveDataQualityState(ctx, st); err != nil {
		return nil, err
	}
	log.Printf("[data-quality] tenant=%s product_master %s: %d rows, %d issues, %d rows with critical issues",
		tenantID, filename, res.TotalRows, len(res.Issues), res.CriticalRows)
	return &run, nil
}

// Reconcile merges a fresh check of one source into the persisted state:
//   - known issues keep id, first_seen and a manual status (an ignored issue stays ignored);
//     a closed issue found again is reopened;
//   - new issues open;
//   - open issues of that source no longer found are auto-closed as fixed.
func Reconcile(st *domain.DataQualityState, source string, found []domain.DataQualityIssue, now time.Time) {
	byID := map[string]int{}
	for i, iss := range st.Issues {
		byID[iss.ID] = i
	}
	seen := map[string]bool{}
	for _, f := range found {
		if seen[f.ID] {
			continue
		}
		seen[f.ID] = true
		f.LastSeen = now
		if i, ok := byID[f.ID]; ok {
			old := st.Issues[i]
			f.FirstSeen = old.FirstSeen
			f.Status, f.StatusReason, f.StatusBy = old.Status, old.StatusReason, old.StatusBy
			f.UpdatedAt = old.UpdatedAt
			f.ResolvedAt = old.ResolvedAt
			if old.Status == domain.DQStatusResolved {
				f.Status, f.StatusReason, f.StatusBy, f.UpdatedAt, f.ResolvedAt = domain.DQStatusOpen, "ظهرت مجددًا في آخر فحص", "system", now, nil
			}
			st.Issues[i] = f
			continue
		}
		f.FirstSeen, f.UpdatedAt, f.Status = now, now, domain.DQStatusOpen
		st.Issues = append(st.Issues, f)
		byID[f.ID] = len(st.Issues) - 1
	}
	for i := range st.Issues {
		iss := &st.Issues[i]
		if iss.Source == source && !seen[iss.ID] && iss.Status == domain.DQStatusOpen {
			t := now
			iss.Status, iss.StatusReason, iss.StatusBy, iss.AutoClosed, iss.UpdatedAt, iss.ResolvedAt = domain.DQStatusResolved, "لم تعد موجودة في آخر فحص", "system", true, now, &t
		}
	}
}

// IssueFilter narrows ListIssues; empty fields match everything.
type IssueFilter struct{ Source, Type, Severity, Status string }

func (s *Service) ListIssues(ctx context.Context, tenantID string, f IssueFilter) ([]domain.DataQualityIssue, error) {
	st, err := s.store.GetDataQualityState(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	out := []domain.DataQualityIssue{}
	for _, iss := range st.Issues {
		if (f.Source == "" || iss.Source == f.Source) && (f.Type == "" || iss.Type == f.Type) &&
			(f.Severity == "" || iss.Severity == f.Severity) && (f.Status == "" || iss.Status == f.Status) {
			out = append(out, iss)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Source != out[j].Source {
			return out[i].Source < out[j].Source
		}
		if out[i].Severity != out[j].Severity {
			return out[i].Severity == domain.DQSeverityCritical
		}
		return out[i].Row < out[j].Row
	})
	return out, nil
}

var ErrNotFound = fmt.Errorf("issue not found")

// UpdateStatus sets an issue's status. Ignoring requires a reason.
func (s *Service) UpdateStatus(ctx context.Context, tenantID, id, newStatus, reason, by string) (*domain.DataQualityIssue, error) {
	switch newStatus {
	case domain.DQStatusOpen, domain.DQStatusResolved, domain.DQStatusIgnored:
	default:
		return nil, fmt.Errorf("invalid status %q", newStatus)
	}
	reason = strings.TrimSpace(reason)
	if newStatus == domain.DQStatusIgnored && reason == "" {
		return nil, fmt.Errorf("reason is required to ignore an issue")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.store.GetDataQualityState(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	for i := range st.Issues {
		if st.Issues[i].ID == id {
			iss := &st.Issues[i]
			now := s.now()
			iss.Status, iss.StatusReason, iss.StatusBy, iss.AutoClosed, iss.UpdatedAt = newStatus, reason, by, false, now
			iss.ResolvedAt = nil
			if newStatus == domain.DQStatusResolved {
				iss.ResolvedAt = &now
			}
			if err := s.store.SaveDataQualityState(ctx, st); err != nil {
				return nil, err
			}
			cp := *iss
			return &cp, nil
		}
	}
	return nil, ErrNotFound
}

// TypeSummary is one card on the Errors page.
type TypeSummary struct {
	Source    string  `json:"source"`
	Type      string  `json:"type"`
	TypeLabel string  `json:"type_label"`
	Severity  string  `json:"severity"`
	Open      int     `json:"open"`
	Resolved  int     `json:"resolved"`
	Ignored   int     `json:"ignored"`
	Total     int     `json:"total"`
	ImpactEGP float64 `json:"impact_egp"` // open issues only; SKUs counted once per type
}

type SourceSummary struct {
	Source        string    `json:"source"`
	SourceFile    string    `json:"source_file"`
	Sheet         string    `json:"sheet"`
	TotalRows     int       `json:"total_rows"`
	CriticalRows  int       `json:"critical_rows"` // rows with an open critical issue
	CleanlinessPc float64   `json:"cleanliness_pct"`
	Open          int       `json:"open"`
	RanAt         time.Time `json:"ran_at"`
}

type Summary struct {
	Sources       []SourceSummary `json:"sources"`
	Types         []TypeSummary   `json:"types"`
	TotalRows     int             `json:"total_rows"`
	CriticalRows  int             `json:"critical_rows"`
	CleanlinessPc float64         `json:"cleanliness_pct"`
	Open          int             `json:"open"`
	Resolved      int             `json:"resolved"`
	Ignored       int             `json:"ignored"`
	UpdatedAt     time.Time       `json:"updated_at"`
}

// Summary: counts per source/type and cleanliness % = rows without an open critical issue / rows.
func (s *Service) Summary(ctx context.Context, tenantID string) (*Summary, error) {
	st, err := s.store.GetDataQualityState(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	sum := &Summary{Sources: []SourceSummary{}, Types: []TypeSummary{}, UpdatedAt: st.UpdatedAt}
	types := map[string]*TypeSummary{}
	impactSeen := map[string]bool{}
	critRows := map[string]map[int]bool{}
	openBySource := map[string]int{}
	for _, iss := range st.Issues {
		k := iss.Source + "|" + iss.Type
		t := types[k]
		if t == nil {
			t = &TypeSummary{Source: iss.Source, Type: iss.Type, TypeLabel: iss.TypeLabel, Severity: iss.Severity}
			types[k] = t
		}
		if iss.Severity == domain.DQSeverityCritical {
			t.Severity = domain.DQSeverityCritical
		}
		t.Total++
		switch iss.Status {
		case domain.DQStatusOpen:
			t.Open++
			sum.Open++
			openBySource[iss.Source]++
			if iss.ImpactEGP != nil && !impactSeen[k+"|"+iss.ItemCode+"|"+iss.Barcode] {
				impactSeen[k+"|"+iss.ItemCode+"|"+iss.Barcode] = true
				t.ImpactEGP += *iss.ImpactEGP
			}
			if iss.Severity == domain.DQSeverityCritical {
				if critRows[iss.Source] == nil {
					critRows[iss.Source] = map[int]bool{}
				}
				critRows[iss.Source][iss.Row] = true
			}
		case domain.DQStatusResolved:
			t.Resolved++
			sum.Resolved++
		case domain.DQStatusIgnored:
			t.Ignored++
			sum.Ignored++
		}
	}
	for _, t := range types {
		t.ImpactEGP = math.Round(t.ImpactEGP*100) / 100
		sum.Types = append(sum.Types, *t)
	}
	sort.Slice(sum.Types, func(i, j int) bool {
		if sum.Types[i].Open != sum.Types[j].Open {
			return sum.Types[i].Open > sum.Types[j].Open
		}
		return sum.Types[i].Type < sum.Types[j].Type
	})
	for _, r := range st.Runs {
		ss := SourceSummary{Source: r.Source, SourceFile: r.SourceFile, Sheet: r.Sheet, TotalRows: r.TotalRows,
			CriticalRows: len(critRows[r.Source]), Open: openBySource[r.Source], RanAt: r.RanAt}
		ss.CleanlinessPc = cleanliness(ss.TotalRows, ss.CriticalRows)
		sum.Sources = append(sum.Sources, ss)
		sum.TotalRows += ss.TotalRows
		sum.CriticalRows += ss.CriticalRows
	}
	sum.CleanlinessPc = cleanliness(sum.TotalRows, sum.CriticalRows)
	return sum, nil
}

func cleanliness(total, critical int) float64 {
	if total <= 0 {
		return 100
	}
	return math.Round(float64(total-critical)/float64(total)*10000) / 100
}

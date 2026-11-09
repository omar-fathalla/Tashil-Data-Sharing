package branchmaster

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// AIProposer optionally refines unknown-name proposals (Gemini). Nil = deterministic only.
type AIProposer interface {
	// Propose returns an optional preferred branch code among candidates, with confidence.
	Propose(ctx context.Context, raw string, candidates []Branch) (code string, confidence float64, reasonAR string, err error)
}

// Service is the tenant-scoped branch master API.
type Service struct {
	store Store
	ai    AIProposer
	now   func() time.Time
	mu    sync.Mutex
	cache map[string]*State // tenant key → last loaded
}

// New constructs a Service.
func New(store Store) *Service {
	if store == nil {
		store = NewMemoryStore()
	}
	return &Service{
		store: store,
		now:   func() time.Time { return time.Now().UTC() },
		cache: map[string]*State{},
	}
}

// WithAI attaches an optional Gemini proposer.
func (s *Service) WithAI(ai AIProposer) *Service {
	s.ai = ai
	return s
}

func (s *Service) load(ctx context.Context, tenantID string) (*State, error) {
	st, err := s.store.GetBranchMaster(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	if st == nil {
		st = &State{TenantID: tenantID}
	}
	s.mu.Lock()
	s.cache[normalizeTenant(tenantID)] = st
	s.mu.Unlock()
	return st, nil
}

func (s *Service) save(ctx context.Context, st *State) error {
	st.UpdatedAt = s.now()
	if err := s.store.SaveBranchMaster(ctx, st); err != nil {
		return err
	}
	s.mu.Lock()
	s.cache[normalizeTenant(st.TenantID)] = cloneStatePtr(st)
	s.mu.Unlock()
	return nil
}

func cloneStatePtr(st *State) *State {
	cp := cloneState(*st)
	return &cp
}

// Get returns the current master (empty if none).
func (s *Service) Get(ctx context.Context, tenantID string) (*State, error) {
	return s.load(ctx, tenantID)
}

// ListBranches returns branches, optionally filtered by chain code.
func (s *Service) ListBranches(ctx context.Context, tenantID, chainCode string) ([]Branch, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	var out []Branch
	for _, b := range st.Branches {
		if chainCode != "" && !strings.EqualFold(b.ChainCode, chainCode) {
			continue
		}
		out = append(out, b)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Code < out[j].Code })
	return out, nil
}

// ListAliases returns aliases, optionally for one branch.
func (s *Service) ListAliases(ctx context.Context, tenantID, branchCode string) ([]Alias, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	var out []Alias
	for _, a := range st.Aliases {
		if branchCode != "" && !strings.EqualFold(a.BranchCode, branchCode) {
			continue
		}
		out = append(out, a)
	}
	return out, nil
}

// ListPending returns unresolved pending proposals.
func (s *Service) ListPending(ctx context.Context, tenantID string) ([]Pending, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	var out []Pending
	for _, p := range st.Pending {
		if p.Status == StatusPending || p.Status == "" {
			out = append(out, p)
		}
	}
	return out, nil
}

// UpdateDisplayName edits the short display name of a branch.
func (s *Service) UpdateDisplayName(ctx context.Context, tenantID, branchCode, displayName, by string) (*Branch, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	displayName = strings.TrimSpace(displayName)
	if displayName == "" {
		return nil, fmt.Errorf("display_name required")
	}
	for i := range st.Branches {
		if !strings.EqualFold(st.Branches[i].Code, branchCode) {
			continue
		}
		if st.Branches[i].Unallocated {
			return nil, fmt.Errorf("cannot rename unallocated bucket")
		}
		st.Branches[i].DisplayName = displayName
		st.Branches[i].UpdatedAt = s.now()
		if err := s.save(ctx, st); err != nil {
			return nil, err
		}
		br := st.Branches[i]
		return &br, nil
	}
	return nil, fmt.Errorf("branch %s not found", branchCode)
}

// ResolveForReport is the query-time mapping layer: group key = branch code (or raw
// when unmapped), display = short name. Raw facts are never modified.
func (s *Service) ResolveForReport(ctx context.Context, tenantID, chainSlug, rawStoreName string) (code, display string) {
	rawStoreName = strings.TrimSpace(rawStoreName)
	if rawStoreName == "" {
		return "", ""
	}
	if IsUnallocated(rawStoreName) {
		cc := ChainCodeForSlug(chainSlug)
		return UnallocatedCode(cc), UnallocatedBranchName
	}
	st, err := s.load(ctx, tenantID)
	if err != nil || st == nil || (!st.BootstrapDone && len(st.Aliases) == 0 && len(st.Branches) == 0) {
		return rawStoreName, ShortDisplay(rawStoreName)
	}
	r := Resolve(st, chainSlug, rawStoreName)
	switch r.Kind {
	case KindExact, KindAlias, KindNormalized, KindHigh, KindUnallocated:
		if r.BranchCode != "" {
			return r.BranchCode, r.DisplayName
		}
	}
	// Pending / new / identity: keep separate buckets by raw (no silent merge).
	return rawStoreName, ShortDisplay(rawStoreName)
}

// ObserveRaw resolves a newly seen name during upload. High → auto-link + alias + notice.
// Ambiguous / low → PENDING. New → allocate code + notice. Unallocated never auto-linked.
func (s *Service) ObserveRaw(ctx context.Context, tenantID, chainSlug, raw, by string) (Resolution, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return Resolution{}, err
	}
	now := s.now()
	if chainSlug == "" {
		chainSlug = InferChainSlug(raw)
	}
	EnsureUnallocatedBranch(st, chainSlug, now)

	r := Resolve(st, chainSlug, raw)
	if r.Kind == KindUnallocated {
		_ = s.save(ctx, st)
		return r, nil
	}
	if r.Kind == KindExact || r.Kind == KindAlias || r.Kind == KindNormalized {
		return r, nil
	}

	// Optional AI refinement for unknown / low / ambiguous.
	if s.ai != nil && (r.Kind == KindNew || r.Kind == KindLow || r.Kind == KindAmbiguous) {
		cands := RankCandidates(st, findChainCode(st, chainSlug), raw)
		var branches []Branch
		for _, c := range cands {
			branches = append(branches, c.Branch)
		}
		if code, conf, reason, err := s.ai.Propose(ctx, raw, branches); err == nil && code != "" {
			if br, ok := findBranchByCode(st, code); ok && conf >= HighConfidenceMin {
				r.Kind = KindHigh
				r.BranchCode = br.Code
				r.DisplayName = br.DisplayName
				r.ChainCode = br.ChainCode
				r.Confidence = conf
				r.ReasonAR = reason
			}
		}
	}

	switch r.Kind {
	case KindHigh:
		ts := now
		st.Aliases = append(st.Aliases, Alias{
			RawName:       raw,
			NormalizedKey: Normalize(raw),
			BranchCode:    r.BranchCode,
			Source:        SourceAuto,
			Confidence:    r.Confidence,
			ConfirmedBy:   by,
			ConfirmedAt:   &ts,
			CreatedAt:     now,
		})
		r.AutoLinked = true
		st.Notices = append(st.Notices, Notice{
			ID:        uuid.NewString(),
			Kind:      "auto_link",
			MessageAR: fmt.Sprintf("تم ربط «%s» تلقائياً بالفرع %s (%s).", raw, r.DisplayName, r.BranchCode),
			RawName:   raw,
			BranchCode: r.BranchCode,
			CreatedAt: now,
		})
		if err := s.save(ctx, st); err != nil {
			return r, err
		}
		return r, nil

	case KindAmbiguous, KindLow:
		p := Pending{
			ID:               uuid.NewString(),
			RawName:          raw,
			NormalizedKey:    Normalize(raw),
			ChainSlug:        chainSlug,
			SuggestedCode:    r.BranchCode,
			SuggestedName:    r.DisplayName,
			AltSuggestedCode: r.AltCode,
			AltSuggestedName: r.AltName,
			Confidence:       r.Confidence,
			AltConfidence:    r.AltConfidence,
			ReasonAR:         r.ReasonAR,
			Kind:             r.Kind,
			Status:           StatusPending,
			CreatedAt:        now,
			UpdatedAt:        now,
		}
		// Dedupe pending by normalized key.
		replaced := false
		for i := range st.Pending {
			if st.Pending[i].NormalizedKey == p.NormalizedKey && st.Pending[i].Status == StatusPending {
				st.Pending[i] = p
				replaced = true
				break
			}
		}
		if !replaced {
			st.Pending = append(st.Pending, p)
		}
		r.PendingID = p.ID
		st.Notices = append(st.Notices, Notice{
			ID:        uuid.NewString(),
			Kind:      "pending",
			MessageAR: fmt.Sprintf("اسم فرع يحتاج تأكيد: «%s» — %s", raw, r.ReasonAR),
			RawName:   raw,
			CreatedAt: now,
		})
		if err := s.save(ctx, st); err != nil {
			return r, err
		}
		return r, nil

	default: // KindNew / KindIdentity
		if !st.BootstrapDone && len(st.Branches) <= 1 {
			// Empty master: leave to bootstrap proposal; still surface as new.
			r.Kind = KindNew
			r.ReasonAR = "أول رفع لهذه السلسلة — يلزم تأكيد جدول الفروع المقترح مرة واحدة."
			return r, nil
		}
		ch := ensureChain(st, chainSlug, now)
		code := NextBranchCode(ch.Code, st.Branches)
		display := ShortDisplay(raw)
		br := Branch{
			Code:        code,
			ChainCode:   ch.Code,
			DisplayName: display,
			Active:      true,
			CreatedAt:   now,
			UpdatedAt:   now,
		}
		st.Branches = append(st.Branches, br)
		ts := now
		st.Aliases = append(st.Aliases, Alias{
			RawName:       raw,
			NormalizedKey: Normalize(raw),
			BranchCode:    code,
			Source:        SourceUpload,
			Confidence:    1,
			ConfirmedBy:   by,
			ConfirmedAt:   &ts,
			CreatedAt:     now,
		})
		st.Notices = append(st.Notices, Notice{
			ID:         uuid.NewString(),
			Kind:       "new_branch",
			MessageAR:  fmt.Sprintf("فرع جديد: %s (%s) من الاسم «%s».", display, code, raw),
			RawName:    raw,
			BranchCode: code,
			CreatedAt:  now,
		})
		r.Kind = KindNew
		r.BranchCode = code
		r.DisplayName = display
		r.ChainCode = ch.Code
		r.Confidence = 1
		r.ReasonAR = "تم إنشاء كود فرع جديد وإشعار المالك."
		if err := s.save(ctx, st); err != nil {
			return r, err
		}
		return r, nil
	}
}

// ConfirmPending lets the owner pick a branch (or create new) for a pending raw name.
func (s *Service) ConfirmPending(ctx context.Context, tenantID, pendingID, branchCode, newDisplayName, by string) (*Pending, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	now := s.now()
	var idx = -1
	for i := range st.Pending {
		if st.Pending[i].ID == pendingID {
			idx = i
			break
		}
	}
	if idx < 0 {
		return nil, fmt.Errorf("pending %s not found", pendingID)
	}
	p := st.Pending[idx]
	if p.Status != StatusPending && p.Status != "" {
		return nil, fmt.Errorf("pending already decided")
	}

	var br Branch
	if branchCode == "" || strings.EqualFold(branchCode, "new") {
		ch := ensureChain(st, p.ChainSlug, now)
		code := NextBranchCode(ch.Code, st.Branches)
		display := strings.TrimSpace(newDisplayName)
		if display == "" {
			display = ShortDisplay(p.RawName)
		}
		br = Branch{
			Code: code, ChainCode: ch.Code, DisplayName: display,
			Active: true, CreatedAt: now, UpdatedAt: now,
		}
		st.Branches = append(st.Branches, br)
		branchCode = code
	} else {
		var ok bool
		br, ok = findBranchByCode(st, branchCode)
		if !ok {
			return nil, fmt.Errorf("branch %s not found", branchCode)
		}
		if br.Unallocated {
			return nil, fmt.Errorf("cannot link to unallocated bucket")
		}
	}

	ts := now
	st.Aliases = append(st.Aliases, Alias{
		RawName:       p.RawName,
		NormalizedKey: p.NormalizedKey,
		BranchCode:    branchCode,
		Source:        SourceOwner,
		Confidence:    1,
		ConfirmedBy:   by,
		ConfirmedAt:   &ts,
		CreatedAt:     now,
	})
	p.Status = StatusConfirmed
	p.SuggestedCode = branchCode
	p.SuggestedName = br.DisplayName
	p.DecidedBy = by
	p.UpdatedAt = now
	st.Pending[idx] = p
	if err := s.save(ctx, st); err != nil {
		return nil, err
	}
	return &p, nil
}

// RejectPending marks a pending name rejected (stays unmapped).
func (s *Service) RejectPending(ctx context.Context, tenantID, pendingID, by string) (*Pending, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	for i := range st.Pending {
		if st.Pending[i].ID != pendingID {
			continue
		}
		st.Pending[i].Status = StatusRejected
		st.Pending[i].DecidedBy = by
		st.Pending[i].UpdatedAt = s.now()
		p := st.Pending[i]
		if err := s.save(ctx, st); err != nil {
			return nil, err
		}
		return &p, nil
	}
	return nil, fmt.Errorf("pending %s not found", pendingID)
}

// ConfirmBootstrap applies a dry-run / bootstrap proposal after owner approval.
func (s *Service) ConfirmBootstrap(ctx context.Context, tenantID string, report DryRunReport, by string) (*State, error) {
	st, err := s.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	report.TenantID = tenantID
	ApplyProposal(st, report, by, s.now())
	if err := s.save(ctx, st); err != nil {
		return nil, err
	}
	return st, nil
}

// GroupKeyForTests exposes ResolveForReport for aggregation tests.
func GroupTotals(mapper func(raw string) (code, display string), rows []struct {
	Raw   string
	Value float64
}) map[string]float64 {
	out := map[string]float64{}
	for _, r := range rows {
		code, _ := mapper(r.Raw)
		out[code] += r.Value
	}
	return out
}

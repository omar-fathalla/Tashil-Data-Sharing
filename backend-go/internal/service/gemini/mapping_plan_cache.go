package gemini

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode"
)

// mappingPlanCacheVersion is the on-disk envelope version. Bump when the wrapper
// shape changes in a breaking way; get() ignores entries with a different version
// so callers re-infer instead of applying a stale schema.
const mappingPlanCacheVersion = 1

// Plan cache entry sources recorded in the versioned envelope.
const (
	planCacheSourceAI         = "ai"
	planCacheSourceCorrection = "correction"
)

// mappingPlanCacheState is the shared mem/disk store behind every tenant view.
type mappingPlanCacheState struct {
	mu  sync.Mutex
	mem map[string][]byte
	dir string
}

// mappingPlanCache keeps accepted AI column-mapping plans keyed by a hash of the exact prompt (file name + the
// sampled header rows). Re-reading an archived file (startup archive sync, replays on other instances) reuses
// the stored interpretation instead of calling Gemini again. With a directory (the shared archive mount) the
// plans survive restarts and are shared by every instance.
//
// On disk (v1+) entries are a versioned envelope; legacy bare ColumnMapPlan JSON is still readable.
// When tenant is set, keys/paths are namespaced per tenant so corrections cannot leak across tenants.
type mappingPlanCache struct {
	state  *mappingPlanCacheState
	tenant string
}

// cachedMappingPlan is the versioned on-disk / in-memory envelope around a ColumnMapPlan.
type cachedMappingPlan struct {
	Version   int           `json:"v"`
	Source    string        `json:"source,omitempty"`     // "ai" | "correction"
	LearnedAt string        `json:"learned_at,omitempty"` // RFC3339 when source=correction
	Plan      ColumnMapPlan `json:"plan"`
}

func newMappingPlanCache() mappingPlanCache {
	return mappingPlanCache{state: &mappingPlanCacheState{}}
}

func mappingPlanKey(prompt string) string {
	sum := sha256.Sum256([]byte(prompt))
	return hex.EncodeToString(sum[:])
}

func normalizeMappingTenant(tenantID string) string {
	t := strings.TrimSpace(strings.ToLower(tenantID))
	t = strings.TrimPrefix(t, "tenant-")
	t = strings.TrimPrefix(t, "tenant_")
	return strings.TrimSpace(t)
}

func sanitizeTenantSegment(tenantID string) string {
	t := normalizeMappingTenant(tenantID)
	if t == "" {
		return ""
	}
	var b strings.Builder
	for _, r := range t {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' || r == '_' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	out := b.String()
	if out == "" {
		return "_unknown"
	}
	return out
}

func (c *mappingPlanCache) ensureState() *mappingPlanCacheState {
	if c.state == nil {
		c.state = &mappingPlanCacheState{}
	}
	return c.state
}

// storageKey namespaces the content hash under the tenant when set.
func (c *mappingPlanCache) storageKey(contentKey string) string {
	if seg := sanitizeTenantSegment(c.tenant); seg != "" {
		return seg + "/" + contentKey
	}
	return contentKey
}

func (c *mappingPlanCache) path(contentKey string) string {
	st := c.ensureState()
	if st.dir == "" {
		return ""
	}
	return filepath.Join(st.dir, c.storageKey(contentKey)+".json")
}

func (c *mappingPlanCache) get(key string) (*ColumnMapPlan, bool) {
	plan, _, ok := c.getEntry(key)
	return plan, ok
}

// getEntry returns the plan and its recorded source ("ai", "correction", or "" for legacy).
func (c *mappingPlanCache) getEntry(key string) (*ColumnMapPlan, string, bool) {
	st := c.ensureState()
	sk := c.storageKey(key)
	st.mu.Lock()
	raw, ok := st.mem[sk]
	st.mu.Unlock()
	if !ok {
		if p := c.path(key); p != "" {
			if b, err := os.ReadFile(p); err == nil {
				raw, ok = b, true
			}
		}
	}
	if !ok {
		return nil, "", false
	}
	plan, source, ok := decodeCachedMappingPlan(raw)
	if !ok {
		return nil, "", false
	}
	return plan, source, true
}

// decodeCachedMappingPlan accepts versioned envelopes and legacy bare ColumnMapPlan JSON.
// Entries with an unsupported envelope version are treated as a miss.
func decodeCachedMappingPlan(raw []byte) (*ColumnMapPlan, string, bool) {
	var env cachedMappingPlan
	if err := json.Unmarshal(raw, &env); err == nil && env.Version != 0 {
		if env.Version != mappingPlanCacheVersion {
			return nil, "", false
		}
		if env.Plan.Layout == "" || len(env.Plan.Columns) == 0 {
			return nil, "", false
		}
		cp := env.Plan
		return &cp, env.Source, true
	}
	// Legacy: bare ColumnMapPlan written before versioning.
	plan := &ColumnMapPlan{}
	if err := json.Unmarshal(raw, plan); err != nil {
		return nil, "", false
	}
	if plan.Layout == "" || len(plan.Columns) == 0 {
		return nil, "", false
	}
	return plan, "", true
}

func (c *mappingPlanCache) put(key string, plan *ColumnMapPlan) {
	// AI infer path cannot fail the upload on a cache write; log only.
	if err := c.putWithSource(key, plan, planCacheSourceAI, ""); err != nil {
		log.Printf("[ingest-mapping] plan cache write failed: %v", err)
	}
}

func (c *mappingPlanCache) putWithSource(key string, plan *ColumnMapPlan, source, learnedAt string) error {
	if plan == nil {
		return fmt.Errorf("mapping plan cache: plan is nil")
	}
	env := cachedMappingPlan{
		Version:   mappingPlanCacheVersion,
		Source:    source,
		LearnedAt: learnedAt,
		Plan:      *plan,
	}
	raw, err := json.Marshal(env)
	if err != nil {
		return fmt.Errorf("mapping plan cache marshal: %w", err)
	}
	st := c.ensureState()
	sk := c.storageKey(key)
	st.mu.Lock()
	dir := st.dir
	st.mu.Unlock()

	// When a shared dir is configured, durable disk write must succeed before mem update
	// so LearnFromCorrection never reports success without persistence.
	if dir != "" {
		p := filepath.Join(dir, sk+".json")
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return fmt.Errorf("mapping plan cache mkdir: %w", err)
		}
		if err := os.WriteFile(p, raw, 0o644); err != nil {
			return fmt.Errorf("mapping plan cache write: %w", err)
		}
	}

	st.mu.Lock()
	if st.mem == nil {
		st.mem = map[string][]byte{}
	}
	st.mem[sk] = raw
	st.mu.Unlock()
	return nil
}

// learnCorrection stores a human-corrected plan under the same prompt key, overwriting any AI entry.
func (c *mappingPlanCache) learnCorrection(key string, plan *ColumnMapPlan) error {
	return c.putWithSource(key, plan, planCacheSourceCorrection, time.Now().UTC().Format(time.RFC3339))
}

// forTenant returns a Client view that namespaces the shared plan cache under tenantID.
// Same underlying mem/dir; safe for concurrent tenants.
func (c *Client) forTenant(tenantID string) *Client {
	if c == nil {
		return nil
	}
	out := *c
	st := c.planCache.ensureState()
	out.planCache = mappingPlanCache{state: st, tenant: normalizeMappingTenant(tenantID)}
	return &out
}

// WithMappingPlanDir persists accepted column-mapping plans under dir so archive re-reads skip Gemini.
func (c *Client) WithMappingPlanDir(dir string) *Client {
	st := c.planCache.ensureState()
	st.mu.Lock()
	st.dir = dir
	st.mu.Unlock()
	return c
}

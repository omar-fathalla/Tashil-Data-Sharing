package gemini

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"
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

// mappingPlanCache keeps accepted AI column-mapping plans keyed by a hash of the exact prompt (file name + the
// sampled header rows). Re-reading an archived file (startup archive sync, replays on other instances) reuses
// the stored interpretation instead of calling Gemini again. With a directory (the shared archive mount) the
// plans survive restarts and are shared by every instance.
//
// On disk (v1+) entries are a versioned envelope; legacy bare ColumnMapPlan JSON is still readable.
type mappingPlanCache struct {
	mu  sync.Mutex
	mem map[string][]byte
	dir string
}

// cachedMappingPlan is the versioned on-disk / in-memory envelope around a ColumnMapPlan.
type cachedMappingPlan struct {
	Version   int           `json:"v"`
	Source    string        `json:"source,omitempty"` // "ai" | "correction"
	LearnedAt string        `json:"learned_at,omitempty"` // RFC3339 when source=correction
	Plan      ColumnMapPlan `json:"plan"`
}

func mappingPlanKey(prompt string) string {
	sum := sha256.Sum256([]byte(prompt))
	return hex.EncodeToString(sum[:])
}

func (c *mappingPlanCache) path(key string) string {
	if c.dir == "" {
		return ""
	}
	return filepath.Join(c.dir, key+".json")
}

func (c *mappingPlanCache) get(key string) (*ColumnMapPlan, bool) {
	plan, _, ok := c.getEntry(key)
	return plan, ok
}

// getEntry returns the plan and its recorded source ("ai", "correction", or "" for legacy).
func (c *mappingPlanCache) getEntry(key string) (*ColumnMapPlan, string, bool) {
	c.mu.Lock()
	raw, ok := c.mem[key]
	c.mu.Unlock()
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
	c.putWithSource(key, plan, planCacheSourceAI, "")
}

func (c *mappingPlanCache) putWithSource(key string, plan *ColumnMapPlan, source, learnedAt string) {
	if plan == nil {
		return
	}
	env := cachedMappingPlan{
		Version:   mappingPlanCacheVersion,
		Source:    source,
		LearnedAt: learnedAt,
		Plan:      *plan,
	}
	raw, err := json.Marshal(env)
	if err != nil {
		return
	}
	c.mu.Lock()
	if c.mem == nil {
		c.mem = map[string][]byte{}
	}
	c.mem[key] = raw
	c.mu.Unlock()
	if p := c.path(key); p != "" {
		if err := os.MkdirAll(c.dir, 0o755); err == nil {
			if err := os.WriteFile(p, raw, 0o644); err != nil {
				log.Printf("[ingest-mapping] plan cache write failed: %v", err)
			}
		}
	}
}

// learnCorrection stores a human-corrected plan under the same prompt key, overwriting any AI entry.
func (c *mappingPlanCache) learnCorrection(key string, plan *ColumnMapPlan) {
	c.putWithSource(key, plan, planCacheSourceCorrection, time.Now().UTC().Format(time.RFC3339))
}

// WithMappingPlanDir persists accepted column-mapping plans under dir so archive re-reads skip Gemini.
func (c *Client) WithMappingPlanDir(dir string) *Client {
	c.planCache.mu.Lock()
	c.planCache.dir = dir
	c.planCache.mu.Unlock()
	return c
}

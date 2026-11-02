package gemini

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sync"
)

// mappingPlanCache keeps accepted AI column-mapping plans keyed by a hash of the exact prompt (file name + the
// sampled header rows). Re-reading an archived file (startup archive sync, replays on other instances) reuses
// the stored interpretation instead of calling Gemini again. With a directory (the shared archive mount) the
// plans survive restarts and are shared by every instance.
type mappingPlanCache struct {
	mu  sync.Mutex
	mem map[string][]byte
	dir string
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
		return nil, false
	}
	plan := &ColumnMapPlan{}
	if err := json.Unmarshal(raw, plan); err != nil {
		return nil, false
	}
	return plan, true
}

func (c *mappingPlanCache) put(key string, plan *ColumnMapPlan) {
	raw, err := json.Marshal(plan)
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

// WithMappingPlanDir persists accepted column-mapping plans under dir so archive re-reads skip Gemini.
func (c *Client) WithMappingPlanDir(dir string) *Client {
	c.planCache.mu.Lock()
	c.planCache.dir = dir
	c.planCache.mu.Unlock()
	return c
}

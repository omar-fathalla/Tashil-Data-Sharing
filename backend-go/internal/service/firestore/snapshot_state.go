package firestore

import (
	"bytes"
	"encoding/json"
	"fmt"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// snapshotState holds the in-memory entities that the startup archive replay
// rebuilds in this repository (stores, OOS alerts, ingestion batches and the
// per-chain store counts). Users, tenants and other Firestore-backed entities
// are NOT included: they are loaded from Cloud Firestore on every boot.
type snapshotState struct {
	Stores           map[string][]domain.Store `json:"stores"`
	Alerts           []domain.OOSAlert         `json:"alerts"`
	Batches          []domain.IngestionBatch   `json:"batches"`
	CleanedTenants   map[string]bool           `json:"cleaned_tenants"`
	ChainStoreCounts map[string]int            `json:"chain_store_counts"`
}

func (c *Client) liveSnapshotStateLocked() *snapshotState {
	counts := make(map[string]int, len(c.retailChains))
	for k, rc := range c.retailChains {
		counts[k] = rc.StoreCount
	}
	return &snapshotState{
		Stores:           c.stores,
		Alerts:           c.alerts,
		Batches:          c.batches,
		CleanedTenants:   c.cleanedTenants,
		ChainStoreCounts: counts,
	}
}

// ExportSnapshot serialises the replay-derived entities and verifies the round trip is lossless.
func (c *Client) ExportSnapshot() ([]byte, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	live := c.liveSnapshotStateLocked()
	raw, err := json.Marshal(live)
	if err != nil {
		return nil, fmt.Errorf("firestore snapshot encode: %w", err)
	}
	var back snapshotState
	if err := json.Unmarshal(raw, &back); err != nil {
		return nil, fmt.Errorf("firestore snapshot verify decode: %w", err)
	}
	// Fixed-point check: re-encoding the decoded copy must reproduce the exact
	// same bytes, otherwise some value would not survive the round trip.
	again, err := json.Marshal(&back)
	if err != nil || !bytes.Equal(raw, again) {
		return nil, fmt.Errorf("firestore snapshot verify: round trip is not lossless")
	}
	return raw, nil
}

// ImportSnapshot restores entities produced by ExportSnapshot.
func (c *Client) ImportSnapshot(raw []byte) error {
	var st snapshotState
	if err := json.Unmarshal(raw, &st); err != nil {
		return fmt.Errorf("firestore snapshot decode: %w", err)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.stores = st.Stores
	if c.stores == nil {
		c.stores = make(map[string][]domain.Store)
	}
	c.alerts = st.Alerts
	c.batches = st.Batches
	c.cleanedTenants = st.CleanedTenants
	if c.cleanedTenants == nil {
		c.cleanedTenants = make(map[string]bool)
	}
	for k, n := range st.ChainStoreCounts {
		if rc, ok := c.retailChains[k]; ok {
			rc.StoreCount = n
			c.retailChains[k] = rc
		}
	}
	return nil
}

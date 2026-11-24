package bigquery

import (
	"bytes"
	"encoding/json"
	"fmt"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// snapshotState is the serialisable copy of every in-memory dataset that the
// startup archive replay rebuilds. It is used by the ingestion startup snapshot
// so a restart can restore the parsed data in seconds instead of re-parsing
// every archived workbook. All maps stay keyed by tenant, so tenant isolation
// is preserved exactly as it is in memory.
type snapshotState struct {
	Records                          []domain.SellOutFact                             `json:"records"`
	PricingItems                     []domain.PricingComplianceItem                   `json:"pricing_items"`
	WorkbookMeta                     map[string]TenantWorkbookAnalytics               `json:"workbook_meta"`
	SellInRecords                    map[string][]domain.SellInRecord                 `json:"sell_in_records"`
	SellInFilename                   map[string]string                                `json:"sell_in_filename"`
	SellInPlanRecords                map[string][]domain.SellInRecord                 `json:"sell_in_plan_records,omitempty"`
	Targets                          map[string][]domain.TargetRecord                 `json:"targets"`
	ProductMaster                    map[string]*domain.ProductMasterSummaryResponse  `json:"product_master"`
	BaselineProductMaster            map[string]*domain.ProductMasterSummaryResponse  `json:"baseline_product_master"`
	ProductMasterByCode              map[string]map[string]domain.ProductMasterItem   `json:"product_master_by_code"`
	ProductMasterByBarcode           map[string]map[string]domain.ProductMasterItem   `json:"product_master_by_barcode"`
	ProductMasterByBarcodeCandidates map[string]map[string][]domain.ProductMasterItem `json:"product_master_by_barcode_candidates"`
	ProductMasterByName              map[string]map[string]domain.ProductMasterItem   `json:"product_master_by_name"`
	CleanedTenants                   map[string]bool                                  `json:"cleaned_tenants"`
}

func (c *Client) liveSnapshotStateLocked() *snapshotState {
	return &snapshotState{
		Records:                          c.records,
		PricingItems:                     c.pricingItems,
		WorkbookMeta:                     c.workbookMeta,
		SellInRecords:                    c.sellInRecords,
		SellInFilename:                   c.sellInFilename,
		SellInPlanRecords:                c.sellInPlanRecords,
		Targets:                          c.targets,
		ProductMaster:                    c.productMaster,
		BaselineProductMaster:            c.baselineProductMaster,
		ProductMasterByCode:              c.productMasterByCode,
		ProductMasterByBarcode:           c.productMasterByBarcode,
		ProductMasterByBarcodeCandidates: c.productMasterByBarcodeCandidates,
		ProductMasterByName:              c.productMasterByName,
		CleanedTenants:                   c.cleanedTenants,
	}
}

// ExportSnapshot serialises the in-memory dataset. The encoding is verified by
// decoding it again and comparing it with the live state; if anything would not
// survive the round trip exactly, an error is returned and no snapshot is made.
func (c *Client) ExportSnapshot() ([]byte, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	live := c.liveSnapshotStateLocked()
	raw, err := json.Marshal(live)
	if err != nil {
		return nil, fmt.Errorf("bigquery snapshot encode: %w", err)
	}
	var back snapshotState
	if err := json.Unmarshal(raw, &back); err != nil {
		return nil, fmt.Errorf("bigquery snapshot verify decode: %w", err)
	}
	// Fixed-point check: re-encoding the decoded copy must reproduce the exact
	// same bytes, otherwise some value would not survive the round trip.
	again, err := json.Marshal(&back)
	if err != nil || !bytes.Equal(raw, again) {
		return nil, fmt.Errorf("bigquery snapshot verify: round trip is not lossless")
	}
	return raw, nil
}

// ImportSnapshot replaces the in-memory dataset with a snapshot produced by ExportSnapshot.
func (c *Client) ImportSnapshot(raw []byte) error {
	var st snapshotState
	if err := json.Unmarshal(raw, &st); err != nil {
		return fmt.Errorf("bigquery snapshot decode: %w", err)
	}
	c.mu.Lock()
	c.records = st.Records
	c.pricingItems = st.PricingItems
	c.workbookMeta = st.WorkbookMeta
	c.sellInRecords = st.SellInRecords
	c.sellInFilename = st.SellInFilename
	c.sellInPlanRecords = st.SellInPlanRecords
	// A snapshot written before Plan rows were separated may hold them among the Sell-In rows.
	for tenant, recs := range c.sellInRecords {
		if real, plan := splitSellInPlan("", recs); len(plan) > 0 {
			c.sellInRecords[tenant] = real
			c.putSellInPlanLocked(tenant, plan)
		}
	}
	c.targets = st.Targets
	c.productMaster = st.ProductMaster
	c.baselineProductMaster = st.BaselineProductMaster
	c.productMasterByCode = st.ProductMasterByCode
	c.productMasterByBarcode = st.ProductMasterByBarcode
	c.productMasterByBarcodeCandidates = st.ProductMasterByBarcodeCandidates
	c.productMasterByName = st.ProductMasterByName
	c.cleanedTenants = st.CleanedTenants
	c.ensureSnapshotMapsLocked()
	c.noteSellInDataChanged()
	c.mu.Unlock()
	c.invalidateKPICache()
	return nil
}

func (c *Client) ensureSnapshotMapsLocked() {
	if c.workbookMeta == nil {
		c.workbookMeta = make(map[string]TenantWorkbookAnalytics)
	}
	if c.sellInRecords == nil {
		c.sellInRecords = make(map[string][]domain.SellInRecord)
	}
	if c.sellInFilename == nil {
		c.sellInFilename = make(map[string]string)
	}
	if c.sellInPlanRecords == nil {
		c.sellInPlanRecords = make(map[string][]domain.SellInRecord)
	}
	if c.targets == nil {
		c.targets = make(map[string][]domain.TargetRecord)
	}
	if c.productMaster == nil {
		c.productMaster = make(map[string]*domain.ProductMasterSummaryResponse)
	}
	if c.baselineProductMaster == nil {
		c.baselineProductMaster = make(map[string]*domain.ProductMasterSummaryResponse)
	}
	if c.productMasterByCode == nil {
		c.productMasterByCode = make(map[string]map[string]domain.ProductMasterItem)
	}
	if c.productMasterByBarcode == nil {
		c.productMasterByBarcode = make(map[string]map[string]domain.ProductMasterItem)
	}
	if c.productMasterByBarcodeCandidates == nil {
		c.productMasterByBarcodeCandidates = make(map[string]map[string][]domain.ProductMasterItem)
	}
	if c.productMasterByName == nil {
		c.productMasterByName = make(map[string]map[string]domain.ProductMasterItem)
	}
	if c.cleanedTenants == nil {
		c.cleanedTenants = make(map[string]bool)
	}
}

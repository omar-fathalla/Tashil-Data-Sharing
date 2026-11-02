package dataquality

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Sell-In upload findings shown on the data-quality page.
const (
	DQSourceSellInUploadPrefix = "sellin_upload:"
	DQTypeUnknownItem          = "unknown_item"
)

// UnknownItem is a Sell-In item without a Product Master match (the rows are kept and counted).
type UnknownItem struct {
	ItemCode, Barcode, ItemName string
	Rows                        int
	Value                       float64
}

// RecordSellInUnknownItems replaces the unknown-item issues of one uploaded file. Issues of other
// sources and other files are untouched; items of this file that are now known auto-close.
func (s *Service) RecordSellInUnknownItems(ctx context.Context, tenantID, filename string, items []UnknownItem) error {
	source := DQSourceSellInUploadPrefix + strings.TrimSpace(filename)
	found := make([]domain.DataQualityIssue, 0, len(items))
	for _, it := range items {
		v := it.Value
		found = append(found, domain.DataQualityIssue{
			ID:            issueID(source, DQTypeUnknownItem, it.ItemCode, it.Barcode, it.ItemName),
			Source:        source,
			Type:          DQTypeUnknownItem,
			TypeLabel:     "صنف مش موجود في كارتة الأصناف",
			Severity:      domain.DQSeverityWarning,
			Sheet:         filename,
			Column:        "كود الصنف / الباركود",
			ItemCode:      it.ItemCode,
			Barcode:       it.Barcode,
			SKUName:       it.ItemName,
			FoundValue:    fmt.Sprintf("%d صف", it.Rows),
			ExpectedValue: "الصنف يتضاف لكارتة الأصناف",
			ImpactEGP:     &v,
			ImpactBasis:   "قيمة صفوف الصنف في الملف (الصفوف محفوظة ومن غير سعر رسمي)",
			SourceFile:    filename,
		})
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, err := s.store.GetDataQualityState(ctx, tenantID)
	if err != nil {
		return err
	}
	Reconcile(st, source, found, s.now())
	st.TenantID = tenantID
	if err := s.store.SaveDataQualityState(ctx, st); err != nil {
		return err
	}
	log.Printf("[data-quality] tenant=%s sell-in %s: %d items not in the Product Master", tenantID, filename, len(items))
	return nil
}

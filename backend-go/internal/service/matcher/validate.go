package matcher

import (
	"fmt"
)

// ValidateChosen ensures an approve decision's item code / barcode pair exists on
// the tenant Product Master catalog. Empty barcode is allowed (unknown GTIN kept
// empty — never invented). A non-empty barcode must belong to the chosen item
// (or to any SKU sharing that exact GTIN that includes the chosen item code).
func (c *Catalog) ValidateChosen(itemCode, barcode string) error {
	code := normalizeItemCode(itemCode)
	bc := cleanBarcode(barcode)

	if c == nil || c.Len() == 0 {
		if code != "" || bc != "" {
			return fmt.Errorf("كارتة الأصناف غير محمّلة — لا يمكن اعتماد كود/باركود")
		}
		return nil
	}

	if code == "" && bc == "" {
		return nil
	}

	if code != "" {
		if _, ok := c.byCode[code]; !ok {
			return fmt.Errorf("كود الصنف %s غير موجود في كارتة الأصناف", code)
		}
	}

	if bc == "" {
		return nil
	}

	cands := c.byBarcode[bc]
	if len(cands) == 0 {
		return fmt.Errorf("الباركود %s غير موجود في كارتة الأصناف لهذا المستأجر", bc)
	}

	if code == "" {
		return nil // barcode alone is in master
	}

	for _, it := range cands {
		if normalizeItemCode(it.ItemCode) == code {
			return nil
		}
	}
	// Also allow when the chosen item's own barcode field matches (primary map).
	if it, ok := c.byCode[code]; ok && cleanBarcode(it.Barcode) == bc {
		return nil
	}
	return fmt.Errorf("الباركود %s لا يخص الكود %s في كارتة الأصناف", bc, code)
}

// HasBarcode reports whether the cleaned barcode exists on this tenant catalog.
func (c *Catalog) HasBarcode(barcode string) bool {
	if c == nil {
		return false
	}
	bc := cleanBarcode(barcode)
	if bc == "" {
		return false
	}
	return len(c.byBarcode[bc]) > 0
}

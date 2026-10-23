package gemini

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestParseProductMasterWorkbook_SeedFile(t *testing.T) {
	seedXLSX := "/Users/fathalla/.gemini/antigravity/brain/26f9f76f-c46f-46ac-83aa-5b20f751b218/.user_uploaded/media_1792693286917_0c8098d4.xlsx"
	rawBytes, err := os.ReadFile(seedXLSX)
	if err != nil {
		// Fallback to repo copy if running in environment without brain dir
		repoCopy := filepath.Join("..", "..", "..", "data", "product_master", "adeco_product_master_2026_08_01.xlsx")
		rawBytes, err = os.ReadFile(repoCopy)
		if err != nil {
			t.Skipf("seed xlsx not found at %s or %s: %v", seedXLSX, repoCopy, err)
		}
	}

	if !IsProductMasterWorkbook(rawBytes) {
		t.Fatalf("expected IsProductMasterWorkbook to return true for Adeco Product Master sheet")
	}

	res, err := ParseProductMasterWorkbook("tenant-adeco", "تحديث قائمة أسعار كرتة الأصناف 01-08-2026.xlsx", rawBytes)
	if err != nil {
		t.Fatalf("ParseProductMasterWorkbook failed: %v", err)
	}

	if res.TotalSKUs != 389 {
		t.Fatalf("expected 389 total SKUs, got %d", res.TotalSKUs)
	}
	if res.RegularSKUsCount != 280 || res.PromoSKUsCount != 109 {
		t.Fatalf("expected 280 regular and 109 promo SKUs, got regular=%d promo=%d", res.RegularSKUsCount, res.PromoSKUsCount)
	}

	// Verify first SKU FGCL-0550-0001
	first := res.Items[0]
	if first.ItemCode != "FGCL-0550-0001" {
		t.Errorf("expected first ItemCode FGCL-0550-0001, got %s", first.ItemCode)
	}
	if first.Barcode != "6223000231227" {
		t.Errorf("expected first Barcode 6223000231227, got %s", first.Barcode)
	}
	if first.UnitsPerCarton != 20 {
		t.Errorf("expected UnitsPerCarton 20, got %d", first.UnitsPerCarton)
	}
	if !first.IsPrimaryForBarcode {
		t.Errorf("expected FGCL-0550-0001 to be IsPrimaryForBarcode=true")
	}

	if first.ERPPrefix != "FGCL" {
		t.Errorf("expected first ERPPrefix FGCL, got %s", first.ERPPrefix)
	}
	if first.DepartmentAr == "" {
		t.Errorf("expected non-empty DepartmentAr for FGCL-0550-0001")
	}

	// Verify FGGC Glassy items are classified as Glass Cleaner ("ملمع زجاج وكريستال") and brand "جلاسي (Glassy)"
	foundGlassy := false
	for _, it := range res.Items {
		if it.ItemCode == "FGGC-0600-0007" {
			foundGlassy = true
			if it.Brand != "جلاسي (Glassy)" {
				t.Errorf("expected FGGC-0600-0007 Brand 'جلاسي (Glassy)', got %q", it.Brand)
			}
			if it.Category != "ملمع زجاج وكريستال" {
				t.Errorf("expected FGGC-0600-0007 Category 'ملمع زجاج وكريستال', got %q", it.Category)
			}
		}
	}
	if !foundGlassy {
		t.Errorf("expected to find FGGC-0600-0007 in parsed Product Master")
	}

	// Verify search helper on ItemCode, Barcode, and phonetic FGSL alias
	if !domain.MatchesProductSearchQuery("FGCL-0550", first.ItemCode, first.Barcode, first.OfficialName, first.OfficialName, first.Category, first.Brand) {
		t.Errorf("expected MatchesProductSearchQuery to match FGCL-0550")
	}
	if !domain.MatchesProductSearchQuery("fgsl", first.ItemCode, first.Barcode, first.OfficialName, first.OfficialName, first.Category, first.Brand) {
		t.Errorf("expected MatchesProductSearchQuery to match phonetic alias fgsl")
	}
	if !domain.MatchesProductSearchQuery("6223000231227", first.ItemCode, first.Barcode, first.OfficialName, first.OfficialName, first.Category, first.Brand) {
		t.Errorf("expected MatchesProductSearchQuery to match barcode 6223000231227")
	}

	// Write canonical seed JSON and XLSX copy if missing or updated
	outDir := filepath.Join("..", "..", "..", "data", "product_master")
	if err := os.MkdirAll(outDir, 0o755); err == nil {
		jsonBytes, err := json.MarshalIndent(res, "", "  ")
		if err == nil {
			_ = os.WriteFile(filepath.Join(outDir, "tenant-adeco.json"), jsonBytes, 0o644)
		}
		xlsxDest := filepath.Join(outDir, "adeco_product_master_2026_08_01.xlsx")
		if _, statErr := os.Stat(xlsxDest); os.IsNotExist(statErr) {
			_ = os.WriteFile(xlsxDest, rawBytes, 0o644)
		}
	}
}

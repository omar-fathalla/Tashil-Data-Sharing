package dataquality

import (
	"sync"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

type fakeMaster struct {
	mu    sync.Mutex
	items []domain.ProductMasterItem
}

func (f *fakeMaster) set(it []domain.ProductMasterItem) { f.mu.Lock(); f.items = it; f.mu.Unlock() }
func (f *fakeMaster) GetProductMasterItems(string) []domain.ProductMasterItem {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.items
}

func parsedItems(t *testing.T, raw []byte) []domain.ProductMasterItem {
	res, err := gemini.ParseProductMasterWorkbook("", "m.xlsx", raw)
	if err != nil {
		t.Fatal(err)
	}
	return res.Items
}

package bigquery

import (
	"context"
	"errors"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestSetSellInRecordsRejectsMissingPeriod(t *testing.T) {
	c := NewClient("test-proj", "test-dataset", true)
	err := c.SetSellInRecords(context.Background(), "tenant-adeco", "x.xlsx", []domain.SellInRecord{{Year: 0, MonthNum: 4, NetValueEGP: 1}})
	var pe *SellInMissingPeriodError
	if !errors.As(err, &pe) || pe.Rows != 1 {
		t.Fatalf("expected rejection, got %v", err)
	}
	if n := len(c.SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("nothing may be stored (no 2026 default), got %d", n)
	}
}

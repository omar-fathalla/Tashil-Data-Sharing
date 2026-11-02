package bqsink

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestStreamSellInDropsRowsWithoutPeriod(t *testing.T) {
	in := []domain.SellInRecord{{Year: 2026, MonthNum: 3}, {Year: 0, MonthNum: 3}, {Year: 2026, MonthNum: 0}, {Year: 2027, MonthNum: 12}}
	out := validSellInPeriods(in)
	if len(out) != 2 || out[1].Year != 2027 {
		t.Fatalf("got %+v (a row without a period must never become 2026)", out)
	}
}

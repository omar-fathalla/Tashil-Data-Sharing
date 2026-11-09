package bqsink

import (
	"strings"
	"testing"
)

func TestSellInArchivePeriodCountsSQL(t *testing.T) {
	sql := SellInArchivePeriodCountsSQL("`p.d.sell_in_records`")
	for _, want := range []string{
		"tenant_id = @tenant_id",
		"archive_id = @archive_id",
		"period_month",
		"SUM(IFNULL(net_value_egp, 0))",
		"GROUP BY 1",
	} {
		if !strings.Contains(sql, want) {
			t.Fatalf("missing %q in %s", want, sql)
		}
	}
	if strings.Contains(sql, "NOT IN UNNEST") || strings.Contains(sql, "orphan") {
		t.Fatal("period counts must not touch orphan cleanup")
	}
}

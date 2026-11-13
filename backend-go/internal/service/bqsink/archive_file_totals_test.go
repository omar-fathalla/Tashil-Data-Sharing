package bqsink

import (
	"strings"
	"testing"
)

func TestArchiveFileTotalsSQL(t *testing.T) {
	out := ArchiveFileTotalsSQL(KindSellOut, "`p.d.sell_out_facts`")
	for _, want := range []string{
		"COUNT(*) n",
		"SUM(IF(IFNULL(is_own_brand, FALSE) OR IFNULL(supplier, '') = '', quantity_sold, 0))",
		"WHERE tenant_id = @tenant_id GROUP BY 1, 2",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("sell-out SQL missing %q: %s", want, out)
		}
	}
	in := ArchiveFileTotalsSQL(KindSellIn, "`p.d.sell_in_records`")
	if !strings.Contains(in, "SUM(net_qty_cases)") || !strings.Contains(in, "SUM(weight_tons)") || strings.Contains(in, "quantity_sold") {
		t.Fatalf("sell-in SQL: %s", in)
	}
	pm := ArchiveFileTotalsSQL(KindProductMaster, "`p.d.pm`")
	if strings.Contains(pm, "SUM(") {
		t.Fatalf("product master SQL must only count rows: %s", pm)
	}
	for _, s := range []string{out, in, pm} {
		u := strings.ToUpper(s)
		if !strings.HasPrefix(u, "SELECT ") || strings.Contains(u, "DELETE") || strings.Contains(u, "INSERT") || strings.Contains(u, "UPDATE") {
			t.Fatalf("must be a read-only SELECT: %s", s)
		}
	}
}

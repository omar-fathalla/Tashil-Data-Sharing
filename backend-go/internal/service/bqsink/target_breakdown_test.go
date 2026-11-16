package bqsink

import (
	"strings"
	"testing"
)

func TestTargetBreakdownSQLIsReadOnlyAndDeduped(t *testing.T) {
	where, params := RecordsFilterSQL(RecordsQuery{TenantID: "tenant-adeco", Chain: "fathalla"})
	for name, q := range map[string]string{
		"coverage":  TargetCoverageSQL("`p.d.sell_out_facts`", where),
		"breakdown": TargetBreakdownSQL("`p.d.sell_out_facts`", where),
	} {
		up := strings.ToUpper(q)
		for _, bad := range []string{"INSERT ", "UPDATE ", "DELETE ", "MERGE ", "DROP ", "CREATE ", "TRUNCATE "} {
			if strings.Contains(up, bad) {
				t.Errorf("%s must be read-only, found %q", name, bad)
			}
		}
		if !strings.Contains(q, "tenant_id = @tenant_id") {
			t.Errorf("%s not tenant scoped", name)
		}
		if !strings.Contains(q, "QUALIFY ROW_NUMBER() OVER (PARTITION BY IFNULL(t.record_id, GENERATE_UUID())") {
			t.Errorf("%s must read through the deduplicating serving view", name)
		}
		if strings.Contains(q, "ORDER BY ingested_at, record_id") {
			t.Errorf("%s keeps the serving-view ORDER BY", name)
		}
		if !strings.Contains(q, "is_own_brand") {
			t.Errorf("%s must keep the own-SKU rule", name)
		}
	}
	names := map[string]bool{}
	for _, p := range params {
		names[p.Name] = true
	}
	if !names["tenant_id"] || !names["chain"] {
		t.Errorf("params %v", names)
	}
}

func TestTargetBreakdownSQLAggregatesBothWindowsInOnePass(t *testing.T) {
	q := TargetBreakdownSQL("`p.d.sell_out_facts`", "TRUE")
	for _, want := range []string{
		"transaction_date BETWEEN @b_start AND @b_end",
		"transaction_date BETWEEN @a_start AND @a_end",
		"SUM(IF(transaction_date BETWEEN @b_start AND @b_end, net_revenue, 0)), 0) base_rev",
		"SUM(IF(transaction_date BETWEEN @a_start AND @a_end, net_revenue, 0)), 0) act_rev",
		"COUNTIF(transaction_date BETWEEN @a_start AND @a_end) act_rows",
		"GROUP BY 1, 4, 5, 6",
		"IFNULL(COALESCE(NULLIF(store_id, ''), NULLIF(store_name, '')), '') store_key",
	} {
		if !strings.Contains(q, want) {
			t.Errorf("breakdown SQL missing %q:\n%s", want, q)
		}
	}
}

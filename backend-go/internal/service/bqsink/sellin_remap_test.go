package bqsink

import (
	"strings"
	"testing"
)

func TestRemapSellInCustomerSQLIsExactAndTenantScoped(t *testing.T) {
	sql := RemapSellInCustomerSQL("`p.d.sell_in_records`")
	if err := RemapSQLGuard(sql); err != nil {
		t.Fatal(err)
	}
	for _, must := range []string{
		"tenant_id = @tenant_id",
		"customer_name = @from_name",
		"customer_name = @to_name",
		"customer_branch_code = @to_branch",
		"IFNULL(chain_key, '') = @chain",
	} {
		if !strings.Contains(sql, must) {
			t.Fatalf("missing %q in %s", must, sql)
		}
	}
	if strings.Contains(strings.ToLower(sql), "like") || strings.Contains(sql, "NORMALIZE") {
		t.Fatal("remap must stay exact-match only")
	}
}

func TestRestoreSellInCustomerSQLUsesRecordIDs(t *testing.T) {
	sql := RestoreSellInCustomerSQL("`p.d.sell_in_records`")
	if err := RemapSQLGuard(sql); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(sql, "record_id IN UNNEST(@record_ids)") {
		t.Fatalf("restore must key by record_id: %s", sql)
	}
}

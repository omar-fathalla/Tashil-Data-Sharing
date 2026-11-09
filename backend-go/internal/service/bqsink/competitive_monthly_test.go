package bqsink

import (
	"strings"
	"testing"
)

func TestCompetitiveMonthlySQLGroupsByBarcodeMonth(t *testing.T) {
	sql := CompetitiveMonthlySQL("`proj.ds.sell_out_facts`", "TRUE")
	for _, want := range []string{
		"GROUP BY 1, 2",
		"SUBSTR(transaction_date, 1, 7)",
		"unit_price * quantity_sold",
		"TRIM(IFNULL(barcode, ''))",
	} {
		if !strings.Contains(sql, want) {
			t.Fatalf("SQL missing %q:\n%s", want, sql)
		}
	}
	if strings.Contains(sql, "LIMIT @limit") {
		t.Fatal("competitive monthly must not page raw rows")
	}
}

func TestSellOutMonthsSQLDistinctMonths(t *testing.T) {
	sql := SellOutMonthsSQL("`proj.ds.sell_out_facts`")
	for _, want := range []string{
		"DISTINCT",
		"month_num",
		"@year_prefix",
		"BETWEEN 1 AND 12",
	} {
		if !strings.Contains(sql, want) {
			t.Fatalf("SQL missing %q:\n%s", want, sql)
		}
	}
}

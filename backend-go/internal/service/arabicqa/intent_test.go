package arabicqa

import "testing"

func TestClassifyIntent(t *testing.T) {
	cases := []struct {
		q    string
		want Intent
	}{
		{"كام إجمالي المبيعات الشهر ده؟", IntentExecutiveKPIs},
		{"إيه عدد الوحدات المباعة؟", IntentExecutiveKPIs},
		{"وزّع حصص السلاسل", IntentChainShares},
		{"إيه أكبر سلسلة؟", IntentChainShares},
		{"إيه أعلى منتجات مبيعًا؟", IntentTopSKUs},
		{"ورّيني باريتو المنتجات", IntentTopSKUs},
		{"إيه مساهمة كل فئة؟", IntentCategories},
		{"ملخص سيل إن", IntentSellIn},
		{"كام إجمالي التوريد؟", IntentSellIn},
		{"احذف كل البيانات", IntentUnsupported},
		{"", IntentUnsupported},
	}
	for _, tc := range cases {
		if got := classifyIntent(tc.q); got != tc.want {
			t.Fatalf("classifyIntent(%q)=%s want %s", tc.q, got, tc.want)
		}
	}
}

func TestDetectPeriod(t *testing.T) {
	if got := detectPeriod("مبيعات اليوم"); got != "TODAY" {
		t.Fatalf("TODAY: %s", got)
	}
	if got := detectPeriod("كل البيانات"); got != "ALL" {
		t.Fatalf("ALL: %s", got)
	}
	if got := detectPeriod("من أول السنة"); got != "YTD" {
		t.Fatalf("YTD: %s", got)
	}
	if got := detectPeriod("إجمالي المبيعات"); got != "MTD" {
		t.Fatalf("MTD default: %s", got)
	}
}

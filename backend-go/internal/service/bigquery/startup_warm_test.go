package bigquery

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestWarmCommonTenantAnalytics_FillsKPIAndReturnsCache(t *testing.T) {
	c := NewClient("tashil-test", "retail", true)
	_ = c.ClearTenantData(context.Background(), "all")
	c.ReplaceSellInRecords("tenant-adeco", []domain.SellInRecord{
		{RecordID: "1", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: time.Now().Year(), MonthNum: 1, CustomerName: "فرع", CustomerBranchCode: "b1", ItemName: "صنف", ItemCode: "P1", NetValueEGP: 100, NetQtyCases: 10},
		{RecordID: "2", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: time.Now().Year(), MonthNum: 1, CustomerName: "فرع", CustomerBranchCode: "b1", ItemName: "صنف", ItemCode: "P1", NetValueEGP: -10, NetQtyCases: -1, TransactionType: "مرتجع (Return)"},
	})

	c.WarmCommonTenantAnalytics(context.Background(), []string{"tenant-adeco"})

	c.kpiCacheMu.RLock()
	kpiHits := 0
	keys := make([]string, 0, len(c.kpiCache))
	for k, v := range c.kpiCache {
		keys = append(keys, k)
		if v != nil && (strings.Contains(k, "|YTD|") || strings.Contains(k, "|MTD|") ||
			strings.HasSuffix(k, "|YTD") || strings.Contains(k, "|YTD|") || strings.Contains(k, "YTD")) {
			if strings.Contains(k, "YTD") || strings.Contains(k, "MTD") {
				kpiHits++
			}
		}
	}
	c.kpiCacheMu.RUnlock()
	if kpiHits < 1 {
		t.Fatalf("expected warmed YTD/MTD kpiCache entries, got %d keys=%v", kpiHits, keys)
	}

	year := time.Now().Year()
	key := sellInReturnsCacheKey("tenant-adeco", SellInReturnsFilter{Year: year})
	c.returnsCacheMu.RLock()
	ent, ok := c.returnsCache[key]
	ver := ent.version
	retVal := ent.report.KPIs.ReturnsValueEGP
	c.returnsCacheMu.RUnlock()
	if !ok || ver != c.AnalyticsSourceVersion() {
		t.Fatalf("expected warmed returns cache for %s, ok=%v version=%d want=%d", key, ok, ver, c.AnalyticsSourceVersion())
	}
	if retVal != 10 {
		t.Fatalf("warmed returns KPI: %v", retVal)
	}
}

func TestGetSellInReturnsCached_HitAfterWarm(t *testing.T) {
	c := NewClient("tashil-test", "retail", true)
	_ = c.ClearTenantData(context.Background(), "all")
	c.ReplaceSellInRecords("tenant-adeco", []domain.SellInRecord{
		{RecordID: "1", TenantID: "tenant-adeco", Year: 2026, MonthNum: 2, CustomerName: "أ", CustomerBranchCode: "a", ItemName: "x", ItemCode: "X", NetValueEGP: 50, NetQtyCases: 5},
		{RecordID: "2", TenantID: "tenant-adeco", Year: 2026, MonthNum: 2, CustomerName: "أ", CustomerBranchCode: "a", ItemName: "x", ItemCode: "X", NetValueEGP: -8, NetQtyCases: -1, TransactionType: "مرتجع (Return)"},
	})

	filter := SellInReturnsFilter{Year: 2026}
	first := c.GetSellInReturnsCached(context.Background(), "tenant-adeco", filter)
	second := c.GetSellInReturnsCached(context.Background(), "tenant-adeco", filter)
	if first.KPIs.ReturnsValueEGP != 8 || second.KPIs.ReturnsValueEGP != 8 {
		t.Fatalf("first=%v second=%v", first.KPIs.ReturnsValueEGP, second.KPIs.ReturnsValueEGP)
	}
	if len(first.Alerts) != 0 || len(first.Advisories) != 0 {
		t.Fatalf("empty alerts/advisories required")
	}

	c.invalidateKPICache()
	third := c.GetSellInReturnsCached(context.Background(), "tenant-adeco", filter)
	if third.KPIs.ReturnsValueEGP != 8 {
		t.Fatalf("after invalidate: %v", third.KPIs.ReturnsValueEGP)
	}
}

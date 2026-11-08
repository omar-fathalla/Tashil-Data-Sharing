package bigquery

import (
	"math"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestAggregateSellInReturns_MonthlyNettingAndNegativesKept(t *testing.T) {
	recs := []domain.SellInRecord{
		{Year: 2026, MonthNum: 1, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", ItemCode: "P1", ItemGroup: "مجموعة1", NetValueEGP: 100, NetQtyCases: 10, TransactionType: "مسحوبات بيع (Sale)"},
		{Year: 2026, MonthNum: 1, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", ItemCode: "P1", ItemGroup: "مجموعة1", NetValueEGP: -20, NetQtyCases: -2, TransactionType: "مرتجع (Return)"},
		{Year: 2026, MonthNum: 2, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", ItemCode: "P1", ItemGroup: "مجموعة1", NetValueEGP: 50, NetQtyCases: 5, TransactionType: "مسحوبات بيع (Sale)"},
		{Year: 2026, MonthNum: 2, CustomerName: "فرع ب", CustomerBranchCode: "b-b", ItemName: "صنف2", ItemCode: "P2", ItemGroup: "مجموعة2", NetValueEGP: 40, NetQtyCases: 4, TransactionType: "مسحوبات بيع (Sale)"},
		{Year: 2026, MonthNum: 3, CustomerName: "فرع ب", CustomerBranchCode: "b-b", ItemName: "صنف2", ItemCode: "P2", ItemGroup: "مجموعة2", NetValueEGP: -10, NetQtyCases: -1, TransactionType: "مرتجع (Return)"},
		// Return in March for product with no March invoice → net-negative month (kept + advisory)
		{Year: 2026, MonthNum: 3, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", ItemCode: "P1", ItemGroup: "مجموعة1", NetValueEGP: -30, NetQtyCases: -3, TransactionType: "مرتجع (Return)"},
	}

	rep := AggregateSellInReturns(recs, SellInReturnsFilter{Year: 2026})
	if len(rep.Months) != 3 || rep.Months[0] != 1 || rep.Months[2] != 3 {
		t.Fatalf("dynamic months: got %v", rep.Months)
	}
	// Yearly returns = 20+10+30 = 60; gross = 100+50+40 = 190; net = 190-60 = 130
	if math.Abs(rep.KPIs.ReturnsValueEGP-60) > 0.01 {
		t.Fatalf("returns value: got %v want 60", rep.KPIs.ReturnsValueEGP)
	}
	if math.Abs(rep.KPIs.ReturnsQty-6) > 0.01 {
		t.Fatalf("returns qty: got %v want 6", rep.KPIs.ReturnsQty)
	}
	if math.Abs(rep.KPIs.GrossValueEGP-190) > 0.01 {
		t.Fatalf("gross: got %v want 190", rep.KPIs.GrossValueEGP)
	}
	if math.Abs(rep.KPIs.NetValueEGP-130) > 0.01 {
		t.Fatalf("net: got %v want 130", rep.KPIs.NetValueEGP)
	}
	wantPct := round2((60.0 / 190.0) * 100)
	if math.Abs(rep.KPIs.ReturnPctOfGross-wantPct) > 0.01 {
		t.Fatalf("return %%: got %v want %v", rep.KPIs.ReturnPctOfGross, wantPct)
	}

	// Monthly chart has gross/returns/net for each month; Jan net = 80
	var jan, mar *SellInReturnsMonthPoint
	for i := range rep.Monthly {
		if rep.Monthly[i].MonthNum == 1 {
			jan = &rep.Monthly[i]
		}
		if rep.Monthly[i].MonthNum == 3 {
			mar = &rep.Monthly[i]
		}
	}
	if jan == nil || math.Abs(jan.NetValueEGP-80) > 0.01 || math.Abs(jan.ReturnsValueEGP-20) > 0.01 {
		t.Fatalf("jan monthly: %+v", jan)
	}
	if mar == nil || math.Abs(mar.ReturnsValueEGP-40) > 0.01 || math.Abs(mar.GrossValueEGP) > 0.01 {
		t.Fatalf("mar monthly (returns only): %+v", mar)
	}

	// Branch A March cell is return-only (30) and net negative
	var branchA *SellInReturnsBranchRow
	for i := range rep.Branches {
		if rep.Branches[i].BranchKey == "b-a" {
			branchA = &rep.Branches[i]
			break
		}
	}
	if branchA == nil {
		t.Fatal("missing branch A")
	}
	m3 := branchA.ByMonth["3"]
	if math.Abs(m3.ReturnsValueEGP-30) > 0.01 || m3.NetValueEGP >= 0 {
		t.Fatalf("branch A Mar cell: %+v", m3)
	}

	// Monthly sums add to yearly
	var sumRet float64
	for _, p := range rep.Monthly {
		sumRet += p.ReturnsValueEGP
	}
	if math.Abs(sumRet-rep.KPIs.ReturnsValueEGP) > 0.01 {
		t.Fatalf("monthly returns sum %v != yearly %v", sumRet, rep.KPIs.ReturnsValueEGP)
	}

	if len(rep.Advisories) == 0 {
		t.Fatal("expected net-negative advisory for branch A / صنف1 / March")
	}
	found := false
	for _, a := range rep.Advisories {
		if a.MonthNum == 3 && a.BranchName == "فرع أ" && a.NetValueEGP < 0 {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("advisory missing: %+v", rep.Advisories)
	}

	if len(rep.FilterOptions.Branches) != 2 || len(rep.FilterOptions.ProductGroups) != 2 {
		t.Fatalf("filter options: %+v", rep.FilterOptions)
	}
}

func TestAggregateSellInReturns_MonthFilterAndMoM(t *testing.T) {
	recs := []domain.SellInRecord{
		{Year: 2026, MonthNum: 1, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", NetValueEGP: 100, NetQtyCases: 10},
		{Year: 2026, MonthNum: 1, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", NetValueEGP: -10, NetQtyCases: -1, TransactionType: "مرتجع (Return)"},
		{Year: 2026, MonthNum: 2, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", NetValueEGP: 80, NetQtyCases: 8},
		{Year: 2026, MonthNum: 2, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", NetValueEGP: -25, NetQtyCases: -2, TransactionType: "مرتجع (Return)"},
	}
	rep := AggregateSellInReturns(recs, SellInReturnsFilter{Year: 2026, Month: 2})
	if len(rep.Months) != 1 || rep.Months[0] != 2 {
		t.Fatalf("months: %v", rep.Months)
	}
	if math.Abs(rep.KPIs.ReturnsValueEGP-25) > 0.01 {
		t.Fatalf("Feb KPI returns: %v", rep.KPIs.ReturnsValueEGP)
	}
	if rep.KPIs.MomChangePct == nil {
		t.Fatal("expected MoM pct")
	}
	// (25-10)/10 * 100 = 150
	if math.Abs(*rep.KPIs.MomChangePct-150) > 0.01 || rep.KPIs.MomDirection != "up" {
		t.Fatalf("MoM: pct=%v dir=%s", *rep.KPIs.MomChangePct, rep.KPIs.MomDirection)
	}
	// Chart still has both months
	if len(rep.Monthly) != 2 {
		t.Fatalf("chart months: %d", len(rep.Monthly))
	}
}

func TestAggregateSellInReturns_ProductGroupFilter(t *testing.T) {
	recs := []domain.SellInRecord{
		{Year: 2026, MonthNum: 4, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف1", ItemGroup: "منظفات", NetValueEGP: -5, NetQtyCases: -1, TransactionType: "مرتجع (Return)"},
		{Year: 2026, MonthNum: 4, CustomerName: "فرع أ", CustomerBranchCode: "b-a", ItemName: "صنف2", ItemGroup: "عناية", NetValueEGP: -7, NetQtyCases: -1, TransactionType: "مرتجع (Return)"},
	}
	rep := AggregateSellInReturns(recs, SellInReturnsFilter{Year: 2026, ProductGroup: "منظفات"})
	if math.Abs(rep.KPIs.ReturnsValueEGP-5) > 0.01 {
		t.Fatalf("group filter returns: %v", rep.KPIs.ReturnsValueEGP)
	}
}

func TestIsSellInReturn(t *testing.T) {
	if !IsSellInReturn(domain.SellInRecord{NetValueEGP: -1}) {
		t.Fatal("negative value")
	}
	if !IsSellInReturn(domain.SellInRecord{TransactionType: "مرتجع (Return)", NetValueEGP: 0}) {
		t.Fatal("return type")
	}
	if IsSellInReturn(domain.SellInRecord{NetValueEGP: 10, NetQtyCases: 1}) {
		t.Fatal("invoice")
	}
}

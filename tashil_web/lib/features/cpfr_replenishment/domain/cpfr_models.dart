// Data models for CPFR (Collaborative Planning, Forecasting & Replenishment):
// - Sell-In vs. Sell-Out Reconciliation
// - Estimated On-Hand Inventory & Suggested Replenishment PO
// - W1 + W2 -> EXP Month-End Forecasting
// - Promotions (عادي vs عرض) & Returns (مرتجعات) Analytics
// - Field Sales Reps & Key Account Tracking (MT vs CC)

class ReconciliationMonthModel {
  final int year;
  final int monthNum;
  final String monthEn;
  final String monthAr;
  final String periodStatus;
  final bool hasActualSellOut;
  final int activeSkusCount;
  final double openingStockCases;
  final double openingStockValueEgp;
  final double sellInCases;
  final int sellInUnits;
  final double sellInValueEgp;
  final double sellInGrossInclVatEgp;
  final double sellInVatAmountEgp;
  final int sellOutUnits;
  final double sellOutEstCases;
  final double sellOutValueEgp;
  final double sellOutFactoryCostExclVatEgp;
  final double sellOutFactoryCostInclVatEgp;

  /// POS sales that have a real factory cost (basis of the chain margin).
  final double sellOutValueWithCostEgp;

  /// POS sales with no real factory cost — excluded from cost / margin.
  final double sellOutMissingCostValueEgp;
  final double chainGrossMarginEgp;
  final double chainGrossMarginPct;
  final double monthlyNetCases;
  final double monthlyNetValueEgp;
  final double closingStockCases;
  final double closingStockValueEgp;
  final double inventoryGapEgp;
  final double sellThroughRatePct;
  final int prevYearSellOutUnits;
  final double prevYearSellOutValueEgp;
  final double yoySellOutGrowthPct;
  final String stockHealthStatus;
  final String stockHealthLabelAr;
  final double weightTons;
  final double expectedCases;
  final double expectedValueEgp;

  const ReconciliationMonthModel({
    required this.year,
    required this.monthNum,
    required this.monthEn,
    required this.monthAr,
    required this.periodStatus,
    this.hasActualSellOut = false,
    required this.activeSkusCount,
    this.openingStockCases = 0.0,
    this.openingStockValueEgp = 0.0,
    required this.sellInCases,
    this.sellInUnits = 0,
    required this.sellInValueEgp,
    this.sellInGrossInclVatEgp = 0.0,
    this.sellInVatAmountEgp = 0.0,
    required this.sellOutUnits,
    this.sellOutEstCases = 0.0,
    required this.sellOutValueEgp,
    this.sellOutFactoryCostExclVatEgp = 0.0,
    this.sellOutFactoryCostInclVatEgp = 0.0,
    this.sellOutValueWithCostEgp = 0.0,
    this.sellOutMissingCostValueEgp = 0.0,
    this.chainGrossMarginEgp = 0.0,
    this.chainGrossMarginPct = 0.0,
    this.monthlyNetCases = 0.0,
    this.monthlyNetValueEgp = 0.0,
    this.closingStockCases = 0.0,
    this.closingStockValueEgp = 0.0,
    required this.inventoryGapEgp,
    required this.sellThroughRatePct,
    this.prevYearSellOutUnits = 0,
    this.prevYearSellOutValueEgp = 0.0,
    this.yoySellOutGrowthPct = 0.0,
    this.stockHealthStatus = 'optimal',
    this.stockHealthLabelAr = 'رصيد آمن ومتوازن',
    required this.weightTons,
    required this.expectedCases,
    required this.expectedValueEgp,
  });

  factory ReconciliationMonthModel.fromJson(Map<String, dynamic> json) {
    final sellInVal = (json['sell_in_value_egp'] as num?)?.toDouble() ?? 0.0;
    final sellOutVal = (json['sell_out_value_egp'] as num?)?.toDouble() ?? 0.0;
    final sellOutUnits = (json['sell_out_units'] as num?)?.toInt() ?? 0;
    final gapVal =
        (json['inventory_gap_egp'] as num?)?.toDouble() ?? (sellInVal - sellOutVal);
    return ReconciliationMonthModel(
      year: (json['year'] as num?)?.toInt() ?? 2026,
      monthNum: (json['month_num'] as num?)?.toInt() ?? 1,
      monthEn: json['month_en'] as String? ?? '',
      monthAr: json['month_ar'] as String? ?? '',
      periodStatus: json['period_status'] as String? ?? '',
      hasActualSellOut: json['has_actual_sell_out'] as bool? ??
          (sellOutVal > 0 || sellOutUnits > 0),
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      openingStockCases:
          (json['opening_stock_cases'] as num?)?.toDouble() ?? 0.0,
      openingStockValueEgp:
          (json['opening_stock_value_egp'] as num?)?.toDouble() ?? 0.0,
      sellInCases: (json['sell_in_cases'] as num?)?.toDouble() ?? 0.0,
      sellInUnits: (json['sell_in_units'] as num?)?.toInt() ?? 0,
      sellInValueEgp: sellInVal,
      sellInGrossInclVatEgp:
          (json['sell_in_gross_incl_vat_egp'] as num?)?.toDouble() ??
              double.parse((sellInVal * 1.14).toStringAsFixed(2)),
      sellInVatAmountEgp:
          (json['sell_in_vat_amount_egp'] as num?)?.toDouble() ??
              double.parse((sellInVal * 0.14).toStringAsFixed(2)),
      sellOutUnits: sellOutUnits,
      sellOutEstCases:
          (json['sell_out_est_cases'] as num?)?.toDouble() ?? 0.0,
      sellOutValueEgp: sellOutVal,
      sellOutFactoryCostExclVatEgp:
          (json['sell_out_factory_cost_excl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      sellOutFactoryCostInclVatEgp:
          (json['sell_out_factory_cost_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      sellOutValueWithCostEgp:
          (json['sell_out_value_with_cost_egp'] as num?)?.toDouble() ?? 0.0,
      sellOutMissingCostValueEgp:
          (json['sell_out_missing_cost_value_egp'] as num?)?.toDouble() ?? 0.0,
      chainGrossMarginEgp:
          (json['chain_gross_margin_egp'] as num?)?.toDouble() ?? 0.0,
      chainGrossMarginPct:
          (json['chain_gross_margin_pct'] as num?)?.toDouble() ?? 0.0,
      monthlyNetCases:
          (json['monthly_net_cases'] as num?)?.toDouble() ?? 0.0,
      monthlyNetValueEgp:
          (json['monthly_net_value_egp'] as num?)?.toDouble() ?? (sellInVal - sellOutVal),
      closingStockCases:
          (json['closing_stock_cases'] as num?)?.toDouble() ?? 0.0,
      closingStockValueEgp:
          (json['closing_stock_value_egp'] as num?)?.toDouble() ?? gapVal,
      inventoryGapEgp: gapVal,
      sellThroughRatePct:
          (json['sell_through_rate_pct'] as num?)?.toDouble() ?? 0.0,
      prevYearSellOutUnits:
          (json['prev_year_sell_out_units'] as num?)?.toInt() ?? 0,
      prevYearSellOutValueEgp:
          (json['prev_year_sell_out_value_egp'] as num?)?.toDouble() ?? 0.0,
      yoySellOutGrowthPct:
          (json['yoy_sell_out_growth_pct'] as num?)?.toDouble() ?? 0.0,
      stockHealthStatus: json['stock_health_status'] as String? ?? 'optimal',
      stockHealthLabelAr:
          json['stock_health_label_ar'] as String? ?? 'رصيد آمن ومتوازن',
      weightTons: (json['weight_tons'] as num?)?.toDouble() ?? 0.0,
      expectedCases: (json['expected_cases'] as num?)?.toDouble() ?? 0.0,
      expectedValueEgp:
          (json['expected_value_egp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SKUBranchInventoryModel {
  final String itemCode;
  final String barcode;
  final String itemType;
  final String departmentAr;
  final double factoryCartonCost;
  final double officialCartonExclVatEgp;
  final double officialCartonInclVatEgp;
  final double officialUnitInclVatEgp;
  final double avgRetailPosPriceEgp;
  final double retailerMarginPct;
  final String skuName;
  final String brand;
  final String sector;
  final String subCategory;
  final String regionCode;
  final String governorate;
  final String salesRep;
  final int unitsPerCarton;
  final double sellInCases;
  final int sellInUnits;
  final double sellInValueEgp;
  final double sellInGrossInclVatEgp;
  final double matchedSellInCases;
  final double matchedSellInValueEgp;
  final double pendingSellInCases;
  final double pendingSellInValueEgp;
  final int sellOutUnits;
  final double sellOutEstCases;
  final double sellOutValueEgp;
  final double sellOutFactoryCostEgp;
  final double chainGrossMarginEgp;

  /// True when the item has no real factory cost: cost and margin must show "—".
  final bool factoryCostMissing;
  final double returnCases;
  final double returnValueEgp;
  final double estimatedStockCases;
  final int estimatedStockUnits;
  final double estimatedStockValueEgp;
  final double matchedRemainingCases;
  final double matchedRemainingValueEgp;
  final double sellThroughPct;
  final double dailyRunRateCases;
  final double daysOfInventory;
  final String stockStatus;
  final String stockStatusAr;
  final double casePriceEgp;
  final double weightTons;
  final int suggestedPoCases;
  final double suggestedPoValueEgp;
  final double suggestedPoGrossInclVatEgp;
  final double suggestedPoTons;

  const SKUBranchInventoryModel({
    this.itemCode = '',
    this.barcode = '',
    this.itemType = 'عادي',
    this.departmentAr = '',
    this.factoryCartonCost = 0.0,
    this.officialCartonExclVatEgp = 0.0,
    this.officialCartonInclVatEgp = 0.0,
    this.officialUnitInclVatEgp = 0.0,
    this.avgRetailPosPriceEgp = 0.0,
    this.retailerMarginPct = 0.0,
    required this.skuName,
    required this.brand,
    required this.sector,
    required this.subCategory,
    required this.regionCode,
    required this.governorate,
    required this.salesRep,
    this.unitsPerCarton = 12,
    required this.sellInCases,
    this.sellInUnits = 0,
    required this.sellInValueEgp,
    this.sellInGrossInclVatEgp = 0.0,
    this.matchedSellInCases = 0.0,
    this.matchedSellInValueEgp = 0.0,
    this.pendingSellInCases = 0.0,
    this.pendingSellInValueEgp = 0.0,
    this.sellOutUnits = 0,
    required this.sellOutEstCases,
    required this.sellOutValueEgp,
    this.sellOutFactoryCostEgp = 0.0,
    this.chainGrossMarginEgp = 0.0,
    this.factoryCostMissing = false,
    required this.returnCases,
    required this.returnValueEgp,
    required this.estimatedStockCases,
    this.estimatedStockUnits = 0,
    required this.estimatedStockValueEgp,
    this.matchedRemainingCases = 0.0,
    this.matchedRemainingValueEgp = 0.0,
    this.sellThroughPct = 0.0,
    required this.dailyRunRateCases,
    required this.daysOfInventory,
    required this.stockStatus,
    required this.stockStatusAr,
    required this.casePriceEgp,
    required this.weightTons,
    required this.suggestedPoCases,
    required this.suggestedPoValueEgp,
    this.suggestedPoGrossInclVatEgp = 0.0,
    required this.suggestedPoTons,
  });

  factory SKUBranchInventoryModel.fromJson(Map<String, dynamic> json) {
    final upc = (json['units_per_carton'] as num?)?.toInt() ?? 12;
    final sellInC = (json['sell_in_cases'] as num?)?.toDouble() ?? 0.0;
    final sellInV = (json['sell_in_value_egp'] as num?)?.toDouble() ?? 0.0;
    final estStockC = (json['estimated_stock_cases'] as num?)?.toDouble() ?? 0.0;
    final estStockV = (json['estimated_stock_value_egp'] as num?)?.toDouble() ?? 0.0;
    final poValExcl = (json['suggested_po_value_egp'] as num?)?.toDouble() ?? 0.0;
    return SKUBranchInventoryModel(
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      itemType: json['item_type'] as String? ?? 'عادي',
      departmentAr: json['department_ar'] as String? ?? '',
      factoryCartonCost: (json['factory_carton_cost'] as num?)?.toDouble() ?? 0.0,
      officialCartonExclVatEgp:
          (json['official_carton_excl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      officialCartonInclVatEgp:
          (json['official_carton_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      officialUnitInclVatEgp:
          (json['official_unit_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      avgRetailPosPriceEgp:
          (json['avg_retail_pos_price_egp'] as num?)?.toDouble() ?? 0.0,
      retailerMarginPct:
          (json['retailer_margin_pct'] as num?)?.toDouble() ?? 0.0,
      skuName: json['sku_name'] as String? ?? '',
      brand: SmartBrandExtractor.inferBrand(
        json['sku_name'] as String? ?? '',
        existingBrand: json['brand'] as String?,
        subCategory: json['sub_category'] as String?,
      ),
      sector: json['sector'] as String? ?? 'MT',
      subCategory: json['sub_category'] as String? ?? '',
      regionCode: json['region_code'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      salesRep: json['sales_rep'] as String? ?? '',
      unitsPerCarton: upc,
      sellInCases: sellInC,
      sellInUnits: (json['sell_in_units'] as num?)?.toInt() ?? (sellInC * upc).round(),
      sellInValueEgp: sellInV,
      sellInGrossInclVatEgp:
          (json['sell_in_gross_incl_vat_egp'] as num?)?.toDouble() ??
              double.parse((sellInV * 1.14).toStringAsFixed(2)),
      matchedSellInCases:
          (json['matched_sell_in_cases'] as num?)?.toDouble() ?? sellInC,
      matchedSellInValueEgp:
          (json['matched_sell_in_value_egp'] as num?)?.toDouble() ?? sellInV,
      pendingSellInCases:
          (json['pending_sell_in_cases'] as num?)?.toDouble() ?? 0.0,
      pendingSellInValueEgp:
          (json['pending_sell_in_value_egp'] as num?)?.toDouble() ?? 0.0,
      sellOutUnits: (json['sell_out_units'] as num?)?.toInt() ?? 0,
      sellOutEstCases: (json['sell_out_est_cases'] as num?)?.toDouble() ?? 0.0,
      sellOutValueEgp: (json['sell_out_value_egp'] as num?)?.toDouble() ?? 0.0,
      sellOutFactoryCostEgp:
          (json['sell_out_factory_cost_egp'] as num?)?.toDouble() ?? 0.0,
      chainGrossMarginEgp:
          (json['chain_gross_margin_egp'] as num?)?.toDouble() ?? 0.0,
      factoryCostMissing: json['factory_cost_missing'] as bool? ?? false,
      returnCases: (json['return_cases'] as num?)?.toDouble() ?? 0.0,
      returnValueEgp: (json['return_value_egp'] as num?)?.toDouble() ?? 0.0,
      estimatedStockCases: estStockC,
      estimatedStockUnits: (json['estimated_stock_units'] as num?)?.toInt() ??
          (estStockC * upc).round(),
      estimatedStockValueEgp: estStockV,
      matchedRemainingCases:
          (json['matched_remaining_cases'] as num?)?.toDouble() ?? estStockC,
      matchedRemainingValueEgp:
          (json['matched_remaining_value_egp'] as num?)?.toDouble() ?? estStockV,
      sellThroughPct: (json['sell_through_pct'] as num?)?.toDouble() ?? 0.0,
      dailyRunRateCases:
          (json['daily_run_rate_cases'] as num?)?.toDouble() ?? 0.0,
      daysOfInventory: (json['days_of_inventory'] as num?)?.toDouble() ?? 0.0,
      stockStatus: json['stock_status'] as String? ?? 'optimal',
      stockStatusAr: json['stock_status_ar'] as String? ?? 'رصيد آمن',
      casePriceEgp: (json['case_price_egp'] as num?)?.toDouble() ?? 0.0,
      weightTons: (json['weight_tons'] as num?)?.toDouble() ?? 0.0,
      suggestedPoCases: (json['suggested_po_cases'] as num?)?.toInt() ?? 0,
      suggestedPoValueEgp: poValExcl,
      suggestedPoGrossInclVatEgp:
          (json['suggested_po_gross_incl_vat_egp'] as num?)?.toDouble() ??
              double.parse((poValExcl * 1.14).toStringAsFixed(2)),
      suggestedPoTons: (json['suggested_po_tons'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BrandForecastModel {
  final String sector;
  final String sectorNameAr;
  final String brand;
  final int activeSkusCount;
  final double actualCases;
  final double actualValueEgp;
  final double expectedCases;
  final double expectedValueEgp;
  final double forecastUpliftEgp;
  final double achievementRatePct;
  final double weightTons;
  final double shareOfTotalPct;

  const BrandForecastModel({
    required this.sector,
    required this.sectorNameAr,
    required this.brand,
    required this.activeSkusCount,
    required this.actualCases,
    required this.actualValueEgp,
    required this.expectedCases,
    required this.expectedValueEgp,
    required this.forecastUpliftEgp,
    required this.achievementRatePct,
    required this.weightTons,
    required this.shareOfTotalPct,
  });

  factory BrandForecastModel.fromJson(Map<String, dynamic> json) {
    return BrandForecastModel(
      sector: json['sector'] as String? ?? 'MT',
      sectorNameAr: json['sector_name_ar'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      actualCases: (json['actual_cases'] as num?)?.toDouble() ?? 0.0,
      actualValueEgp: (json['actual_value_egp'] as num?)?.toDouble() ?? 0.0,
      expectedCases: (json['expected_cases'] as num?)?.toDouble() ?? 0.0,
      expectedValueEgp:
          (json['expected_value_egp'] as num?)?.toDouble() ?? 0.0,
      forecastUpliftEgp:
          (json['forecast_uplift_egp'] as num?)?.toDouble() ?? 0.0,
      achievementRatePct:
          (json['achievement_rate_pct'] as num?)?.toDouble() ?? 0.0,
      weightTons: (json['weight_tons'] as num?)?.toDouble() ?? 0.0,
      shareOfTotalPct: (json['share_of_total_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RegionPerformanceModel {
  final String regionCode;
  final String governorate;
  final int recordsCount;
  final double actualCases;
  final double actualValueEgp;
  final double expectedCases;
  final double expectedValueEgp;
  final double weightTons;
  final double sharePct;

  const RegionPerformanceModel({
    required this.regionCode,
    required this.governorate,
    required this.recordsCount,
    required this.actualCases,
    required this.actualValueEgp,
    required this.expectedCases,
    required this.expectedValueEgp,
    required this.weightTons,
    required this.sharePct,
  });

  factory RegionPerformanceModel.fromJson(Map<String, dynamic> json) {
    return RegionPerformanceModel(
      regionCode: json['region_code'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      recordsCount: (json['records_count'] as num?)?.toInt() ?? 0,
      actualCases: (json['actual_cases'] as num?)?.toDouble() ?? 0.0,
      actualValueEgp: (json['actual_value_egp'] as num?)?.toDouble() ?? 0.0,
      expectedCases: (json['expected_cases'] as num?)?.toDouble() ?? 0.0,
      expectedValueEgp:
          (json['expected_value_egp'] as num?)?.toDouble() ?? 0.0,
      weightTons: (json['weight_tons'] as num?)?.toDouble() ?? 0.0,
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SalesRepScorecardModel {
  final String salesRep;
  final String kaOfficer;
  final String salesManager;
  final String regionCode;
  final String governorate;
  final int servedBranchesCount;
  final int activeSkusCount;
  final int recordsCount;
  final double actualCases;
  final double actualValueEgp;
  final double expectedCases;
  final double expectedValueEgp;
  final double achievementPct;
  final double weightTons;
  final double promoValueEgp;
  final double promoSharePct;
  final double returnCases;
  final double returnValueEgp;
  final double returnRatePct;
  final double mtValueEgp;
  final double ccValueEgp;

  const SalesRepScorecardModel({
    required this.salesRep,
    required this.kaOfficer,
    required this.salesManager,
    required this.regionCode,
    required this.governorate,
    required this.servedBranchesCount,
    required this.activeSkusCount,
    required this.recordsCount,
    required this.actualCases,
    required this.actualValueEgp,
    required this.expectedCases,
    required this.expectedValueEgp,
    required this.achievementPct,
    required this.weightTons,
    required this.promoValueEgp,
    required this.promoSharePct,
    required this.returnCases,
    required this.returnValueEgp,
    required this.returnRatePct,
    required this.mtValueEgp,
    required this.ccValueEgp,
  });

  factory SalesRepScorecardModel.fromJson(Map<String, dynamic> json) {
    return SalesRepScorecardModel(
      salesRep: json['sales_rep'] as String? ?? '',
      kaOfficer: json['ka_officer'] as String? ?? '',
      salesManager: json['sales_manager'] as String? ?? '',
      regionCode: json['region_code'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      servedBranchesCount:
          (json['served_branches_count'] as num?)?.toInt() ?? 1,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      recordsCount: (json['records_count'] as num?)?.toInt() ?? 0,
      actualCases: (json['actual_cases'] as num?)?.toDouble() ?? 0.0,
      actualValueEgp: (json['actual_value_egp'] as num?)?.toDouble() ?? 0.0,
      expectedCases: (json['expected_cases'] as num?)?.toDouble() ?? 0.0,
      expectedValueEgp:
          (json['expected_value_egp'] as num?)?.toDouble() ?? 0.0,
      achievementPct: (json['achievement_pct'] as num?)?.toDouble() ?? 0.0,
      weightTons: (json['weight_tons'] as num?)?.toDouble() ?? 0.0,
      promoValueEgp: (json['promo_value_egp'] as num?)?.toDouble() ?? 0.0,
      promoSharePct: (json['promo_share_pct'] as num?)?.toDouble() ?? 0.0,
      returnCases: (json['return_cases'] as num?)?.toDouble() ?? 0.0,
      returnValueEgp: (json['return_value_egp'] as num?)?.toDouble() ?? 0.0,
      returnRatePct: (json['return_rate_pct'] as num?)?.toDouble() ?? 0.0,
      mtValueEgp: (json['mt_value_egp'] as num?)?.toDouble() ?? 0.0,
      ccValueEgp: (json['cc_value_egp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ReturnItemSummaryModel {
  final String itemName;
  final String brand;
  final String sector;
  final String regionCode;
  final String governorate;
  final String salesRep;
  final double returnCases;
  final double returnValueEgp;
  final double returnRatePct;

  const ReturnItemSummaryModel({
    required this.itemName,
    required this.brand,
    required this.sector,
    required this.regionCode,
    required this.governorate,
    required this.salesRep,
    required this.returnCases,
    required this.returnValueEgp,
    required this.returnRatePct,
  });

  factory ReturnItemSummaryModel.fromJson(Map<String, dynamic> json) {
    return ReturnItemSummaryModel(
      itemName: json['item_name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      sector: json['sector'] as String? ?? 'MT',
      regionCode: json['region_code'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      salesRep: json['sales_rep'] as String? ?? '',
      returnCases: (json['return_cases'] as num?)?.toDouble() ?? 0.0,
      returnValueEgp: (json['return_value_egp'] as num?)?.toDouble() ?? 0.0,
      returnRatePct: (json['return_rate_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PromoAndReturnSummaryModel {
  final int regularRecordsCount;
  final double regularCases;
  final double regularValueEgp;
  final double regularTons;
  final int promoRecordsCount;
  final double promoCases;
  final double promoValueEgp;
  final double promoTons;
  final double promoValueSharePct;
  final double promoVolumeSharePct;
  final double avgPromoCaseTons;
  final int returnRecordsCount;
  final double totalReturnCases;
  final double totalReturnValueEgp;
  final double overallReturnPct;
  final List<ReturnItemSummaryModel> topReturnItems;

  const PromoAndReturnSummaryModel({
    required this.regularRecordsCount,
    required this.regularCases,
    required this.regularValueEgp,
    required this.regularTons,
    required this.promoRecordsCount,
    required this.promoCases,
    required this.promoValueEgp,
    required this.promoTons,
    required this.promoValueSharePct,
    required this.promoVolumeSharePct,
    required this.avgPromoCaseTons,
    required this.returnRecordsCount,
    required this.totalReturnCases,
    required this.totalReturnValueEgp,
    required this.overallReturnPct,
    required this.topReturnItems,
  });

  factory PromoAndReturnSummaryModel.fromJson(Map<String, dynamic> json) {
    final rawReturns = json['top_return_items'] as List<dynamic>? ?? [];
    return PromoAndReturnSummaryModel(
      regularRecordsCount:
          (json['regular_records_count'] as num?)?.toInt() ?? 0,
      regularCases: (json['regular_cases'] as num?)?.toDouble() ?? 0.0,
      regularValueEgp: (json['regular_value_egp'] as num?)?.toDouble() ?? 0.0,
      regularTons: (json['regular_tons'] as num?)?.toDouble() ?? 0.0,
      promoRecordsCount: (json['promo_records_count'] as num?)?.toInt() ?? 0,
      promoCases: (json['promo_cases'] as num?)?.toDouble() ?? 0.0,
      promoValueEgp: (json['promo_value_egp'] as num?)?.toDouble() ?? 0.0,
      promoTons: (json['promo_tons'] as num?)?.toDouble() ?? 0.0,
      promoValueSharePct:
          (json['promo_value_share_pct'] as num?)?.toDouble() ?? 0.0,
      promoVolumeSharePct:
          (json['promo_volume_share_pct'] as num?)?.toDouble() ?? 0.0,
      avgPromoCaseTons:
          (json['avg_promo_case_tons'] as num?)?.toDouble() ?? 0.0,
      returnRecordsCount: (json['return_records_count'] as num?)?.toInt() ?? 0,
      totalReturnCases: (json['total_return_cases'] as num?)?.toDouble() ?? 0.0,
      totalReturnValueEgp:
          (json['total_return_value_egp'] as num?)?.toDouble() ?? 0.0,
      overallReturnPct: (json['overall_return_pct'] as num?)?.toDouble() ?? 0.0,
      topReturnItems: rawReturns
          .whereType<Map<String, dynamic>>()
          .map(ReturnItemSummaryModel.fromJson)
          .toList(),
    );
  }
}

class CPFRDashboardModel {
  final String tenantId;
  final String retailerChain;
  final String sourceFilename;
  final int totalRecords;
  final int activeSkusCount;
  final int activeRepsCount;
  final String salesManagerName;
  final String kaOfficerName;
  final double jan2026SellInEgp;
  final double jan2026SellOutEgp;
  final double jan2026GapEgp;
  final double jan2026SellThroughPct;
  final double ytd2026SellInEgp;
  final double ytd2026SellInCases;
  final double ytd2026WeightTons;
  final double ytd2026ExpectedEgp;
  final double ytd2026GrossInclVatEgp;
  final double ytd2026VatAmountEgp;
  final int ytd2026TotalUnits;
  final double octW1W2ActualEgp;
  final double octW1W2ActualCases;
  final double octProjectedMonthEndEgp;
  final double octProjectedCases;
  final double mtRevenueEgp;
  final double mtSharePct;
  final double ccRevenueEgp;
  final double ccSharePct;
  final double totalEstimatedStockCases;
  final double totalEstimatedStockEgp;
  final int totalSuggestedPoCases;
  final double totalSuggestedPoEgp;
  final double totalSuggestedPoTons;
  final int urgentReplenishmentCount;
  final int overstockAlertCount;
  final int leadTimeDays;
  final int safetyStockDays;
  final int matchedMonthsCount;
  final String matchedPeriodLabel;
  final double matchedSellInCases;
  final double matchedSellInValueExclVatEgp;
  final double matchedSellInGrossInclVatEgp;
  final int matchedSellOutUnits;
  final double matchedSellOutCases;
  final double matchedSellOutPosValueEgp;
  final double matchedSellOutFactoryCostEgp;

  /// Matched factory cost without VAT (the basis of the chain margin).
  final double matchedSellOutFactoryCostExclVatEgp;
  final double matchedRemainingCases;
  final double matchedRemainingFactoryValueEgp;
  final double matchedSellThroughPct;
  final double matchedChainGrossMarginEgp;
  final double matchedChainGrossMarginPct;
  final double matchedSellOutValueWithCostEgp;
  final double matchedMissingCostSellOutEgp;
  final int matchedMissingCostSellOutUnits;
  final List<MissingCostItemModel> missingCostItems;
  final double matchedYoyUnitsGrowthPct;
  final double matchedYoyValueGrowthPct;

  /// False when no matched month has last-year Sell-Out (backend
  /// `matched_yoy_available`); the YoY card then shows "—", not +0.0%.
  final bool matchedYoyAvailable;
  final int pendingSellOutMonthsCount;
  final String pendingSellOutPeriodLabel;
  final double pendingSellOutCases;
  final double pendingSellOutValueEgp;
  final List<ReconciliationMonthModel> monthlyReconciliation;
  final List<SKUBranchInventoryModel> inventoryAndPoItems;
  final List<BrandForecastModel> brandForecasts;
  final List<RegionPerformanceModel> regionPerformances;
  final List<SalesRepScorecardModel> salesRepScorecards;
  final PromoAndReturnSummaryModel promoAndReturns;

  const CPFRDashboardModel({
    required this.tenantId,
    required this.retailerChain,
    required this.sourceFilename,
    required this.totalRecords,
    required this.activeSkusCount,
    required this.activeRepsCount,
    required this.salesManagerName,
    required this.kaOfficerName,
    required this.jan2026SellInEgp,
    required this.jan2026SellOutEgp,
    required this.jan2026GapEgp,
    required this.jan2026SellThroughPct,
    required this.ytd2026SellInEgp,
    required this.ytd2026SellInCases,
    required this.ytd2026WeightTons,
    required this.ytd2026ExpectedEgp,
    this.ytd2026GrossInclVatEgp = 0.0,
    this.ytd2026VatAmountEgp = 0.0,
    this.ytd2026TotalUnits = 0,
    required this.octW1W2ActualEgp,
    required this.octW1W2ActualCases,
    required this.octProjectedMonthEndEgp,
    required this.octProjectedCases,
    required this.mtRevenueEgp,
    required this.mtSharePct,
    required this.ccRevenueEgp,
    required this.ccSharePct,
    required this.totalEstimatedStockCases,
    required this.totalEstimatedStockEgp,
    required this.totalSuggestedPoCases,
    required this.totalSuggestedPoEgp,
    required this.totalSuggestedPoTons,
    required this.urgentReplenishmentCount,
    required this.overstockAlertCount,
    required this.leadTimeDays,
    required this.safetyStockDays,
    this.matchedMonthsCount = 0,
    this.matchedPeriodLabel = '',
    this.matchedSellInCases = 0.0,
    this.matchedSellInValueExclVatEgp = 0.0,
    this.matchedSellInGrossInclVatEgp = 0.0,
    this.matchedSellOutUnits = 0,
    this.matchedSellOutCases = 0.0,
    this.matchedSellOutPosValueEgp = 0.0,
    this.matchedSellOutFactoryCostEgp = 0.0,
    this.matchedSellOutFactoryCostExclVatEgp = 0.0,
    this.matchedRemainingCases = 0.0,
    this.matchedRemainingFactoryValueEgp = 0.0,
    this.matchedSellThroughPct = 0.0,
    this.matchedChainGrossMarginEgp = 0.0,
    this.matchedChainGrossMarginPct = 0.0,
    this.matchedSellOutValueWithCostEgp = 0.0,
    this.matchedMissingCostSellOutEgp = 0.0,
    this.matchedMissingCostSellOutUnits = 0,
    this.missingCostItems = const [],
    this.matchedYoyUnitsGrowthPct = 0.0,
    this.matchedYoyValueGrowthPct = 0.0,
    this.matchedYoyAvailable = true,
    this.pendingSellOutMonthsCount = 0,
    this.pendingSellOutPeriodLabel = '',
    this.pendingSellOutCases = 0.0,
    this.pendingSellOutValueEgp = 0.0,
    required this.monthlyReconciliation,
    required this.inventoryAndPoItems,
    required this.brandForecasts,
    required this.regionPerformances,
    required this.salesRepScorecards,
    required this.promoAndReturns,
  });

  factory CPFRDashboardModel.fromJson(Map<String, dynamic> json) {
    final monthsRaw = json['monthly_reconciliation'] as List<dynamic>? ?? [];
    final invRaw = json['inventory_and_po_items'] as List<dynamic>? ?? [];
    final brandsRaw = json['brand_forecasts'] as List<dynamic>? ?? [];
    final regionsRaw = json['region_performances'] as List<dynamic>? ?? [];
    final repsRaw = json['sales_rep_scorecards'] as List<dynamic>? ?? [];
    final promoRaw =
        json['promo_and_returns'] as Map<String, dynamic>? ?? const {};
    final ytdSellIn = (json['ytd_2026_sell_in_egp'] as num?)?.toDouble() ?? 0.0;
    final ytdCases = (json['ytd_2026_sell_in_cases'] as num?)?.toDouble() ?? 0.0;

    return CPFRDashboardModel(
      tenantId: json['tenant_id'] as String? ?? 'tenant-default',
      retailerChain: json['retailer_chain'] as String? ?? 'all',
      sourceFilename: json['source_filename'] as String? ??
          'CPFR_Sell_In_Reconciliation.xlsx',
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      activeSkusCount: (json['active_skus_count'] as num?)?.toInt() ?? 0,
      activeRepsCount: (json['active_reps_count'] as num?)?.toInt() ?? 0,
      salesManagerName:
          json['sales_manager_name'] as String? ?? 'إدارة مبيعات السلاسل التجارية',
      kaOfficerName: json['ka_officer_name'] as String? ??
          'إدارة كبار العملاء (Key Accounts)',
      jan2026SellInEgp:
          (json['jan_2026_sell_in_egp'] as num?)?.toDouble() ?? 10212067.76,
      jan2026SellOutEgp:
          (json['jan_2026_sell_out_egp'] as num?)?.toDouble() ?? 9537094.70,
      jan2026GapEgp:
          (json['jan_2026_gap_egp'] as num?)?.toDouble() ?? 674973.06,
      jan2026SellThroughPct:
          (json['jan_2026_sell_through_pct'] as num?)?.toDouble() ?? 93.39,
      ytd2026SellInEgp: ytdSellIn,
      ytd2026SellInCases: ytdCases,
      ytd2026WeightTons:
          (json['ytd_2026_weight_tons'] as num?)?.toDouble() ?? 0.0,
      ytd2026ExpectedEgp:
          (json['ytd_2026_expected_egp'] as num?)?.toDouble() ?? 0.0,
      ytd2026GrossInclVatEgp:
          (json['ytd_2026_gross_incl_vat_egp'] as num?)?.toDouble() ??
              double.parse((ytdSellIn * 1.14).toStringAsFixed(2)),
      ytd2026VatAmountEgp:
          (json['ytd_2026_vat_amount_egp'] as num?)?.toDouble() ??
              double.parse((ytdSellIn * 0.14).toStringAsFixed(2)),
      ytd2026TotalUnits:
          (json['ytd_2026_total_units'] as num?)?.toInt() ??
              (ytdCases * 12).round(),
      octW1W2ActualEgp:
          (json['oct_w1w2_actual_egp'] as num?)?.toDouble() ?? 0.0,
      octW1W2ActualCases:
          (json['oct_w1w2_actual_cases'] as num?)?.toDouble() ?? 0.0,
      octProjectedMonthEndEgp:
          (json['oct_projected_month_end_egp'] as num?)?.toDouble() ?? 0.0,
      octProjectedCases:
          (json['oct_projected_cases'] as num?)?.toDouble() ?? 0.0,
      mtRevenueEgp: (json['mt_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      mtSharePct: (json['mt_share_pct'] as num?)?.toDouble() ?? 0.0,
      ccRevenueEgp: (json['cc_revenue_egp'] as num?)?.toDouble() ?? 0.0,
      ccSharePct: (json['cc_share_pct'] as num?)?.toDouble() ?? 0.0,
      totalEstimatedStockCases:
          (json['total_estimated_stock_cases'] as num?)?.toDouble() ?? 0.0,
      totalEstimatedStockEgp:
          (json['total_estimated_stock_egp'] as num?)?.toDouble() ?? 0.0,
      totalSuggestedPoCases:
          (json['total_suggested_po_cases'] as num?)?.toInt() ?? 0,
      totalSuggestedPoEgp:
          (json['total_suggested_po_egp'] as num?)?.toDouble() ?? 0.0,
      totalSuggestedPoTons:
          (json['total_suggested_po_tons'] as num?)?.toDouble() ?? 0.0,
      urgentReplenishmentCount:
          (json['urgent_replenishment_count'] as num?)?.toInt() ?? 0,
      overstockAlertCount:
          (json['overstock_alert_count'] as num?)?.toInt() ?? 0,
      leadTimeDays: (json['lead_time_days'] as num?)?.toInt() ?? 4,
      safetyStockDays: (json['safety_stock_days'] as num?)?.toInt() ?? 7,
      matchedMonthsCount:
          (json['matched_months_count'] as num?)?.toInt() ?? 0,
      matchedPeriodLabel:
          json['matched_period_label'] as String? ?? '',
      matchedSellInCases:
          (json['matched_sell_in_cases'] as num?)?.toDouble() ?? 0.0,
      matchedSellInValueExclVatEgp:
          (json['matched_sell_in_value_excl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      matchedSellInGrossInclVatEgp:
          (json['matched_sell_in_gross_incl_vat_egp'] as num?)?.toDouble() ?? 0.0,
      matchedSellOutUnits:
          (json['matched_sell_out_units'] as num?)?.toInt() ?? 0,
      matchedSellOutCases:
          (json['matched_sell_out_cases'] as num?)?.toDouble() ?? 0.0,
      matchedSellOutPosValueEgp:
          (json['matched_sell_out_pos_value_egp'] as num?)?.toDouble() ?? 0.0,
      matchedSellOutFactoryCostEgp:
          (json['matched_sell_out_factory_cost_egp'] as num?)?.toDouble() ?? 0.0,
      matchedSellOutFactoryCostExclVatEgp:
          (json['matched_sell_out_factory_cost_excl_vat_egp'] as num?)?.toDouble() ??
              (json['matched_sell_out_factory_cost_egp'] as num?)?.toDouble() ??
              0.0,
      matchedRemainingCases:
          (json['matched_remaining_cases'] as num?)?.toDouble() ?? 0.0,
      matchedRemainingFactoryValueEgp:
          (json['matched_remaining_factory_value_egp'] as num?)?.toDouble() ?? 0.0,
      matchedSellThroughPct:
          (json['matched_sell_through_pct'] as num?)?.toDouble() ?? 0.0,
      matchedChainGrossMarginEgp:
          (json['matched_chain_gross_margin_egp'] as num?)?.toDouble() ?? 0.0,
      matchedChainGrossMarginPct:
          (json['matched_chain_gross_margin_pct'] as num?)?.toDouble() ?? 0.0,
      matchedSellOutValueWithCostEgp:
          (json['matched_sell_out_value_with_cost_egp'] as num?)?.toDouble() ?? 0.0,
      matchedMissingCostSellOutEgp:
          (json['matched_missing_cost_sell_out_egp'] as num?)?.toDouble() ?? 0.0,
      matchedMissingCostSellOutUnits:
          (json['matched_missing_cost_sell_out_units'] as num?)?.toInt() ?? 0,
      missingCostItems: (json['missing_cost_items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MissingCostItemModel.fromJson)
          .toList(),
      matchedYoyUnitsGrowthPct:
          (json['matched_yoy_units_growth_pct'] as num?)?.toDouble() ?? 0.0,
      matchedYoyValueGrowthPct:
          (json['matched_yoy_value_growth_pct'] as num?)?.toDouble() ?? 0.0,
      // Older payloads without the flag: treat a non-zero % as available.
      matchedYoyAvailable: json['matched_yoy_available'] as bool? ??
          (((json['matched_yoy_value_growth_pct'] as num?) ?? 0) != 0 ||
              ((json['matched_yoy_units_growth_pct'] as num?) ?? 0) != 0),
      pendingSellOutMonthsCount:
          (json['pending_sell_out_months_count'] as num?)?.toInt() ?? 0,
      pendingSellOutPeriodLabel:
          json['pending_sell_out_period_label'] as String? ?? '',
      pendingSellOutCases:
          (json['pending_sell_out_cases'] as num?)?.toDouble() ?? 0.0,
      pendingSellOutValueEgp:
          (json['pending_sell_out_value_egp'] as num?)?.toDouble() ?? 0.0,
      monthlyReconciliation: monthsRaw
          .whereType<Map<String, dynamic>>()
          .map(ReconciliationMonthModel.fromJson)
          .toList(),
      inventoryAndPoItems: invRaw
          .whereType<Map<String, dynamic>>()
          .map(SKUBranchInventoryModel.fromJson)
          .toList(),
      brandForecasts: brandsRaw
          .whereType<Map<String, dynamic>>()
          .map(BrandForecastModel.fromJson)
          .toList(),
      regionPerformances: regionsRaw
          .whereType<Map<String, dynamic>>()
          .map(RegionPerformanceModel.fromJson)
          .toList(),
      salesRepScorecards: repsRaw
          .whereType<Map<String, dynamic>>()
          .map(SalesRepScorecardModel.fromJson)
          .toList(),
      promoAndReturns: PromoAndReturnSummaryModel.fromJson(promoRaw),
    );
  }
}

/// A Sell-Out item with no real factory cost (not in the Sell-Out sheet and not
/// priced in the product master). Its cost/margin are left empty, never guessed.
class MissingCostItemModel {
  final String itemCode;
  final String barcode;
  final String skuName;
  final List<String> chains;
  final int unitsSold;
  final double salesValueEgp;
  final String reason;
  final String reasonAr;
  final String masterItemCode;
  final String masterName;

  const MissingCostItemModel({
    this.itemCode = '',
    this.barcode = '',
    this.skuName = '',
    this.chains = const [],
    this.unitsSold = 0,
    this.salesValueEgp = 0.0,
    this.reason = '',
    this.reasonAr = '',
    this.masterItemCode = '',
    this.masterName = '',
  });

  factory MissingCostItemModel.fromJson(Map<String, dynamic> json) {
    return MissingCostItemModel(
      itemCode: json['item_code'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      skuName: json['sku_name'] as String? ?? '',
      chains: (json['chains'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      unitsSold: (json['units_sold'] as num?)?.toInt() ?? 0,
      salesValueEgp: (json['sales_value_egp'] as num?)?.toDouble() ?? 0.0,
      reason: json['reason'] as String? ?? '',
      reasonAr: json['reason_ar'] as String? ?? '',
      masterItemCode: json['master_item_code'] as String? ?? '',
      masterName: json['master_name'] as String? ?? '',
    );
  }
}

/// SmartBrandExtractor provides AI-grade brand extraction for FMCG & retail items.
/// Recognizes popular Egyptian & international FMCG brands, and provides intelligent
/// token inference for any new company or novel catalog uploaded to the system.
class SmartBrandExtractor {
  static const Map<String, String> _knownBrands = {
    'ماكسيل': 'ماكسيل (Maxell)',
    'maxel': 'ماكسيل (Maxell)',
    'ديفا': 'ديفا (Diva)',
    'diva': 'ديفا (Diva)',
    'فلڤيتا': 'فلڤيتا (Velveta)',
    'فلفيتا': 'فلڤيتا (Velveta)',
    'velveta': 'فلڤيتا (Velveta)',
    'فيبا': 'فيبا (Feba)',
    'feba': 'فيبا (Feba)',
    'فيفا': 'فيفا (Viva)',
    'viva': 'فيفا (Viva)',
    'نيفيا': 'نيفيا (Nivea)',
    'nivea': 'نيفيا (Nivea)',
    'دوف': 'دوف (Dove)',
    'dove': 'دوف (Dove)',
    'رابيدو': 'رابيدو (Rapido)',
    'rapido': 'رابيدو (Rapido)',
    'جلاسي': 'رابيدو (Rapido)',
    'جلاسى': 'رابيدو (Rapido)',
    'سبيد': 'رابيدو (Rapido)',
    'فما': 'فيما (Fema)',
    'فيما': 'فيما (Fema)',
    'fema': 'فيما (Fema)',
    'ديفاتول': 'ديفاتول (Divatol)',
    'كلوريل': 'كلوريل (Clorel)',
    'clorel': 'كلوريل (Clorel)',
    'جنرال': 'جنرال (General)',
    'general': 'جنرال (General)',
    'أريال': 'أريال (Ariel)',
    'اريال': 'أريال (Ariel)',
    'ariel': 'أريال (Ariel)',
    'برسيل': 'برسيل (Persil)',
    'persil': 'برسيل (Persil)',
    'كلوركس': 'كلوركس (Clorox)',
    'clorox': 'كلوركس (Clorox)',
    'ديتول': 'ديتول (Dettol)',
    'dettol': 'ديتول (Dettol)',
    'فاين': 'فاين (Fine)',
    'fine': 'فاين (Fine)',
    'زينة': 'زينة (Zeina)',
    'zeina': 'زينة (Zeina)',
    'بامبرز': 'بامبرز (Pampers)',
    'pampers': 'بامبرز (Pampers)',
    'مولفيكس': 'مولفيكس (Molfix)',
    'molfix': 'مولفيكس (Molfix)',
    'جهينة': 'جهينة (Juhayna)',
    'juhayna': 'جهينة (Juhayna)',
    'المراعي': 'المراعي (Almarai)',
    'almarai': 'المراعي (Almarai)',
    'ليبتون': 'ليبتون (Lipton)',
    'lipton': 'ليبتون (Lipton)',
    'نسكافيه': 'نسكافيه (Nescafe)',
    'nescafe': 'نسكافيه (Nescafe)',
    'بيبسي': 'بيبسي (Pepsi)',
    'pepsi': 'بيبسي (Pepsi)',
    'كوكاكولا': 'كوكاكولا (Coca-Cola)',
    'coca': 'كوكاكولا (Coca-Cola)',
  };

  /// Dynamically infers and extracts the Brand name from SKU name, category, itemCode, or existing brand.
  static String inferBrand(
    String skuName, {
    String? existingBrand,
    String? subCategory,
    String? itemCode,
  }) {
    final eb = existingBrand?.trim() ?? '';
    if (eb.isNotEmpty &&
        eb != 'عام' &&
        eb.toLowerCase() != 'other' &&
        eb.toLowerCase() != 'general' &&
        eb != 'منتجات الشركة' &&
        !eb.contains('أصناف عامة')) {
      return eb;
    }

    final text = '${skuName.trim()} ${subCategory ?? ''}'.toLowerCase();
    for (final entry in _knownBrands.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }

    final codeUpper = (itemCode ?? '').trim().toUpperCase();
    if (codeUpper.startsWith('FGCL')) return 'كلوريل (Clorel)';
    if (codeUpper.startsWith('FGDW')) return 'فيبا (Feba)';
    if (codeUpper.startsWith('FGDG')) return 'ديفاتول (Divatol)';
    if (codeUpper.startsWith('FGHC')) return 'فلفيتا (Velveta)';

    // Dynamic AI token inference for any novel company
    final cleaned = skuName
        .replaceAll(RegExp(r'^[*0-9\-_./\s]+'), '')
        .replaceFirst(RegExp(r'^(عرض\s+\d*\s*)'), '')
        .trim();
    if (cleaned.isEmpty) {
      if (subCategory != null && subCategory.trim().isNotEmpty) {
        return subCategory.trim();
      }
      return 'أصناف عامة';
    }

    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isNotEmpty) {
      final first = tokens[0];
      if (tokens.length > 1) {
        final second = tokens[1].toLowerCase();
        if (['ماجيك', 'جولد', 'بلس', 'magic', 'gold', 'plus', 'كلاسيك', 'classic'].contains(second)) {
          return '$first ${tokens[1]}';
        }
      }
      if (first.length >= 2) {
        return first;
      }
    }

    return 'أصناف عامة';
  }
}


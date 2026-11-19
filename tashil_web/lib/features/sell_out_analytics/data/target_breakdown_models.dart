import '../../../core/network/api_client.dart' show TargetMonthBreakdownModel;

/// Response of `GET /api/v1/sellout/targets/{id}/breakdown`: how one Sell-Out
/// target is spread over branches and SKUs (proportional to a historical
/// baseline) next to the actuals of the target period.
class TargetBreakdownModel {
  final String targetId;
  final String retailerChain;
  final String chainDisplayName;
  final int year;
  final int month;
  final String monthLabel;
  final String branchScope;
  final String categoryScope;
  final double targetRevenueEgp;
  final double targetUnits;
  final TargetBreakdownBaseline baseline;

  /// False when the target period has no sales in scope (a future year):
  /// achieved / achievement / gap render as «—», never 0.
  final bool hasActuals;
  final double actualRevenueEgp;
  final int actualUnits;
  final double? achievementPct;
  final double gapEgp;
  final int? allocatedUnitsTotal;
  final double? allocatedCartonsTotal;
  final double unattributedActualEgp;
  final double noHistoryActualEgp;
  final double allocationGranularityEgp;
  final List<TargetBreakdownBranchModel> branches;
  final List<TargetBreakdownNoHistoryModel> noHistory;
  final String source;

  /// Seasonal 12-month series for the (possibly branch-filtered) annual target.
  final List<TargetMonthBreakdownModel> monthlyPhasing;
  final String appliedBranch;
  final int appliedMonth;

  const TargetBreakdownModel({
    required this.targetId,
    required this.retailerChain,
    required this.chainDisplayName,
    required this.year,
    required this.month,
    required this.monthLabel,
    required this.branchScope,
    required this.categoryScope,
    required this.targetRevenueEgp,
    required this.targetUnits,
    required this.baseline,
    required this.hasActuals,
    required this.actualRevenueEgp,
    required this.actualUnits,
    required this.achievementPct,
    required this.gapEgp,
    this.allocatedUnitsTotal,
    this.allocatedCartonsTotal,
    this.unattributedActualEgp = 0,
    this.noHistoryActualEgp = 0,
    this.allocationGranularityEgp = 1,
    this.branches = const [],
    this.noHistory = const [],
    this.source = '',
    this.monthlyPhasing = const [],
    this.appliedBranch = '',
    this.appliedMonth = 0,
  });

  /// Sum of the branch allocations; equals [targetRevenueEgp] when a
  /// baseline exists (largest-remainder rounding on the server).
  double get allocatedTotalEgp =>
      branches.fold<double>(0, (s, b) => s + b.allocatedTargetEgp);

  bool get hasBranches => branches.isNotEmpty;

  /// Money in whole pounds unless the target itself has piastres.
  bool get showDecimals => allocationGranularityEgp < 1;

  factory TargetBreakdownModel.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        (json[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(f)
            .toList();
    return TargetBreakdownModel(
      targetId: json['target_id'] as String? ?? '',
      retailerChain: json['retailer_chain'] as String? ?? '',
      chainDisplayName: json['chain_display_name'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      monthLabel: json['month_label'] as String? ?? '',
      branchScope: json['branch_scope'] as String? ?? '',
      categoryScope: json['category_scope'] as String? ?? '',
      targetRevenueEgp: _d(json['target_revenue_egp']),
      targetUnits: _d(json['target_units']),
      baseline: TargetBreakdownBaseline.fromJson(
        json['baseline'] as Map<String, dynamic>? ?? const {},
      ),
      hasActuals: json['has_actuals'] as bool? ?? false,
      actualRevenueEgp: _d(json['actual_revenue_egp']),
      actualUnits: (json['actual_units'] as num?)?.toInt() ?? 0,
      achievementPct: _dn(json['achievement_pct']),
      gapEgp: _d(json['gap_egp']),
      allocatedUnitsTotal: (json['allocated_target_units'] as num?)?.toInt(),
      allocatedCartonsTotal: _dn(json['allocated_target_cartons']),
      unattributedActualEgp: _d(json['unattributed_actual_revenue_egp']),
      noHistoryActualEgp: _d(json['no_history_actual_revenue_egp']),
      allocationGranularityEgp:
          _dn(json['allocation_granularity_egp']) ?? 1,
      branches: list('branches', TargetBreakdownBranchModel.fromJson),
      noHistory: list('no_history', TargetBreakdownNoHistoryModel.fromJson),
      source: json['source'] as String? ?? '',
      monthlyPhasing: list('monthly_phasing', TargetMonthBreakdownModel.fromJson),
      appliedBranch: json['applied_branch'] as String? ?? '',
      appliedMonth: (json['applied_month'] as num?)?.toInt() ?? 0,
    );
  }
}

class TargetBreakdownBaseline {
  /// `prior_year_month`, `prior_year`, `trailing_12m` or `none`.
  final String kind;
  final int year;
  final String startDate;
  final String endDate;
  final int monthsCovered;
  final bool partial;
  final bool fallbackUsed;
  final double totalRevenueEgp;

  /// Arabic caption explaining the allocation method and baseline period.
  final String captionAr;

  const TargetBreakdownBaseline({
    this.kind = 'none',
    this.year = 0,
    this.startDate = '',
    this.endDate = '',
    this.monthsCovered = 0,
    this.partial = false,
    this.fallbackUsed = false,
    this.totalRevenueEgp = 0,
    this.captionAr = '',
  });

  bool get isNone => kind == 'none';

  factory TargetBreakdownBaseline.fromJson(Map<String, dynamic> json) =>
      TargetBreakdownBaseline(
        kind: json['kind'] as String? ?? 'none',
        year: (json['year'] as num?)?.toInt() ?? 0,
        startDate: json['start_date'] as String? ?? '',
        endDate: json['end_date'] as String? ?? '',
        monthsCovered: (json['months_covered'] as num?)?.toInt() ?? 0,
        partial: json['partial'] as bool? ?? false,
        fallbackUsed: json['fallback_used'] as bool? ?? false,
        totalRevenueEgp: _d(json['total_revenue_egp']),
        captionAr: json['caption_ar'] as String? ?? '',
      );
}

class TargetBreakdownBranchModel {
  final String branchKey;
  final String branchName;
  final double baselineRevenueEgp;
  final double sharePct;
  final double allocatedTargetEgp;
  final int? allocatedUnits;
  final double? allocatedCartons;
  final double actualRevenueEgp;
  final int actualUnits;
  final double? achievementPct;
  final double gapEgp;
  final List<TargetBreakdownSkuModel> skus;

  const TargetBreakdownBranchModel({
    required this.branchKey,
    required this.branchName,
    required this.baselineRevenueEgp,
    required this.sharePct,
    required this.allocatedTargetEgp,
    this.allocatedUnits,
    this.allocatedCartons,
    required this.actualRevenueEgp,
    required this.actualUnits,
    this.achievementPct,
    this.gapEgp = 0,
    this.skus = const [],
  });

  factory TargetBreakdownBranchModel.fromJson(Map<String, dynamic> json) =>
      TargetBreakdownBranchModel(
        branchKey: json['branch_key'] as String? ?? '',
        branchName: json['branch_name'] as String? ?? '',
        baselineRevenueEgp: _d(json['baseline_revenue_egp']),
        sharePct: _d(json['share_pct']),
        allocatedTargetEgp: _d(json['allocated_target_egp']),
        allocatedUnits: (json['allocated_target_units'] as num?)?.toInt(),
        allocatedCartons: _dn(json['allocated_target_cartons']),
        actualRevenueEgp: _d(json['actual_revenue_egp']),
        actualUnits: (json['actual_units'] as num?)?.toInt() ?? 0,
        achievementPct: _dn(json['achievement_pct']),
        gapEgp: _d(json['gap_egp']),
        skus: (json['skus'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TargetBreakdownSkuModel.fromJson)
            .toList(),
      );
}

class TargetBreakdownSkuModel {
  final String skuKey;
  final String skuName;
  final String category;
  final int unitsPerCarton;
  final double baselineRevenueEgp;
  final double sharePct;
  final double? avgUnitPriceEgp;
  final double allocatedTargetEgp;
  final int? allocatedUnits;
  final double? allocatedCartons;
  final double actualRevenueEgp;
  final int actualUnits;
  final double? achievementPct;
  final double gapEgp;

  const TargetBreakdownSkuModel({
    required this.skuKey,
    required this.skuName,
    this.category = '',
    this.unitsPerCarton = 0,
    this.baselineRevenueEgp = 0,
    required this.sharePct,
    this.avgUnitPriceEgp,
    required this.allocatedTargetEgp,
    this.allocatedUnits,
    this.allocatedCartons,
    required this.actualRevenueEgp,
    required this.actualUnits,
    this.achievementPct,
    this.gapEgp = 0,
  });

  factory TargetBreakdownSkuModel.fromJson(Map<String, dynamic> json) =>
      TargetBreakdownSkuModel(
        skuKey: json['sku_key'] as String? ?? '',
        skuName: json['sku_name'] as String? ?? '',
        category: json['category'] as String? ?? '',
        unitsPerCarton: (json['units_per_carton'] as num?)?.toInt() ?? 0,
        baselineRevenueEgp: _d(json['baseline_revenue_egp']),
        sharePct: _d(json['share_pct']),
        avgUnitPriceEgp: _dn(json['avg_unit_price_egp']),
        allocatedTargetEgp: _d(json['allocated_target_egp']),
        allocatedUnits: (json['allocated_target_units'] as num?)?.toInt(),
        allocatedCartons: _dn(json['allocated_target_cartons']),
        actualRevenueEgp: _d(json['actual_revenue_egp']),
        actualUnits: (json['actual_units'] as num?)?.toInt() ?? 0,
        achievementPct: _dn(json['achievement_pct']),
        gapEgp: _d(json['gap_egp']),
      );
}

/// A branch, or a SKU inside a branch, without baseline sales: it gets no
/// allocation and is listed apart under «بدون مبيعات سابقة».
class TargetBreakdownNoHistoryModel {
  /// `branch` or `sku`.
  final String kind;
  final String branchKey;
  final String branchName;
  final String skuName;
  final double actualRevenueEgp;
  final int actualUnits;

  const TargetBreakdownNoHistoryModel({
    required this.kind,
    required this.branchKey,
    required this.branchName,
    this.skuName = '',
    required this.actualRevenueEgp,
    required this.actualUnits,
  });

  bool get isBranch => kind == 'branch';

  factory TargetBreakdownNoHistoryModel.fromJson(Map<String, dynamic> json) =>
      TargetBreakdownNoHistoryModel(
        kind: json['kind'] as String? ?? 'branch',
        branchKey: json['branch_key'] as String? ?? '',
        branchName: json['branch_name'] as String? ?? '',
        skuName: json['sku_name'] as String? ?? '',
        actualRevenueEgp: _d(json['actual_revenue_egp']),
        actualUnits: (json['actual_units'] as num?)?.toInt() ?? 0,
      );
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;
double? _dn(Object? v) => (v as num?)?.toDouble();

import '../domain/share_target_plan.dart';

class ShareTargetBaselineCategory {
  const ShareTargetBaselineCategory({
    required this.category,
    required this.currentSharePct,
    required this.ownRevenueEgp,
    required this.marketRevenueEgp,
    required this.ownUnits,
    required this.avgPriceEgp,
    this.skuCount = 0,
  });

  final String category;
  final double currentSharePct;
  final double ownRevenueEgp;
  final double marketRevenueEgp;
  final double ownUnits;
  final double avgPriceEgp;
  final int skuCount;

  factory ShareTargetBaselineCategory.fromJson(Map<String, dynamic> json) {
    return ShareTargetBaselineCategory(
      category: json['category'] as String? ?? '',
      currentSharePct: (json['current_share_pct'] as num?)?.toDouble() ?? 0,
      ownRevenueEgp: (json['own_revenue_egp'] as num?)?.toDouble() ?? 0,
      marketRevenueEgp: (json['market_revenue_egp'] as num?)?.toDouble() ?? 0,
      ownUnits: (json['own_units'] as num?)?.toDouble() ?? 0,
      avgPriceEgp: (json['avg_price_egp'] as num?)?.toDouble() ?? 0,
      skuCount: (json['sku_count'] as num?)?.toInt() ?? 0,
    );
  }

  ShareCategoryInput toInput() => ShareCategoryInput(
        category: category,
        currentSharePct: currentSharePct,
        ownRevenueEgp: ownRevenueEgp,
        marketRevenueEgp: marketRevenueEgp,
        ownUnits: ownUnits,
        avgPriceEgp: avgPriceEgp,
      );
}

class ShareTargetBaselineBranch {
  const ShareTargetBaselineBranch({
    required this.branchKey,
    required this.branchName,
    required this.ownRevenueEgp,
  });

  final String branchKey;
  final String branchName;
  final double ownRevenueEgp;

  factory ShareTargetBaselineBranch.fromJson(Map<String, dynamic> json) {
    return ShareTargetBaselineBranch(
      branchKey: json['branch_key'] as String? ?? '',
      branchName: json['branch_name'] as String? ?? '',
      ownRevenueEgp: (json['own_revenue_egp'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ShareTargetBaseline {
  const ShareTargetBaseline({
    required this.retailerChain,
    required this.chainDisplayName,
    required this.year,
    required this.monthsWithData,
    required this.categories,
    required this.branches,
    required this.totalOwnEgp,
    required this.totalMarketEgp,
    required this.overallCurrentPct,
    this.monthKeys = const [],
  });

  final String retailerChain;
  final String chainDisplayName;
  final int year;
  final int monthsWithData;
  final List<ShareTargetBaselineCategory> categories;
  final List<ShareTargetBaselineBranch> branches;
  final double totalOwnEgp;
  final double totalMarketEgp;
  final double overallCurrentPct;
  final List<String> monthKeys;

  factory ShareTargetBaseline.fromJson(Map<String, dynamic> json) {
    return ShareTargetBaseline(
      retailerChain: json['retailer_chain'] as String? ?? '',
      chainDisplayName: json['chain_display_name'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 2026,
      monthsWithData: (json['months_with_data'] as num?)?.toInt() ?? 0,
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShareTargetBaselineCategory.fromJson)
          .toList(),
      branches: (json['branches'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShareTargetBaselineBranch.fromJson)
          .toList(),
      totalOwnEgp: (json['total_own_egp'] as num?)?.toDouble() ?? 0,
      totalMarketEgp: (json['total_market_egp'] as num?)?.toDouble() ?? 0,
      overallCurrentPct:
          (json['overall_current_share_pct'] as num?)?.toDouble() ?? 0,
      monthKeys: (json['month_keys'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class ShareCascadeBranch {
  const ShareCascadeBranch({
    required this.branchName,
    required this.historicalSharePct,
    required this.targetEgp,
    required this.upliftEgp,
    this.skus = const [],
  });

  final String branchName;
  final double historicalSharePct;
  final double targetEgp;
  final double upliftEgp;
  final List<ShareCascadeSku> skus;

  factory ShareCascadeBranch.fromJson(Map<String, dynamic> json) {
    return ShareCascadeBranch(
      branchName: json['branch_name'] as String? ?? '',
      historicalSharePct:
          (json['historical_share_pct'] as num?)?.toDouble() ?? 0,
      targetEgp: (json['target_egp'] as num?)?.toDouble() ?? 0,
      upliftEgp: (json['uplift_egp'] as num?)?.toDouble() ?? 0,
      skus: (json['skus'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShareCascadeSku.fromJson)
          .toList(),
    );
  }
}

class ShareCascadeSku {
  const ShareCascadeSku({
    required this.skuName,
    required this.sharePct,
    required this.targetEgp,
    this.targetUnits = 0,
  });

  final String skuName;
  final double sharePct;
  final double targetEgp;
  final double targetUnits;

  factory ShareCascadeSku.fromJson(Map<String, dynamic> json) {
    return ShareCascadeSku(
      skuName: json['sku_name'] as String? ?? '',
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0,
      targetEgp: (json['target_egp'] as num?)?.toDouble() ?? 0,
      targetUnits: (json['target_units'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ShareCascadeMonth {
  const ShareCascadeMonth({
    required this.month,
    required this.sharePct,
    required this.targetEgp,
  });

  final int month;
  final double sharePct;
  final double targetEgp;

  factory ShareCascadeMonth.fromJson(Map<String, dynamic> json) {
    return ShareCascadeMonth(
      month: (json['month'] as num?)?.toInt() ?? 0,
      sharePct: (json['share_pct'] as num?)?.toDouble() ?? 0,
      targetEgp: (json['target_egp'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ShareCategoryCascade {
  const ShareCategoryCascade({
    required this.category,
    required this.desiredSharePct,
    required this.targetRevenueEgp,
    required this.branches,
    required this.months,
  });

  final String category;
  final double desiredSharePct;
  final double targetRevenueEgp;
  final List<ShareCascadeBranch> branches;
  final List<ShareCascadeMonth> months;

  factory ShareCategoryCascade.fromJson(Map<String, dynamic> json) {
    final cat = json['category'] as Map<String, dynamic>? ?? const {};
    return ShareCategoryCascade(
      category: cat['category'] as String? ?? '',
      desiredSharePct: (cat['desired_share_pct'] as num?)?.toDouble() ?? 0,
      targetRevenueEgp: (cat['target_revenue_egp'] as num?)?.toDouble() ?? 0,
      branches: (json['branches'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShareCascadeBranch.fromJson)
          .toList(),
      months: (json['months'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShareCascadeMonth.fromJson)
          .toList(),
    );
  }
}

class ShareTargetPreview {
  const ShareTargetPreview({
    required this.plan,
    required this.cascades,
    required this.canSave,
  });

  final SharePlanSummary plan;
  final List<ShareCategoryCascade> cascades;
  final bool canSave;

  factory ShareTargetPreview.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'] as Map<String, dynamic>? ?? const {};
    final cats = (planJson['categories'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((c) => ShareCategoryPlan(
              category: c['category'] as String? ?? '',
              currentSharePct:
                  (c['current_share_pct'] as num?)?.toDouble() ?? 0,
              desiredSharePct:
                  (c['desired_share_pct'] as num?)?.toDouble() ?? 0,
              ownRevenueEgp: (c['own_revenue_egp'] as num?)?.toDouble() ?? 0,
              marketRevenueEgp:
                  (c['market_revenue_egp'] as num?)?.toDouble() ?? 0,
              projectedMarketEgp:
                  (c['projected_market_egp'] as num?)?.toDouble() ?? 0,
              targetRevenueEgp:
                  (c['target_revenue_egp'] as num?)?.toDouble() ?? 0,
              upliftRevenueEgp:
                  (c['uplift_revenue_egp'] as num?)?.toDouble() ?? 0,
              upliftPct: (c['uplift_pct'] as num?)?.toDouble() ?? 0,
              avgPriceEgp: (c['avg_price_egp'] as num?)?.toDouble() ?? 0,
              currentUnits: (c['current_units'] as num?)?.toDouble() ?? 0,
              targetUnits: (c['target_units'] as num?)?.toDouble() ?? 0,
              upliftUnits: (c['uplift_units'] as num?)?.toDouble() ?? 0,
              belowCurrent: c['below_current'] as bool? ?? false,
              exceedsMarket: c['exceeds_market'] as bool? ?? false,
            ))
        .toList();
    final opt = SharePlanOptions(
      marketGrowthPct:
          (planJson['market_growth_pct'] as num?)?.toDouble() ?? 0,
      monthsWithData: (planJson['months_with_data'] as num?)?.toInt() ?? 12,
      annualize: planJson['annualized'] as bool? ?? true,
    );
    final plan = summarizePlans(cats, opt);
    return ShareTargetPreview(
      plan: plan,
      cascades: (json['cascades'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShareCategoryCascade.fromJson)
          .toList(),
      canSave: json['can_save'] as bool? ?? plan.canProceed,
    );
  }
}

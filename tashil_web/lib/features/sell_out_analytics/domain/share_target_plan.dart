/// Pure client-side formulas for «مستهدف بالحصة السوقية» (mirrors Go sharetarget).
library;

class ShareCategoryInput {
  const ShareCategoryInput({
    required this.category,
    required this.currentSharePct,
    required this.ownRevenueEgp,
    required this.marketRevenueEgp,
    this.ownUnits = 0,
    this.avgPriceEgp = 0,
  });

  final String category;
  final double currentSharePct;
  final double ownRevenueEgp;
  final double marketRevenueEgp;
  final double ownUnits;
  final double avgPriceEgp;
}

class SharePlanOptions {
  const SharePlanOptions({
    this.marketGrowthPct = 0,
    this.monthsWithData = 12,
    this.annualize = true,
  });

  final double marketGrowthPct;
  final int monthsWithData;
  final bool annualize;

  double get annualizationFactor {
    if (!annualize || monthsWithData <= 0 || monthsWithData >= 12) return 1;
    return 12 / monthsWithData;
  }
}

class ShareCategoryPlan {
  const ShareCategoryPlan({
    required this.category,
    required this.currentSharePct,
    required this.desiredSharePct,
    required this.ownRevenueEgp,
    required this.marketRevenueEgp,
    required this.projectedMarketEgp,
    required this.targetRevenueEgp,
    required this.upliftRevenueEgp,
    required this.upliftPct,
    required this.avgPriceEgp,
    required this.currentUnits,
    required this.targetUnits,
    required this.upliftUnits,
    required this.belowCurrent,
    required this.exceedsMarket,
  });

  final String category;
  final double currentSharePct;
  final double desiredSharePct;
  final double ownRevenueEgp;
  final double marketRevenueEgp;
  final double projectedMarketEgp;
  final double targetRevenueEgp;
  final double upliftRevenueEgp;
  final double upliftPct;
  final double avgPriceEgp;
  final double currentUnits;
  final double targetUnits;
  final double upliftUnits;
  final bool belowCurrent;
  final bool exceedsMarket;
}

class SharePlanSummary {
  const SharePlanSummary({
    required this.categories,
    required this.totalOwnEgp,
    required this.totalMarketEgp,
    required this.totalProjectedEgp,
    required this.totalTargetEgp,
    required this.totalUpliftEgp,
    required this.totalUpliftPct,
    required this.totalCurrentUnits,
    required this.totalTargetUnits,
    required this.overallCurrentPct,
    required this.overallDesiredPct,
    required this.hasShareOver100,
    required this.hasBelowCurrent,
    required this.marketGrowthPct,
    required this.monthsWithData,
    required this.annualized,
    required this.annualizationFactor,
  });

  final List<ShareCategoryPlan> categories;
  final double totalOwnEgp;
  final double totalMarketEgp;
  final double totalProjectedEgp;
  final double totalTargetEgp;
  final double totalUpliftEgp;
  final double totalUpliftPct;
  final double totalCurrentUnits;
  final double totalTargetUnits;
  final double overallCurrentPct;
  final double overallDesiredPct;
  final bool hasShareOver100;
  final bool hasBelowCurrent;
  final double marketGrowthPct;
  final int monthsWithData;
  final bool annualized;
  final double annualizationFactor;

  bool get canProceed => !hasShareOver100;
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
double _round1(double v) => (v * 10).roundToDouble() / 10;

double exactCurrentSharePct(ShareCategoryInput in_) {
  if (in_.marketRevenueEgp > 0) {
    return in_.ownRevenueEgp / in_.marketRevenueEgp * 100;
  }
  return in_.currentSharePct;
}

ShareCategoryPlan planCategory(
  ShareCategoryInput in_,
  double desiredSharePct,
  SharePlanOptions opt,
) {
  final factor = opt.annualizationFactor;
  var g = 1 + opt.marketGrowthPct / 100;
  if (g < 0) g = 0;
  final own = in_.ownRevenueEgp * factor;
  final market = in_.marketRevenueEgp * factor;
  final projected = market * g;
  var avg = in_.avgPriceEgp;
  final units = in_.ownUnits * factor;
  if (avg <= 0 && units > 0 && own > 0) {
    avg = own / units;
  }
  final exact = market > 0 ? own / market * 100 : in_.currentSharePct;
  final displayCurrent =
      in_.currentSharePct > 0 ? in_.currentSharePct : exact;
  final desired = desiredSharePct;
  final exceeds = desired > 100;
  final target = desired / 100 * projected;
  final uplift = target - own;
  final upliftPct = own > 0 ? uplift / own * 100 : 0.0;
  final targetUnits = avg > 0 ? target / avg : 0.0;
  return ShareCategoryPlan(
    category: in_.category,
    currentSharePct: _round1(displayCurrent),
    desiredSharePct: _round1(desired),
    ownRevenueEgp: _round2(own),
    marketRevenueEgp: _round2(market),
    projectedMarketEgp: _round2(projected),
    targetRevenueEgp: _round2(target),
    upliftRevenueEgp: _round2(uplift),
    upliftPct: _round1(upliftPct),
    avgPriceEgp: _round2(avg),
    currentUnits: _round2(units),
    targetUnits: _round2(targetUnits),
    upliftUnits: _round2(targetUnits - units),
    belowCurrent: desired + 1e-9 < exact,
    exceedsMarket: exceeds,
  );
}

ShareCategoryPlan planCategoryDelta(
  ShareCategoryInput in_,
  double deltaPts,
  SharePlanOptions opt,
) =>
    planCategory(in_, exactCurrentSharePct(in_) + deltaPts, opt);

SharePlanSummary summarizePlans(
  List<ShareCategoryPlan> plans,
  SharePlanOptions opt,
) {
  var own = 0.0, market = 0.0, projected = 0.0, target = 0.0, uplift = 0.0;
  var curUnits = 0.0, tgtUnits = 0.0;
  var over100 = false, below = false;
  for (final p in plans) {
    own += p.ownRevenueEgp;
    market += p.marketRevenueEgp;
    projected += p.projectedMarketEgp;
    target += p.targetRevenueEgp;
    uplift += p.upliftRevenueEgp;
    curUnits += p.currentUnits;
    tgtUnits += p.targetUnits;
    if (p.exceedsMarket) over100 = true;
    if (p.belowCurrent) below = true;
  }
  own = _round2(own);
  market = _round2(market);
  projected = _round2(projected);
  target = _round2(target);
  uplift = _round2(uplift);
  return SharePlanSummary(
    categories: plans,
    totalOwnEgp: own,
    totalMarketEgp: market,
    totalProjectedEgp: projected,
    totalTargetEgp: target,
    totalUpliftEgp: uplift,
    totalUpliftPct: own > 0 ? _round1(uplift / own * 100) : 0,
    totalCurrentUnits: _round2(curUnits),
    totalTargetUnits: _round2(tgtUnits),
    overallCurrentPct: market > 0 ? _round1(own / market * 100) : 0,
    overallDesiredPct: projected > 0 ? _round1(target / projected * 100) : 0,
    hasShareOver100: over100,
    hasBelowCurrent: below,
    marketGrowthPct: opt.marketGrowthPct,
    monthsWithData: opt.monthsWithData,
    annualized: opt.annualize && opt.monthsWithData > 0 && opt.monthsWithData < 12,
    annualizationFactor: opt.annualizationFactor,
  );
}

SharePlanSummary planAll(
  List<ShareCategoryInput> inputs,
  List<double> desired,
  SharePlanOptions opt,
) {
  assert(inputs.length == desired.length);
  final plans = <ShareCategoryPlan>[];
  for (var i = 0; i < inputs.length; i++) {
    plans.add(planCategory(inputs[i], desired[i], opt));
  }
  return summarizePlans(plans, opt);
}

SharePlanSummary planAllDelta(
  List<ShareCategoryInput> inputs,
  double deltaPts,
  SharePlanOptions opt,
) {
  final plans = inputs.map((e) => planCategoryDelta(e, deltaPts, opt)).toList();
  return summarizePlans(plans, opt);
}

/// Research worked example (+5pt, flat, 10-month base). Amounts in millions EGP.
class ShareFixtureRow {
  const ShareFixtureRow({
    required this.category,
    required this.currentSharePct,
    required this.desiredSharePct,
    required this.ownM,
    required this.marketM,
    required this.targetM,
    required this.upliftM,
    required this.avgPrice,
    required this.currentUnits,
  });

  final String category;
  final double currentSharePct;
  final double desiredSharePct;
  final double ownM;
  final double marketM;
  final double targetM;
  final double upliftM;
  final double avgPrice;
  final double currentUnits;
}

List<ShareFixtureRow> workedExampleFathalla2026() => const [
      ShareFixtureRow(
        category: 'صابون سائل اطباق',
        currentSharePct: 39.0,
        desiredSharePct: 44.0,
        ownM: 43.44,
        marketM: 111.24,
        targetM: 49.00,
        upliftM: 5.56,
        avgPrice: 100.4,
        currentUnits: 432526,
      ),
      ShareFixtureRow(
        category: 'منعمات ملابس',
        currentSharePct: 30.0,
        desiredSharePct: 35.0,
        ownM: 14.49,
        marketM: 48.35,
        targetM: 16.91,
        upliftM: 2.42,
        avgPrice: 105.6,
        currentUnits: 137212,
      ),
      ShareFixtureRow(
        category: 'هاند وواش',
        currentSharePct: 29.9,
        desiredSharePct: 34.9,
        ownM: 11.91,
        marketM: 39.82,
        targetM: 13.90,
        upliftM: 1.99,
        avgPrice: 64.6,
        currentUnits: 184437,
      ),
      ShareFixtureRow(
        category: 'كلور ألوان',
        currentSharePct: 30.2,
        desiredSharePct: 35.2,
        ownM: 7.80,
        marketM: 25.80,
        targetM: 9.09,
        upliftM: 1.29,
        avgPrice: 64.7,
        currentUnits: 120464,
      ),
      ShareFixtureRow(
        category: 'كلور عادى',
        currentSharePct: 40.1,
        desiredSharePct: 45.1,
        ownM: 7.31,
        marketM: 18.22,
        targetM: 8.22,
        upliftM: 0.91,
        avgPrice: 44.0,
        currentUnits: 166246,
      ),
      ShareFixtureRow(
        category: 'شاور جيل',
        currentSharePct: 7.2,
        desiredSharePct: 12.2,
        ownM: 5.53,
        marketM: 76.59,
        targetM: 9.36,
        upliftM: 3.83,
        avgPrice: 132.3,
        currentUnits: 41788,
      ),
      ShareFixtureRow(
        category: 'مطهر عام',
        currentSharePct: 29.5,
        desiredSharePct: 34.5,
        ownM: 4.23,
        marketM: 14.35,
        targetM: 4.95,
        upliftM: 0.72,
        avgPrice: 100.1,
        currentUnits: 42267,
      ),
      ShareFixtureRow(
        category: 'مساحيق جيل اتوماتيك',
        currentSharePct: 3.6,
        desiredSharePct: 8.6,
        ownM: 4.18,
        marketM: 116.49,
        targetM: 10.00,
        upliftM: 5.82,
        avgPrice: 163.7,
        currentUnits: 25529,
      ),
    ];

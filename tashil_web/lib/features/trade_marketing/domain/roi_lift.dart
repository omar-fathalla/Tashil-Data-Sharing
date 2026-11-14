/// How the campaign-free sales baseline was chosen. There is no
/// cherry-picking between MoM and YoY lifts.
enum RoiBaselineMethod {
  /// Last-year same calendar month (seasonal YoY control period).
  yoySeasonal,

  /// Legacy id from the short-lived organic-ratio method; treated as
  /// [yoySeasonal] when reading mid-deploy API responses.
  yoyTrend,

  /// Legacy id from the prior-organic-average fallback; no longer emitted.
  priorOrganicAverage,

  /// Not enough history to form a baseline (no last-year same month).
  unavailable,
}

/// Calendar month key used when walking a chain's sales history.
class RoiMonthKey {
  final int year;
  final int month;
  const RoiMonthKey(this.year, this.month);

  RoiMonthKey get previous {
    if (month == 1) return RoiMonthKey(year - 1, 12);
    return RoiMonthKey(year, month - 1);
  }

  RoiMonthKey get lastYear => RoiMonthKey(year - 1, month);

  @override
  bool operator ==(Object other) =>
      other is RoiMonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Result of the standard incremental-lift / ROMI calculation.
class RoiLiftResult {
  final RoiBaselineMethod method;
  final double? baselineSalesEgp;
  final double? organicYoyRatio;
  final int organicMonthsUsed;
  final double? incrementalLiftEgp;
  final double? liftVsBaselinePct;
  final double? romiMultiple;
  final double? netRoiPct;
  final String methodAr;
  final String? unavailableMessageAr;

  const RoiLiftResult({
    required this.method,
    this.baselineSalesEgp,
    this.organicYoyRatio,
    this.organicMonthsUsed = 0,
    this.incrementalLiftEgp,
    this.liftVsBaselinePct,
    this.romiMultiple,
    this.netRoiPct,
    required this.methodAr,
    this.unavailableMessageAr,
  });

  bool get available => method != RoiBaselineMethod.unavailable;

  static const RoiLiftResult unavailable = RoiLiftResult(
    method: RoiBaselineMethod.unavailable,
    methodAr: kRoiNoLastYearAr,
    unavailableMessageAr: kRoiNoLastYearAr,
  );
}

/// Shown when last-year same-month Sell-Out is missing.
const kRoiNoLastYearAr = 'لا توجد بيانات للعام السابق';

/// Alias kept for existing call sites / tests.
const kRoiBaselineUnavailableAr = kRoiNoLastYearAr;

/// Standing explanation of the method (tooltip / info line).
const kRoiLiftMethodExplainerAr =
    'العائد = (مبيعات الشهر الحالي − مبيعات نفس الشهر العام السابق) ÷ المصروف. الزيادة قد تكون سالبة. عند غياب بيانات العام السابق يُعرض —.';

const String kRoiYoySeasonalMethodAr =
    'الأساس = مبيعات نفس الشهر العام السابق (مقارنة موسمية)';

String roiBaselineMethodId(RoiBaselineMethod m) {
  switch (m) {
    case RoiBaselineMethod.yoySeasonal:
      return 'yoy_seasonal';
    case RoiBaselineMethod.yoyTrend:
      return 'yoy_trend';
    case RoiBaselineMethod.priorOrganicAverage:
      return 'prior_organic_avg';
    case RoiBaselineMethod.unavailable:
      return 'unavailable';
  }
}

RoiBaselineMethod roiBaselineMethodFromId(String? id) {
  switch (id) {
    case 'yoy_seasonal':
      return RoiBaselineMethod.yoySeasonal;
    case 'yoy_trend':
      // Mid-deploy / cached responses: treat as seasonal YoY.
      return RoiBaselineMethod.yoySeasonal;
    case 'prior_organic_avg':
      return RoiBaselineMethod.priorOrganicAverage;
    default:
      return RoiBaselineMethod.unavailable;
  }
}

/// Expected sales for [target] without the campaign = last-year same month.
/// Incremental lift, ROMI and Net ROI% follow from that seasonal baseline.
/// [salesByMonth] / [campaignMonths] are accepted for call-site compatibility
/// but are not used. Lift may be negative.
RoiLiftResult computeRoiLift({
  required double currentSalesEgp,
  required double lastYearSameMonthSalesEgp,
  required double marketingSpendEgp,
  required RoiMonthKey target,
  Map<RoiMonthKey, double> salesByMonth = const {},
  Set<RoiMonthKey> campaignMonths = const {},
}) {
  // Seasonal YoY only needs last-year sales. [target], [salesByMonth] and
  // [campaignMonths] stay in the signature for call-site / Go parity.
  // Keep signature params referenced for analyzer / call-site parity.
  if (target.year < 0 && salesByMonth.isNotEmpty && campaignMonths.isNotEmpty) {
    return RoiLiftResult.unavailable;
  }
  if (lastYearSameMonthSalesEgp <= 0) {
    return RoiLiftResult.unavailable;
  }

  final baseline = lastYearSameMonthSalesEgp;
  final lift = currentSalesEgp - baseline;
  final liftPct = baseline > 0 ? (lift / baseline) * 100.0 : null;
  double? romi;
  double? netRoi;
  if (marketingSpendEgp > 0) {
    romi = lift / marketingSpendEgp;
    netRoi = ((lift - marketingSpendEgp) / marketingSpendEgp) * 100.0;
  }
  return RoiLiftResult(
    method: RoiBaselineMethod.yoySeasonal,
    baselineSalesEgp: baseline,
    organicYoyRatio: 1.0,
    organicMonthsUsed: 0,
    incrementalLiftEgp: lift,
    liftVsBaselinePct: liftPct,
    romiMultiple: romi,
    netRoiPct: netRoi,
    methodAr: kRoiYoySeasonalMethodAr,
  );
}

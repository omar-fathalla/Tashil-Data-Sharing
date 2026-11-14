/// How the campaign-free sales baseline was chosen. There is no
/// cherry-picking between MoM and YoY lifts.
enum RoiBaselineMethod {
  /// Last-year same month × trailing organic YoY ratio (or × 1 when
  /// no organic months are available to estimate a trend).
  yoyTrend,

  /// Average of the previous non-campaign months (no last-year sales).
  priorOrganicAverage,

  /// Not enough history to form a baseline.
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
    methodAr: kRoiBaselineUnavailableAr,
    unavailableMessageAr: kRoiBaselineUnavailableAr,
  );
}

/// Shown when a baseline cannot be computed.
const kRoiBaselineUnavailableAr =
    'لا يمكن حساب العائد: لا توجد بيانات أساس كافية';

/// Standing explanation of the method (tooltip / info line).
const kRoiLiftMethodExplainerAr =
    'العائد = الزيادة عن المبيعات المتوقعة بدون الحملة ÷ المصروف. المبيعات المتوقعة = مبيعات نفس الشهر العام السابق × متوسط النمو العضوي للسلسلة في الأشهر بدون حملات، أو متوسط تلك الأشهر إذا لم تتوفر بيانات العام السابق.';

const int kRoiOrganicLookbackMonths = 12;
const int kRoiOrganicWindow = 3;

String roiBaselineMethodId(RoiBaselineMethod m) {
  switch (m) {
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
    case 'yoy_trend':
      return RoiBaselineMethod.yoyTrend;
    case 'prior_organic_avg':
      return RoiBaselineMethod.priorOrganicAverage;
    default:
      return RoiBaselineMethod.unavailable;
  }
}

String yoyTrendMethodAr(int monthsUsed) {
  if (monthsUsed <= 0) {
    return 'الأساس = مبيعات نفس الشهر العام السابق (لا يوجد أشهر عضوية كافية لحساب الاتجاه)';
  }
  return 'الأساس = مبيعات نفس الشهر العام السابق × متوسط النمو العضوي لآخر $monthsUsed أشهر بدون حملات';
}

String priorOrganicMethodAr(int monthsUsed) {
  return 'الأساس = متوسط مبيعات آخر $monthsUsed أشهر بدون حملات (لا توجد بيانات للعام السابق)';
}

/// Expected sales for [target] without the campaign, incremental lift,
/// ROMI and Net ROI%. Walks [salesByMonth] and [campaignMonths] back
/// up to [kRoiOrganicLookbackMonths]. Lift may be negative.
RoiLiftResult computeRoiLift({
  required double currentSalesEgp,
  required double lastYearSameMonthSalesEgp,
  required double marketingSpendEgp,
  required RoiMonthKey target,
  Map<RoiMonthKey, double> salesByMonth = const {},
  Set<RoiMonthKey> campaignMonths = const {},
}) {
  RoiLiftResult finish({
    required RoiBaselineMethod method,
    required double baseline,
    double? organicRatio,
    int monthsUsed = 0,
    required String methodAr,
  }) {
    final lift = currentSalesEgp - baseline;
    final liftPct = baseline > 0 ? (lift / baseline) * 100.0 : null;
    double? romi;
    double? netRoi;
    if (marketingSpendEgp > 0) {
      romi = lift / marketingSpendEgp;
      netRoi = ((lift - marketingSpendEgp) / marketingSpendEgp) * 100.0;
    }
    return RoiLiftResult(
      method: method,
      baselineSalesEgp: baseline,
      organicYoyRatio: organicRatio,
      organicMonthsUsed: monthsUsed,
      incrementalLiftEgp: lift,
      liftVsBaselinePct: liftPct,
      romiMultiple: romi,
      netRoiPct: netRoi,
      methodAr: methodAr,
    );
  }

  if (lastYearSameMonthSalesEgp > 0) {
    final ratios = <double>[];
    var cursor = target.previous;
    for (var i = 0;
        i < kRoiOrganicLookbackMonths && ratios.length < kRoiOrganicWindow;
        i++) {
      if (!campaignMonths.contains(cursor)) {
        final sales = salesByMonth[cursor] ?? 0;
        final ly = salesByMonth[cursor.lastYear] ?? 0;
        if (sales > 0 && ly > 0) {
          ratios.add(sales / ly);
        }
      }
      cursor = cursor.previous;
    }
    final monthsUsed = ratios.length;
    final ratio = monthsUsed > 0
        ? ratios.fold<double>(0, (a, b) => a + b) / monthsUsed
        : 1.0;
    return finish(
      method: RoiBaselineMethod.yoyTrend,
      baseline: lastYearSameMonthSalesEgp * ratio,
      organicRatio: ratio,
      monthsUsed: monthsUsed,
      methodAr: yoyTrendMethodAr(monthsUsed),
    );
  }

  final organicSales = <double>[];
  var cursor = target.previous;
  for (var i = 0;
      i < kRoiOrganicLookbackMonths && organicSales.length < kRoiOrganicWindow;
      i++) {
    if (!campaignMonths.contains(cursor)) {
      final sales = salesByMonth[cursor] ?? 0;
      if (sales > 0) organicSales.add(sales);
    }
    cursor = cursor.previous;
  }
  if (organicSales.isEmpty) return RoiLiftResult.unavailable;
  final monthsUsed = organicSales.length;
  final baseline =
      organicSales.fold<double>(0, (a, b) => a + b) / monthsUsed;
  return finish(
    method: RoiBaselineMethod.priorOrganicAverage,
    baseline: baseline,
    monthsUsed: monthsUsed,
    methodAr: priorOrganicMethodAr(monthsUsed),
  );
}

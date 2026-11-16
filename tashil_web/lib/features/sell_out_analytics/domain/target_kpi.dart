import '../../../core/network/api_client.dart';

/// KPI-card numbers of the Targets tab.
///
/// The target card keeps every target (a 2027 target counts), but achievement
/// % and the gap only compare periods that have actual sales: a future year
/// with no sales yet must not read as "0% achieved, gap −180M".
class TargetKpis {
  const TargetKpis({
    required this.targetRevenue,
    required this.targetUnits,
    required this.actualRevenue,
    required this.actualUnits,
    required this.comparableTargetRevenue,
    required this.comparableActualRevenue,
    required this.comparableTargetUnits,
    required this.comparableActualUnits,
    required this.noDataTargetRevenue,
    required this.noDataTargetUnits,
    required this.targetsCount,
    required this.comparableCount,
    required this.noDataCount,
  });

  /// All targets in the current filter (target card).
  final double targetRevenue;
  final double targetUnits;

  /// Actual sales of the periods that have any (achieved card).
  final double actualRevenue;
  final double actualUnits;

  /// Targets whose period has actual sales: the only ones compared.
  final double comparableTargetRevenue;
  final double comparableActualRevenue;
  final double comparableTargetUnits;
  final double comparableActualUnits;

  /// Targets without sales yet (future periods), shown apart.
  final double noDataTargetRevenue;
  final double noDataTargetUnits;
  final int targetsCount;
  final int comparableCount;
  final int noDataCount;

  bool get hasTargets => targetsCount > 0;
  bool get hasComparable => comparableCount > 0;

  /// Targets exist but none has sales yet (e.g. only 2027 selected).
  bool get onlyNoData => hasTargets && !hasComparable;

  /// The target card total includes targets without sales.
  bool get includesNoData => noDataCount > 0 && hasComparable;

  /// Achievement over the comparable targets (revenue, else units); null
  /// when nothing is comparable: shown as «—», never 0.
  double? get achievementPct {
    if (!hasComparable) return null;
    if (comparableTargetRevenue > 0) {
      return _round1(comparableActualRevenue / comparableTargetRevenue * 100);
    }
    if (comparableTargetUnits > 0) {
      return _round1(comparableActualUnits / comparableTargetUnits * 100);
    }
    return null;
  }

  /// Achieved − target over the comparable targets (negative = still to go).
  double? get gapRevenue =>
      hasComparable ? comparableActualRevenue - comparableTargetRevenue : null;

  factory TargetKpis.fromSummary(TargetsSummaryModel summary) {
    double tr = 0, tu = 0, ar = 0, au = 0;
    double ctr = 0, car = 0, ctu = 0, cau = 0, ndr = 0, ndu = 0;
    var comparable = 0, noData = 0;
    for (final item in summary.items) {
      tr += item.targetRevenueEgp;
      tu += item.targetUnits;
      ar += item.actualRevenueEgp;
      au += item.actualUnits;
      if (item.hasActuals) {
        ctr += item.targetRevenueEgp;
        car += item.actualRevenueEgp;
        ctu += item.targetUnits;
        cau += item.actualUnits;
        comparable++;
      } else {
        ndr += item.targetRevenueEgp;
        ndu += item.targetUnits;
        noData++;
      }
    }
    return TargetKpis(
      targetRevenue: tr,
      targetUnits: tu,
      actualRevenue: ar,
      actualUnits: au,
      comparableTargetRevenue: ctr,
      comparableActualRevenue: car,
      comparableTargetUnits: ctu,
      comparableActualUnits: cau,
      noDataTargetRevenue: ndr,
      noDataTargetUnits: ndu,
      targetsCount: summary.items.length,
      comparableCount: comparable,
      noDataCount: noData,
    );
  }

  static double _round1(double v) => (v * 10).round() / 10;
}

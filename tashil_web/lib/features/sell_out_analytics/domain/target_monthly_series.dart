import '../../../core/network/api_client.dart';
import 'target_achievement_status.dart';

const monthLabelsAr = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// One calendar month in a Sell-Out target detail series.
class TargetMonthPoint {
  const TargetMonthPoint({
    required this.year,
    required this.month,
    required this.labelAr,
    required this.targetRevenue,
    required this.targetUnits,
    required this.actualRevenue,
    required this.actualUnits,
    required this.hasActuals,
    required this.fromExplicitMonthlyTarget,
  });

  final int year;
  final int month;
  final String labelAr;
  final double targetRevenue;
  final double targetUnits;
  final double actualRevenue;
  final double actualUnits;
  final bool hasActuals;
  final bool fromExplicitMonthlyTarget;

  double get gapRevenue => actualRevenue - targetRevenue;

  double? get achievementPct {
    if (!hasActuals) return null;
    if (targetRevenue > 0) {
      return round1(actualRevenue / targetRevenue * 100);
    }
    if (targetUnits > 0) {
      return round1(actualUnits / targetUnits * 100);
    }
    return null;
  }

  TargetAchievementStatus get status =>
      TargetAchievementStatus.fromPct(achievementPct, hasActuals: hasActuals);
}

double round1(double v) => (v * 10).round() / 10;

/// Cumulative series for the monthly chart (target vs actual).
class TargetCumulativePoint {
  const TargetCumulativePoint({
    required this.month,
    required this.labelAr,
    required this.cumulativeTarget,
    required this.cumulativeActual,
    required this.hasActuals,
  });

  final int month;
  final String labelAr;
  final double cumulativeTarget;
  final double cumulativeActual;
  final bool hasActuals;
}

/// Builds the 12-month view for a Sell-Out target.
///
/// Monthly target = yearly / 12 unless explicit monthly targets exist for the
/// same chain/year (and branch/category scope). Actuals prefer explicit monthly
/// target rows, then [TargetComparisonModel.monthlyPhasing] from the API.
class TargetMonthlySeries {
  const TargetMonthlySeries({
    required this.months,
    required this.cumulative,
    required this.targetToDateRevenue,
    required this.actualToDateRevenue,
    required this.hasActualsToDate,
  });

  final List<TargetMonthPoint> months;
  final List<TargetCumulativePoint> cumulative;
  final double targetToDateRevenue;
  final double actualToDateRevenue;
  final bool hasActualsToDate;

  double? get achievementToDatePct {
    if (!hasActualsToDate || targetToDateRevenue <= 0) return null;
    return round1(actualToDateRevenue / targetToDateRevenue * 100);
  }

  TargetAchievementStatus get statusToDate => TargetAchievementStatus.fromPct(
        achievementToDatePct,
        hasActuals: hasActualsToDate,
      );

  factory TargetMonthlySeries.build({
    required TargetComparisonModel target,
    List<TargetComparisonModel> siblings = const [],
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final year = target.year;
    final explicitByMonth = <int, TargetComparisonModel>{};
    for (final s in siblings) {
      if (s.retailerChain != target.retailerChain) continue;
      if (s.year != year) continue;
      if (s.month < 1 || s.month > 12) continue;
      if (s.branchName != target.branchName) continue;
      if (s.category != target.category) continue;
      explicitByMonth[s.month] = s;
    }

    final phasingByMonth = <int, TargetMonthBreakdownModel>{};
    for (final m in target.monthlyPhasing) {
      if (m.month >= 1 && m.month <= 12) phasingByMonth[m.month] = m;
    }

    final equalRev = target.targetRevenueEgp / 12.0;
    final equalUnits = target.targetUnits / 12.0;
    final months = <TargetMonthPoint>[];

    for (var month = 1; month <= 12; month++) {
      final explicit = explicitByMonth[month];
      final phasing = phasingByMonth[month];
      final label = monthLabelsAr[month - 1];

      if (explicit != null) {
        months.add(TargetMonthPoint(
          year: year,
          month: month,
          labelAr: label,
          targetRevenue: explicit.targetRevenueEgp,
          targetUnits: explicit.targetUnits,
          actualRevenue: explicit.actualRevenueEgp,
          actualUnits: explicit.actualUnits,
          hasActuals: explicit.hasActuals,
          fromExplicitMonthlyTarget: true,
        ));
        continue;
      }

      final targetRev =
          (phasing != null && phasing.targetRevenueEgp > 0) ? phasing.targetRevenueEgp : equalRev;
      final targetUnits =
          (phasing != null && phasing.targetUnits > 0) ? phasing.targetUnits : equalUnits;
      final hasActuals = phasing != null &&
          (phasing.actualRevenueEgp > 0 || phasing.actualUnits > 0);

      months.add(TargetMonthPoint(
        year: year,
        month: month,
        labelAr: label,
        targetRevenue: targetRev,
        targetUnits: targetUnits,
        actualRevenue: phasing?.actualRevenueEgp ?? 0,
        actualUnits: phasing?.actualUnits ?? 0,
        hasActuals: hasActuals,
        fromExplicitMonthlyTarget: false,
      ));
    }

    final cumulative = <TargetCumulativePoint>[];
    var cumT = 0.0;
    var cumA = 0.0;
    var anyActual = false;
    for (final m in months) {
      cumT += m.targetRevenue;
      if (m.hasActuals) {
        cumA += m.actualRevenue;
        anyActual = true;
      }
      cumulative.add(TargetCumulativePoint(
        month: m.month,
        labelAr: m.labelAr,
        cumulativeTarget: cumT,
        cumulativeActual: cumA,
        hasActuals: anyActual,
      ));
    }

    final monthlyTargets = months.map((m) => m.targetRevenue).toList();
    final ttd = TargetAchievementStatus.targetToDate(
      yearlyTarget: target.targetRevenueEgp,
      year: year,
      asOf: now,
      monthlyTargets: monthlyTargets,
    );
    final lastMonth = now.year > year
        ? 12
        : (now.year < year ? 0 : now.month.clamp(0, 12));
    var atd = 0.0;
    var hasAtd = false;
    for (final m in months) {
      if (m.month > lastMonth) break;
      if (m.hasActuals) {
        atd += m.actualRevenue;
        hasAtd = true;
      }
    }

    return TargetMonthlySeries(
      months: months,
      cumulative: cumulative,
      targetToDateRevenue: ttd,
      actualToDateRevenue: atd,
      hasActualsToDate: hasAtd,
    );
  }
}

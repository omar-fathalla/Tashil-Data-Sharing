/// Achievement status for the Sell-Out Targets redesign (option B).
///
/// Thresholds are vs **target-to-date** (or the period target when the
/// period is fully elapsed): محقق ≥100%, قريب 90–99.9%, أقل <90%.
enum TargetAchievementKind {
  achieved,
  near,
  below,
  noData,
}

class TargetAchievementStatus {
  const TargetAchievementStatus({
    required this.kind,
    required this.labelAr,
    this.pct,
  });

  final TargetAchievementKind kind;
  final String labelAr;
  final double? pct;

  static const nearFloor = 90.0;

  static TargetAchievementStatus fromPct(double? pct, {required bool hasActuals}) {
    if (!hasActuals || pct == null) {
      return const TargetAchievementStatus(
        kind: TargetAchievementKind.noData,
        labelAr: 'لا توجد مبيعات بعد',
      );
    }
    if (pct >= 100) {
      return TargetAchievementStatus(
        kind: TargetAchievementKind.achieved,
        labelAr: 'محقق',
        pct: pct,
      );
    }
    if (pct >= nearFloor) {
      return TargetAchievementStatus(
        kind: TargetAchievementKind.near,
        labelAr: 'قريب من المستهدف',
        pct: pct,
      );
    }
    return TargetAchievementStatus(
      kind: TargetAchievementKind.below,
      labelAr: 'أقل من المستهدف',
      pct: pct,
    );
  }

  /// Target expected by [asOf] for a yearly goal (equal months, or sum of
  /// explicit monthly targets through the as-of month).
  static double targetToDate({
    required double yearlyTarget,
    required int year,
    required DateTime asOf,
    List<double>? monthlyTargets,
  }) {
    if (asOf.year < year) return 0;
    final lastMonth = asOf.year > year ? 12 : asOf.month.clamp(1, 12);
    if (monthlyTargets != null && monthlyTargets.length == 12) {
      var sum = 0.0;
      for (var i = 0; i < lastMonth; i++) {
        sum += monthlyTargets[i];
      }
      return sum;
    }
    return yearlyTarget * lastMonth / 12.0;
  }
}

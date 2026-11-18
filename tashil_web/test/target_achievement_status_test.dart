import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/target_achievement_status.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/target_monthly_series.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  group('TargetAchievementStatus', () {
    test('thresholds: محقق ≥100, قريب 90–99.9, أقل <90', () {
      expect(
        TargetAchievementStatus.fromPct(100, hasActuals: true).kind,
        TargetAchievementKind.achieved,
      );
      expect(
        TargetAchievementStatus.fromPct(99.9, hasActuals: true).labelAr,
        'قريب من المستهدف',
      );
      expect(
        TargetAchievementStatus.fromPct(90, hasActuals: true).kind,
        TargetAchievementKind.near,
      );
      expect(
        TargetAchievementStatus.fromPct(89.9, hasActuals: true).kind,
        TargetAchievementKind.below,
      );
      expect(
        TargetAchievementStatus.fromPct(null, hasActuals: false).kind,
        TargetAchievementKind.noData,
      );
    });

    test('target-to-date uses elapsed months of equal split', () {
      final ttd = TargetAchievementStatus.targetToDate(
        yearlyTarget: 120,
        year: 2026,
        asOf: DateTime(2026, 3, 15),
      );
      expect(ttd, 30); // 3/12 * 120
    });
  });

  group('TargetMonthlySeries', () {
    test('yearly target splits to 12 equal months unless monthly exist', () {
      final yearly = TargetComparisonModel.fromJson({
        'id': 'y',
        'target_type': 'sell_out',
        'retailer_chain': 'fathalla',
        'chain_display_name': 'فتح الله',
        'year': 2026,
        'month': 0,
        'month_label': 'سنة 2026',
        'branch_name': 'كل الفروع',
        'category': 'كل الفئات',
        'target_revenue_egp': 120000000,
        'actual_revenue_egp': 30000000,
        'variance_revenue_egp': -90000000,
        'achievement_rev_pct': 25,
        'target_units': 12000,
        'actual_units': 3000,
        'has_actuals': true,
        'status': 'at_risk',
        'status_ar': 'أقل من المستهدف',
        'monthly_phasing': [
          for (var m = 1; m <= 3; m++)
            {
              'year': 2026,
              'month': m,
              'month_label_ar': 'm$m',
              'month_label_en': 'm$m',
              'target_revenue_egp': 10000000,
              'target_units': 1000,
              'actual_revenue_egp': 10000000,
              'actual_units': 1000,
              'achievement_pct': 100,
            },
        ],
      });
      final series = TargetMonthlySeries.build(
        target: yearly,
        asOf: DateTime(2026, 3, 20),
      );
      expect(series.months, hasLength(12));
      expect(series.months.first.targetRevenue, 10000000);
      expect(series.months[3].targetRevenue, closeTo(10000000, 0.01));
      expect(series.months[0].hasActuals, isTrue);
      expect(series.months[11].hasActuals, isFalse);
      expect(series.targetToDateRevenue, closeTo(30000000, 0.01));
      expect(series.actualToDateRevenue, closeTo(30000000, 0.01));
      expect(series.achievementToDatePct, 100);
    });

    test('explicit monthly targets override equal split', () {
      final yearly = TargetComparisonModel.fromJson({
        'id': 'y',
        'target_type': 'sell_out',
        'retailer_chain': 'fathalla',
        'chain_display_name': 'فتح الله',
        'year': 2026,
        'month': 0,
        'month_label': 'سنة 2026',
        'branch_name': 'كل الفروع',
        'category': 'كل الفئات',
        'target_revenue_egp': 120,
        'actual_revenue_egp': 0,
        'variance_revenue_egp': 0,
        'achievement_rev_pct': 0,
        'target_units': 12,
        'actual_units': 0,
        'has_actuals': false,
        'status': 'no_data',
        'status_ar': 'لا توجد مبيعات بعد',
      });
      final jan = TargetComparisonModel.fromJson({
        'id': 'j',
        'target_type': 'sell_out',
        'retailer_chain': 'fathalla',
        'chain_display_name': 'فتح الله',
        'year': 2026,
        'month': 1,
        'month_label': 'يناير 2026',
        'branch_name': 'كل الفروع',
        'category': 'كل الفئات',
        'target_revenue_egp': 50,
        'actual_revenue_egp': 40,
        'variance_revenue_egp': -10,
        'achievement_rev_pct': 80,
        'target_units': 5,
        'actual_units': 4,
        'has_actuals': true,
        'status': 'at_risk',
        'status_ar': 'أقل من المستهدف',
      });
      final series = TargetMonthlySeries.build(
        target: yearly,
        siblings: [jan],
        asOf: DateTime(2026, 1, 31),
      );
      expect(series.months.first.targetRevenue, 50);
      expect(series.months.first.fromExplicitMonthlyTarget, isTrue);
      expect(series.months[1].targetRevenue, 10); // equal split of yearly
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/features/trade_marketing/domain/roi_lift.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';

void main() {
  group('computeRoiLift', () {
    test('yoy trend uses the average organic ratio of 3 non-campaign months',
        () {
      const target = RoiMonthKey(2026, 2);
      final res = computeRoiLift(
        currentSalesEgp: 1000000,
        lastYearSameMonthSalesEgp: 800000,
        marketingSpendEgp: 50000,
        target: target,
        salesByMonth: {
          const RoiMonthKey(2026, 1): 110000,
          const RoiMonthKey(2025, 1): 100000,
          const RoiMonthKey(2025, 12): 200000,
          const RoiMonthKey(2024, 12): 200000,
          const RoiMonthKey(2025, 11): 120000,
          const RoiMonthKey(2024, 11): 100000,
          const RoiMonthKey(2025, 10): 999999,
          const RoiMonthKey(2024, 10): 100000,
        },
        campaignMonths: {const RoiMonthKey(2025, 10), target},
      );
      expect(res.method, RoiBaselineMethod.yoyTrend);
      expect(res.organicMonthsUsed, 3);
      expect(res.organicYoyRatio, closeTo(1.10, 1e-9));
      expect(res.baselineSalesEgp, closeTo(880000, 1e-6));
      expect(res.incrementalLiftEgp, closeTo(120000, 1e-6));
      expect(res.romiMultiple, closeTo(2.4, 1e-9));
      expect(res.netRoiPct, closeTo(140, 1e-9));
    });

    test('yoy trend uses ratio 1 when no organic months exist', () {
      final res = computeRoiLift(
        currentSalesEgp: 1200000,
        lastYearSameMonthSalesEgp: 800000,
        marketingSpendEgp: 50000,
        target: const RoiMonthKey(2026, 2),
      );
      expect(res.organicMonthsUsed, 0);
      expect(res.organicYoyRatio, 1);
      expect(res.baselineSalesEgp, closeTo(800000, 1e-6));
      expect(res.incrementalLiftEgp, closeTo(400000, 1e-6));
      expect(res.romiMultiple, closeTo(8, 1e-9));
    });

    test('negative lift and ROMI are returned honestly', () {
      final res = computeRoiLift(
        currentSalesEgp: 700000,
        lastYearSameMonthSalesEgp: 800000,
        marketingSpendEgp: 50000,
        target: const RoiMonthKey(2026, 2),
      );
      expect(res.incrementalLiftEgp, closeTo(-100000, 1e-6));
      expect(res.romiMultiple, closeTo(-2, 1e-9));
      expect(res.netRoiPct, closeTo(-300, 1e-9));
    });

    test('falls back to the average of prior non-campaign months when no LY',
        () {
      final res = computeRoiLift(
        currentSalesEgp: 130000,
        lastYearSameMonthSalesEgp: 0,
        marketingSpendEgp: 10000,
        target: const RoiMonthKey(2026, 4),
        salesByMonth: {
          const RoiMonthKey(2026, 3): 110000,
          const RoiMonthKey(2026, 2): 999999,
          const RoiMonthKey(2026, 1): 100000,
          const RoiMonthKey(2025, 12): 90000,
        },
        campaignMonths: {const RoiMonthKey(2026, 2)},
      );
      expect(res.method, RoiBaselineMethod.priorOrganicAverage);
      expect(res.organicMonthsUsed, 3);
      expect(res.baselineSalesEgp, closeTo(100000, 1e-6));
      expect(res.incrementalLiftEgp, closeTo(30000, 1e-6));
      expect(res.romiMultiple, closeTo(3, 1e-9));
      expect(res.methodAr, contains('لا توجد بيانات للعام السابق'));
    });

    test('unavailable when there is no last-year sales and no organic history',
        () {
      final res = computeRoiLift(
        currentSalesEgp: 300000,
        lastYearSameMonthSalesEgp: 0,
        marketingSpendEgp: 15000,
        target: const RoiMonthKey(2026, 2),
      );
      expect(res.available, isFalse);
      expect(res.romiMultiple, isNull);
      expect(res.unavailableMessageAr, kRoiBaselineUnavailableAr);
    });

    test('does not cherry-pick a positive MoM lift over a seasonal baseline',
        () {
      final res = computeRoiLift(
        currentSalesEgp: 1200000,
        lastYearSameMonthSalesEgp: 1500000,
        marketingSpendEgp: 50000,
        target: const RoiMonthKey(2026, 2),
      );
      expect(res.incrementalLiftEgp, closeTo(-300000, 1e-6));
    });
  });

  group('MonthlyChainRoiSummary verdicts', () {
    MonthlyChainRoiSummary row({
      double spend = 50000,
      double current = 1200000,
      double lastYear = 800000,
      RoiLiftResult? lift,
    }) {
      return MonthlyChainRoiSummary(
        year: 2026,
        month: 2,
        chainName: 'Fathalla',
        marketingSpendEgp: spend,
        activitiesCount: 1,
        expenses: const [],
        currentMonthSalesEgp: current,
        previousMonthSalesEgp: 1000000,
        lastYearSameMonthSalesEgp: lastYear,
        currentMonthSellInEgp: 0,
        lift: lift,
      );
    }

    test('excellent when ROMI >= 3.5 and lift vs baseline >= 10%', () {
      // LY 800k, ratio 1 → baseline 800k, lift 400k / 50k = 8x, 50% lift.
      final s = row();
      expect(s.romiMultiple, closeTo(8, 1e-9));
      expect(s.verdictAr, 'عائد ممتاز ونمو قياسي');
      expect(s.verdictColor, M3Palette.success);
    });

    test('successful when ROMI >= 1.5 even if MoM is weak', () {
      // Current almost flat MoM (prev 1M) but well above LY baseline.
      final s = row(current: 1000000, lastYear: 600000, spend: 200000);
      // lift 400k / 200k = 2x, lift pct 66.7%, MoM 0.
      expect(s.romiMultiple, closeTo(2, 1e-9));
      expect(s.momGrowthPct, closeTo(0, 1e-9));
      expect(s.verdictAr, 'حملة ناجحة ونمو إيجابي');
    });

    test('weak when lift is negative, even if MoM is positive', () {
      final s = row(current: 1100000, lastYear: 1500000, spend: 50000);
      expect(s.incrementalLiftEgp, closeTo(-400000, 1e-6));
      expect(s.momLiftEgp, closeTo(100000, 1e-6));
      expect(s.verdictAr, 'عائد ضعيف / مراجعة التكلفة');
      expect(s.verdictColor, M3Palette.danger);
    });

    test('unavailable baseline shows the dash verdict, not 0.00x', () {
      final s = row(
        lastYear: 0,
        lift: RoiLiftResult.unavailable,
      );
      expect(s.romiMultiple, isNull);
      expect(s.verdictAr, 'لا يمكن حساب العائد');
    });

    test('no spend keeps the no-promo verdict', () {
      final s = row(spend: 0);
      expect(s.verdictAr, 'بدون إنفاق ترويجي');
      expect(s.romiMultiple, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/trade_marketing/domain/roi_lift.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';

MonthlyChainRoiSummary _summary({
  double spend = 100000,
  double current = 1200000,
  double previous = 1000000,
  double lastYear = 800000,
  RoiLiftResult? lift,
}) {
  return MonthlyChainRoiSummary(
    year: 2026,
    month: 2,
    chainName: 'fathalla',
    marketingSpendEgp: spend,
    activitiesCount: 1,
    expenses: const [],
    currentMonthSalesEgp: current,
    previousMonthSalesEgp: previous,
    lastYearSameMonthSalesEgp: lastYear,
    currentMonthSellInEgp: 0,
    lift: lift,
  );
}

void main() {
  group('averageHistoricalRomi', () {
    test('returns null when there are no campaigns with a computable baseline',
        () {
      expect(averageHistoricalRomi(const []), isNull);
      expect(
        averageHistoricalRomi([
          _summary(spend: 0, current: 500000, lastYear: 400000),
          _summary(
            spend: 100000,
            current: 300000,
            lastYear: 0,
            lift: RoiLiftResult.unavailable,
          ),
        ]),
        isNull,
      );
    });

    test('averages every computable campaign ROMI, including negatives', () {
      // LY 800k, ratio 1 → baseline 800k, lift 400k / 100k = 4.0x
      final a = _summary(spend: 100000, current: 1200000, lastYear: 800000);
      // lift 200k / 100k = 2.0x
      final b = _summary(spend: 100000, current: 1000000, lastYear: 800000);
      // lift -300k / 100k = -3.0x (included, not cherry-picked away)
      final c = _summary(spend: 100000, current: 500000, lastYear: 800000);
      final skipped = _summary(spend: 0, current: 1500000, lastYear: 800000);
      expect(a.romiMultiple, closeTo(4.0, 0.0001));
      expect(b.romiMultiple, closeTo(2.0, 0.0001));
      expect(c.romiMultiple, closeTo(-3.0, 0.0001));
      expect(averageHistoricalRomi([a, b, c, skipped]), closeTo(1.0, 0.0001));
    });
  });

  group('RoiSimulatorProjection', () {
    test('all projected figures are null when there is no historical ROMI', () {
      const p = RoiSimulatorProjection(
        historicalRomi: null,
        baselineSalesEgp: 800000,
        previousMonthSalesEgp: 1000000,
        lastYearSalesEgp: 800000,
        budgetEgp: 100000,
      );
      expect(p.hasHistoricalRomi, isFalse);
      expect(p.projectedSalesEgp, isNull);
      expect(p.projectedLiftEgp, isNull);
      expect(p.romiMultiple, isNull);
    });

    test('projects lift against the campaign-free baseline', () {
      const p = RoiSimulatorProjection(
        historicalRomi: 2.0,
        baselineSalesEgp: 800000,
        previousMonthSalesEgp: 1000000,
        lastYearSalesEgp: 700000,
        budgetEgp: 100000,
      );
      expect(p.projectedLiftEgp, closeTo(200000, 0.0001));
      expect(p.projectedSalesEgp, closeTo(1000000, 0.0001));
      expect(p.liftVsBaselinePct, closeTo(25, 0.0001));
      expect(p.momLiftEgp, closeTo(0, 0.0001));
      expect(p.yoyLiftEgp, closeTo(300000, 0.0001));
      expect(p.romiMultiple, closeTo(2.0, 0.0001));
    });

    test('keeps a negative historical ROMI instead of hiding it', () {
      const p = RoiSimulatorProjection(
        historicalRomi: -1.5,
        baselineSalesEgp: 800000,
        previousMonthSalesEgp: 1000000,
        lastYearSalesEgp: 800000,
        budgetEgp: 100000,
      );
      expect(p.hasHistoricalRomi, isTrue);
      expect(p.projectedLiftEgp, closeTo(-150000, 0.0001));
      expect(p.projectedSalesEgp, closeTo(650000, 0.0001));
      expect(p.romiMultiple, closeTo(-1.5, 0.0001));
    });

    test('growth percentages are null when a baseline is missing, not 0.0%',
        () {
      const p = RoiSimulatorProjection(
        historicalRomi: 2.0,
        baselineSalesEgp: null,
        previousMonthSalesEgp: 0,
        lastYearSalesEgp: 0,
        budgetEgp: 100000,
      );
      expect(p.projectedLiftEgp, closeTo(200000, 0.0001));
      expect(p.projectedSalesEgp, isNull);
      expect(p.momGrowthPct, isNull);
      expect(p.yoyGrowthPct, isNull);
    });
  });
}

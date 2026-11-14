import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';

MonthlyChainRoiSummary _summary({
  double spend = 100000,
  double current = 445000,
  double previous = 100000,
  double lastYear = 200000,
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
  );
}

void main() {
  group('averageHistoricalRomi', () {
    test('returns null when there are no usable campaigns, not 3.45', () {
      expect(averageHistoricalRomi(const []), isNull);
      expect(
        averageHistoricalRomi([
          _summary(spend: 0, current: 500000, previous: 100000),
          // Negative MoM and YoY lifts → romiMultiple is not > 0.
          _summary(
            spend: 100000,
            current: 50000,
            previous: 200000,
            lastYear: 80000,
          ),
        ]),
        isNull,
      );
    });

    test('averages only rows with spend > 0 and a positive ROMI', () {
      // MoM lift 345,000 / 100,000 = 3.45x
      final a = _summary(spend: 100000, current: 445000, previous: 100000);
      // MoM lift 200,000 / 100,000 = 2.0x
      final b = _summary(spend: 100000, current: 300000, previous: 100000);
      final skipped = _summary(spend: 0, current: 500000, previous: 100000);
      expect(a.romiMultiple, closeTo(3.45, 0.0001));
      expect(b.romiMultiple, closeTo(2.0, 0.0001));
      expect(averageHistoricalRomi([a, b, skipped]), closeTo(2.725, 0.0001));
    });
  });

  group('RoiSimulatorProjection', () {
    test('all projected figures are null when there is no historical ROMI', () {
      const p = RoiSimulatorProjection(
        historicalRomi: null,
        previousMonthSalesEgp: 0,
        lastYearSalesEgp: 0,
        budgetEgp: 100000,
      );
      expect(p.hasHistoricalRomi, isFalse);
      expect(p.projectedSalesEgp, isNull);
      expect(p.momLiftEgp, isNull);
      expect(p.momGrowthPct, isNull);
      expect(p.yoyLiftEgp, isNull);
      expect(p.yoyGrowthPct, isNull);
      expect(p.romiMultiple, isNull);
    });

    test('keeps budget × historical ROMI when campaigns exist', () {
      const p = RoiSimulatorProjection(
        historicalRomi: 3.45,
        previousMonthSalesEgp: 1000000,
        lastYearSalesEgp: 800000,
        budgetEgp: 100000,
      );
      expect(p.momLiftEgp, closeTo(345000, 0.0001));
      expect(p.projectedSalesEgp, closeTo(1345000, 0.0001));
      expect(p.momGrowthPct, closeTo(34.5, 0.0001));
      expect(p.yoyLiftEgp, closeTo(545000, 0.0001));
      expect(p.romiMultiple, closeTo(3.45, 0.0001));
    });

    test('growth percentages are null when a baseline is missing, not 0.0%',
        () {
      const p = RoiSimulatorProjection(
        historicalRomi: 3.45,
        previousMonthSalesEgp: 0,
        lastYearSalesEgp: 0,
        budgetEgp: 100000,
      );
      expect(p.momLiftEgp, closeTo(345000, 0.0001));
      expect(p.projectedSalesEgp, closeTo(345000, 0.0001));
      expect(p.momGrowthPct, isNull);
      expect(p.yoyGrowthPct, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/domain/competitor_month_options.dart';

void main() {
  test('10 months → كل الشهور (يناير - أكتوبر) — 2026 and Jan–Oct chips', () {
    final months = List<int>.generate(10, (i) => i + 1);
    expect(
      CompetitorMonthOptions.allMonthsLabel(months, year: 2026),
      'كل الشهور (يناير - أكتوبر) — 2026',
    );
    final opts = CompetitorMonthOptions.build(months, year: 2026);
    expect(opts, hasLength(11));
    expect(opts.first.month, 0);
    expect(opts.first.labelAr, 'كل الشهور (يناير - أكتوبر) — 2026');
    expect(opts.last.month, 10);
    expect(opts.last.labelAr, 'أكتوبر (10)');
    expect(opts.map((o) => o.month).toList(), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test('monthsFromSeries keeps year filter and sorts', () {
    final points = [
      for (final m in [3, 1, 10, 2])
        SkuMonthlyPricePointModel(
          monthKey: '2026-${m.toString().padLeft(2, '0')}',
          year: 2026,
          monthNum: m,
          monthNameAr: ApiClient.formatArabicMonthOnly(m),
          monthLabelAr: '${ApiClient.formatArabicMonthOnly(m)} 2026',
          unitPrice: 100,
          unitsSold: 1,
          netRevenue: 100,
          priceChangeEgp: 0,
          priceChangePct: 0,
          trendDirection: 'baseline',
        ),
      const SkuMonthlyPricePointModel(
        monthKey: '2025-12',
        year: 2025,
        monthNum: 12,
        monthNameAr: 'ديسمبر',
        monthLabelAr: 'ديسمبر 2025',
        unitPrice: 90,
        unitsSold: 1,
        netRevenue: 90,
        priceChangeEgp: 0,
        priceChangePct: 0,
        trendDirection: 'baseline',
      ),
    ];
    expect(CompetitorMonthOptions.monthsFromSeries(points, year: 2026), [1, 2, 3, 10]);
  });

  test('live covers subset → no leftover seed months', () {
    final seed = <String, ({double price, int units})>{
      '2026-01': (price: 100, units: 10),
      '2026-02': (price: 105, units: 11),
      '2026-03': (price: 108, units: 11),
      '2026-04': (price: 110, units: 12),
    };
    final live = <String, ({double price, int units})>{
      for (var m = 5; m <= 10; m++)
        '2026-${m.toString().padLeft(2, '0')}': (price: 120.0 + m, units: 20),
    };
    final merged = ApiClient.mergeMonthlyData(seed, live);
    final traj = ApiClient.buildMonthlyPriceTrajectory(merged, filterYear: 2026);
    expect(traj.map((p) => p.monthNum).toList(), [5, 6, 7, 8, 9, 10]);
    expect(merged.containsKey('2026-01'), isFalse);
    expect(merged.containsKey('2026-04'), isFalse);
  });

  test('empty API → no seed months in picker', () {
    final resolved = CompetitorMonthOptions.resolveDataMonths(apiMonths: const []);
    expect(resolved, isEmpty);
    expect(CompetitorMonthOptions.build(resolved, year: 2026), isEmpty);
  });

  test('API-vs-series mismatch: picker uses full API list only', () {
    final opts = CompetitorMonthOptions.build(
      CompetitorMonthOptions.resolveDataMonths(
        apiMonths: List<int>.generate(10, (i) => i + 1),
      ),
      year: 2026,
    );
    expect(opts.first.labelAr, 'كل الشهور (يناير - أكتوبر) — 2026');
    expect(opts.where((o) => o.month > 0), hasLength(10));
  });
}

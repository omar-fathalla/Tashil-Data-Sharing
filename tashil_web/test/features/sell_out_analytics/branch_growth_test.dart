import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/branch_growth.dart';

StoreBenchmarkItem _item(String id, String name, double rev, {int units = 0, String region = ''}) =>
    StoreBenchmarkItem(
      storeId: id,
      storeName: name,
      retailerChain: 'fathalla',
      region: region,
      tier: 'Tier A',
      totalRevenue: rev,
      totalUnits: units,
      velocityUnitsPerDay: 0,
      rank: 1,
    );

BranchGrowthBase _base(String id, String name, double fullRevenue) => BranchGrowthBase(
      storeId: id,
      storeName: name,
      chain: 'fathalla',
      region: '—',
      units: 0,
      revenue: fullRevenue,
    );

void main() {
  group('buildBranchGrowthRows: one month window for sales, diff and %', () {
    // Rahab: 2026 uploaded Jan–Oct (full 18,604,715) but 2025 only Jan–Apr.
    // Matched Jan–Apr: 2025 = 5,512,604 and 2026 = 6,332,304.
    const rahabFull = 18604715.0;
    const rahabCur = 6332304.0;
    const rahabPrev = 5512604.0;

    test('diff == 2026 - 2025 of the displayed columns and % uses the same pair', () {
      final rows = buildBranchGrowthRows(
        branches: [_base('rahab', 'مدينة الرحاب', rahabFull)],
        prevByStore: {'rahab': _item('rahab', 'مدينة الرحاب', rahabPrev)},
        currentLikeForLikeByStore: {'rahab': _item('rahab', 'مدينة الرحاب', rahabCur)},
      );
      final r = rows.single;
      expect(r.currentRevenue, rahabCur, reason: 'column shows the matched window, not 18.6M');
      expect(r.prevRevenue, rahabPrev);
      expect(r.varianceEgp, closeTo(819700.0, 0.5));
      expect(r.varianceEgp, r.currentRevenue - r.prevRevenue);
      expect(r.yoyGrowthPct, closeTo(14.87, 0.01));
      expect(r.yoyGrowthPct, closeTo(r.varianceEgp / r.prevRevenue * 100, 1e-9));
      expect(r.fullPeriodRevenue, rahabFull, reason: 'full period is kept for the monthly average');
      expect(r.status, 'growing');
      expect(r.hasPrevYear, isTrue);
    });

    test('branch without 2025 data stays new: no %, no 2025 base', () {
      final rows = buildBranchGrowthRows(
        branches: [_base('dm', 'دمياط الجديدة', 5429124)],
        prevByStore: const {},
        currentLikeForLikeByStore: {'dm': _item('dm', 'دمياط الجديدة', 1730000)},
      );
      final r = rows.single;
      expect(r.hasPrevYear, isFalse);
      expect(r.yoyGrowthPct, isNull);
      expect(r.status, 'new_branch');
      expect(r.varianceEgp, r.currentRevenue - 0);
    });

    test('declining branch and zero-sales branch without 2025', () {
      final rows = buildBranchGrowthRows(
        branches: [_base('a', 'A', 900), _base('b', 'B', 0)],
        prevByStore: {'a': _item('a', 'A', 1000)},
        currentLikeForLikeByStore: {'a': _item('a', 'A', 800)},
      );
      final a = rows.firstWhere((r) => r.storeId == 'a');
      expect(a.status, 'declining');
      expect(a.varianceEgp, -200);
      expect(a.yoyGrowthPct, closeTo(-20.0, 1e-9));
      final b = rows.firstWhere((r) => r.storeId == 'b');
      expect(b.status, 'declining');
      expect(b.currentRevenue, 0);
    });

    test('matches by store name when ids differ between years', () {
      final rows = buildBranchGrowthRows(
        branches: [_base('id26', 'سموحة', 3000)],
        prevByStore: {'id25': _item('id25', 'سموحة', 1000, units: 7, region: 'شرق الإسكندرية')},
        currentLikeForLikeByStore: {'id26': _item('id26', 'سموحة', 1500)},
      );
      final r = rows.single;
      expect(r.prevRevenue, 1000);
      expect(r.prevUnits, 7);
      expect(r.region, 'شرق الإسكندرية', reason: 'region falls back to last year');
      expect(r.varianceEgp, 500);
    });

    test('ranks by the displayed (matched) revenue, full period breaks ties', () {
      final rows = buildBranchGrowthRows(
        branches: [
          _base('big_full', 'X', 10000),
          _base('big_matched', 'Y', 4000),
          _base('tie_low', 'Z', 100),
          _base('tie_high', 'W', 900),
        ],
        prevByStore: const {},
        currentLikeForLikeByStore: {
          'big_full': _item('big_full', 'X', 100),
          'big_matched': _item('big_matched', 'Y', 3000),
          'tie_low': _item('tie_low', 'Z', 50),
          'tie_high': _item('tie_high', 'W', 50),
        },
      );
      expect(rows.map((r) => r.storeId).toList(), ['big_matched', 'big_full', 'tie_high', 'tie_low']);
    });

    test('when a month is picked the same matrix feeds both sides (no trimming)', () {
      final cur = {'s': _item('s', 'S', 500)};
      final rows = buildBranchGrowthRows(
        branches: [_base('s', 'S', 500)],
        prevByStore: {'s': _item('s', 'S', 400)},
        currentLikeForLikeByStore: cur,
      );
      expect(rows.single.currentRevenue, 500);
      expect(rows.single.varianceEgp, 100);
      expect(rows.single.yoyGrowthPct, closeTo(25.0, 1e-9));
    });
  });

  group('matchedMonthsLabelAr', () {
    test('contiguous range, single month, gaps, junk', () {
      expect(matchedMonthsLabelAr([1, 2, 3, 4]), 'يناير–أبريل');
      expect(matchedMonthsLabelAr([4, 3, 2, 1]), 'يناير–أبريل');
      expect(matchedMonthsLabelAr([3]), 'مارس');
      expect(matchedMonthsLabelAr([1, 3, 5]), 'يناير، مارس، مايو');
      expect(matchedMonthsLabelAr([2, 2, 3]), 'فبراير–مارس');
      expect(matchedMonthsLabelAr(const []), '');
      expect(matchedMonthsLabelAr([0, 13]), '');
    });
  });
}

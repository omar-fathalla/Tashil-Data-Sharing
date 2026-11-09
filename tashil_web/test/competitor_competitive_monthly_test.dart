import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/available_months.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/domain/competitor_month_options.dart';

Map<String, dynamic> _monthPt(int month, {double price = 100, int units = 10}) => {
      'month_key': '2026-${month.toString().padLeft(2, '0')}',
      'month': month,
      'unit_price': price,
      'units': units,
      'net_revenue': price * units,
    };

Map<String, dynamic> _aggBody({
  required List<int> months,
  required String barcode,
  List<int>? seriesMonths,
  String skuName = 'فيبا 3 كجم',
  String category = 'صابون سائل اطباق',
  bool isOwnBrand = true,
}) {
  final series = seriesMonths ?? months;
  return {
    'year': 2026,
    'months': months,
    'source': 'memory',
    'own_skus': isOwnBrand
        ? [
            {'barcode': barcode, 'sku_name': skuName, 'category': category},
          ]
        : const [],
    'items': [
      {
        'barcode': barcode,
        'sku_name': skuName,
        'category': category,
        'is_own_brand': isOwnBrand,
        'months': [for (final m in series) _monthPt(m, price: 100.0 + m)],
      },
    ],
  };
}

void main() {
  tearDown(() {
    AvailableMonths.clearForTest();
  });

  test('Compare uses single competitive-monthly request (not raw records paging)', () async {
    const own = '6223000239438';
    final months = List<int>.generate(10, (i) => i + 1);
    var competitiveCalls = 0;
    var recordsCalls = 0;

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final groups = await api.getCompetitiveComparisonGroups(
        chain: 'fathalla',
        year: 2026,
        month: 0,
      );
      expect(competitiveCalls, 1);
      expect(recordsCalls, 0);
      expect(api.lastCompetitiveMonths, months);
      final g = groups.firstWhere((x) => x.ownBarcode == own);
      expect(g.monthlyPrices.map((p) => p.monthNum).toList(), months);
      expect(
        CompetitorMonthOptions.allMonthsLabel(api.lastCompetitiveMonths, year: 2026),
        'كل الشهور (يناير - أكتوبر) — 2026',
      );
    }, () => MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/competitive-monthly')) {
        competitiveCalls++;
        expect(req.url.queryParameters['supplier'], 'all_market');
        expect(req.url.queryParameters['year'], '2026');
        expect(req.url.queryParameters.containsKey('offset'), isFalse);
        return http.Response(
          jsonEncode(_aggBody(months: months, barcode: own)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.contains('/api/v1/analytics/records')) {
        recordsCalls++;
        return http.Response('{"error":"Compare must not page records"}', 500);
      }
      if (req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      return http.Response('{}', 200);
    }));
  });

  test('fixture months Jan–Oct from competitive-monthly (no Jan–Apr seed leftover)', () async {
    const own = '6223000239438';
    const pril = '6221143099674';
    final months = List<int>.generate(10, (i) => i + 1);

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', year: 2026, month: 0);
      final g = groups.firstWhere((x) => x.ownBarcode == own);
      expect(g.monthlyPrices.map((p) => p.monthNum).toList(), months);
      expect(g.monthlyPrices.any((p) => p.monthNum <= 4), isTrue);
      expect(g.monthlyPrices.any((p) => p.monthNum == 10), isTrue);
      // Pril absent from aggregate → no Jan–Apr seed series.
      expect(g.competitors.any((c) => c.barcode == pril), isFalse);
    }, () => MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/competitive-monthly')) {
        return http.Response(
          jsonEncode(_aggBody(months: months, barcode: own)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      return http.Response('{}', 200);
    }));
  });

  test('live May–Oct only → no Jan–Apr seed months on series', () async {
    const own = '6223000239438';
    final months = [5, 6, 7, 8, 9, 10];

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', year: 2026, month: 0);
      final g = groups.firstWhere((x) => x.ownBarcode == own);
      expect(g.monthlyPrices.map((p) => p.monthNum).toList(), months);
      expect(g.monthlyPrices.any((p) => p.monthNum <= 4), isFalse);
    }, () => MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/competitive-monthly')) {
        return http.Response(
          jsonEncode(_aggBody(months: months, barcode: own)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      return http.Response('{}', 200);
    }));
  });

  test('HTTP failure + !allowDemoSeedData → empty series, no seed Jan–Apr', () async {
    await http.runWithClient(() async {
      final api = ApiClient(
        tenantId: 'tenant-adeco',
        allowMockFallback: true,
        allowDemoSeedData: false,
      );
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', year: 2026, month: 0);
      for (final g in groups) {
        expect(g.monthlyPrices, isEmpty);
        for (final c in g.competitors) {
          expect(c.monthlyPrices, isEmpty);
        }
      }
      expect(api.lastCompetitiveMonths, isEmpty);
    }, () => MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/competitive-monthly')) {
        return http.Response('{"error":"boom"}', 500);
      }
      if (req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      return http.Response('{}', 200);
    }));
  });

  test('timeout + !allowDemoSeedData → empty series, no seed Jan–Apr', () async {
    await http.runWithClient(() async {
      final api = ApiClient(
        tenantId: 'tenant-adeco',
        allowMockFallback: true,
        allowDemoSeedData: false,
      );
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', year: 2026, month: 0);
      expect(groups.every((g) => g.monthlyPrices.isEmpty), isTrue);
    }, () => MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/competitive-monthly')) {
        throw TimeoutException('competitive-monthly timed out');
      }
      if (req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      return http.Response('{}', 200);
    }));
  });

  test('AvailableMonths.mergeMonths unions API Jan–Apr with aggregate Jan–Oct', () {
    AvailableMonths.setForTest(const MonthOptions(year: 2026, months: [1, 2, 3, 4]));
    AvailableMonths.mergeMonths(2026, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(AvailableMonths.currentFor(2026).months, List<int>.generate(10, (i) => i + 1));
  });
}

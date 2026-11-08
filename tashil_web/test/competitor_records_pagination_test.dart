import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/domain/competitor_month_options.dart';

Map<String, dynamic> _rec(int i, {String? date, String barcode = '6223000239438'}) {
  final d = date ?? '2026-01-15';
  return {
    'record_id': 'r$i',
    'retailer_chain': 'fathalla',
    'store_id': 's1',
    'store_name': 'فرع',
    'barcode': barcode,
    'sku_name': 'فيبا 3 كجم',
    'category': 'صابون سائل اطباق',
    'quantity_sold': 1,
    'net_revenue': 100.0,
    'unit_price': 100.0,
    'transaction_date': d,
  };
}

void main() {
  test('sellOutRecordsHasMorePage walks past 5000 across 500-sized pages', () {
    const pageSize = ApiClient.sellOutRecordsPageSize;
    const total = 5500;
    var fetched = 0;
    var pages = 0;
    while (true) {
      final remaining = total - fetched;
      final pageLen = remaining >= pageSize ? pageSize : remaining;
      if (pageLen <= 0) break;
      fetched += pageLen;
      pages++;
      if (!ApiClient.sellOutRecordsHasMorePage(
        fetchedSoFar: fetched,
        pageLength: pageLen,
        pageSize: pageSize,
        totalCount: total,
      )) {
        break;
      }
    }
    expect(pages, 11);
    expect(fetched, 5500);
  });

  test('getRecordsAllPages fetches every page when total_count > 5000', () async {
    const total = 5200;
    final offsets = <int>[];
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final all = await api.getRecordsAllPages(
        chain: 'fathalla',
        supplier: 'all_market',
        startDate: '2026-01-01',
        endDate: '2026-12-31',
      );
      expect(all, hasLength(total));
      expect(api.lastSellOutPaginationWarning, isNull);
      expect(offsets.first, 0);
      expect(offsets.last, 5000);
      expect(offsets, hasLength(11));
      expect(all.last.transactionDate.startsWith('2026-10'), isTrue);
    }, () => MockClient((req) async {
      expect(req.url.path, contains('/api/v1/analytics/records'));
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(req.url.queryParameters['limit'] ?? '50');
      expect(limit, lessThanOrEqualTo(ApiClient.sellOutRecordsPageSize));
      offsets.add(offset);
      final page = <Map<String, dynamic>>[];
      for (var i = 0; i < limit && offset + i < total; i++) {
        final idx = offset + i;
        final date = idx >= 5000 ? '2026-10-15' : '2026-01-15';
        page.add(_rec(idx, date: date));
      }
      return http.Response(
        jsonEncode({'records': page, 'total_count': total}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));
  });

  test('safety cap → warning + SellOutRecordsTruncatedException (never silent)', () async {
    const total = 5000;
    const cap = 1000; // small cap for the test
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      try {
        await api.getRecordsAllPages(
          chain: 'fathalla',
          startDate: '2026-01-01',
          endDate: '2026-12-31',
          maxRows: cap,
        );
        fail('expected SellOutRecordsTruncatedException');
      } on SellOutRecordsTruncatedException catch (e) {
        expect(e.partial, hasLength(cap));
        expect(e.totalCount, total);
        expect(e.maxRows, cap);
        expect(api.lastSellOutPaginationWarning, isNotNull);
        expect(api.lastSellOutPaginationWarning, contains('$cap'));
        expect(api.lastSellOutPaginationWarning, contains('incomplete'));
      }
    }, () => MockClient((req) async {
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(req.url.queryParameters['limit'] ?? '50');
      final page = <Map<String, dynamic>>[];
      for (var i = 0; i < limit && offset + i < total; i++) {
        page.add(_rec(offset + i));
      }
      return http.Response(
        jsonEncode({'records': page, 'total_count': total}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));
  });

  test('API months win over shorter seed series (no partial Jan–Apr label)', () {
    final api = List<int>.generate(10, (i) => i + 1);
    final resolved = CompetitorMonthOptions.resolveDataMonths(apiMonths: api);
    expect(resolved, api);
    expect(
      CompetitorMonthOptions.allMonthsLabel(resolved, year: 2026),
      'كل الشهور (يناير - أكتوبر) — 2026',
    );
  });

  test('empty API → no seed months', () {
    expect(
      CompetitorMonthOptions.resolveDataMonths(apiMonths: const []),
      isEmpty,
    );
    expect(CompetitorMonthOptions.build(const [], year: 2026), isEmpty);
  });

  test('live set with own May–Oct only → seeded competitors without live have no months', () async {
    const own = '6223000239438';
    // Pril competitor barcode from seeds — intentionally absent from live rows.
    const pril = '6221143099674';
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', year: 2026, month: 0);
      final ownGroup = groups.firstWhere((g) => g.ownBarcode == own);
      expect(ownGroup.monthlyPrices.map((p) => p.monthNum).toList(), [5, 6, 7, 8, 9, 10]);
      expect(ownGroup.monthlyPrices.any((p) => p.monthNum <= 4), isFalse);
      // Seeded Pril must not appear with Jan–Apr seed prices when it has no live rows.
      expect(ownGroup.competitors.any((c) => c.barcode == pril), isFalse);
    }, () => MockClient((req) async {
      if (!req.url.path.contains('/api/v1/analytics/records')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      final records = [
        for (var m = 5; m <= 10; m++)
          _rec(m, date: '2026-${m.toString().padLeft(2, '0')}-15', barcode: own),
      ];
      return http.Response(
        jsonEncode({'records': records, 'total_count': records.length}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));
  });

  test('truncation → partial live + warning, never seed Jan–Apr', () async {
    const own = '6223000239438';
    const total = 1500;
    const cap = 500;
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      api.debugSellOutMaxRows = cap;
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', year: 2026, month: 0);
      expect(api.lastSellOutPaginationWarning, isNotNull);
      expect(groups, isNotEmpty);
      final g = groups.firstWhere((x) => x.ownBarcode == own);
      // Partial live is May-only — seed Jan–Apr must never appear after truncation.
      expect(g.monthlyPrices.map((p) => p.monthNum).toSet(), {5});
      expect(g.monthlyPrices.any((p) => p.monthNum <= 4), isFalse);
    }, () => MockClient((req) async {
      if (!req.url.path.contains('/api/v1/analytics/records')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(req.url.queryParameters['limit'] ?? '50');
      final page = <Map<String, dynamic>>[];
      for (var i = 0; i < limit && offset + i < total; i++) {
        page.add(_rec(offset + i, date: '2026-05-15', barcode: own));
      }
      return http.Response(
        jsonEncode({'records': page, 'total_count': total}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));
  });
}

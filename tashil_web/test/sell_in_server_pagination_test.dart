// Sell-In records use server-side pagination: opening the page fetches one
// 20-row page (never the whole filtered set), each page click is one request,
// and a response that lands after dispose or a filter change is dropped.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_in_explorer_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

const _bigTotal = 25000;

Map<String, Object?> _record(int i, {String prefix = 'صف'}) => {
      'record_id': 'r$i',
      'tenant_id': 'tenant',
      'retailer_chain': 'fathalla',
      'year': 2026,
      'month_num': 10,
      'month_ar': 'أكتوبر',
      'item_code': 'C$i',
      'item_name': '$prefix $i',
      'units_per_carton': 12,
      'net_qty_cases': 1.0,
      'net_value_egp': 100.0,
      'source_filename': 'in26.xlsx',
    };

http.Response _json(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Honors limit/offset like the backend; [onRecords] can delay or reshape a page.
class _Backend {
  _Backend({this.onRecords});

  static const total = _bigTotal;
  final Future<Map<String, Object?>?> Function(Uri url, int n)? onRecords;
  final List<Uri> recordRequests = [];

  Map<String, Object?> page(Uri url, {String prefix = 'صف'}) {
    final limit = int.parse(url.queryParameters['limit'] ?? '250');
    final offset = int.parse(url.queryParameters['offset'] ?? '0');
    final end = (offset + limit).clamp(0, total);
    return {
      'records': [for (var i = offset; i < end; i++) _record(i, prefix: prefix)],
      'total_count': total,
      'limit': limit,
      'offset': offset,
      'total_value_egp': 2500000.0,
      'total_net_excl_vat_egp': 2500000.0,
      'total_cases': 25000.0,
      'total_weight_tons': 12.5,
      'total_expected_egp': 0.0,
    };
  }

  MockClient get client => MockClient((req) async {
        if (req.url.path.endsWith('/api/v1/analytics/sell-in-records')) {
          recordRequests.add(req.url);
          final custom = await onRecords?.call(req.url, recordRequests.length);
          return _json(custom ?? page(req.url));
        }
        if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
          return _json({'monthly_reconciliation': <Object>[], 'inventory_and_po_items': <Object>[]});
        }
        if (req.url.path.endsWith('/api/v1/ingest/archive')) {
          return _json({'total_count': 0, 'files': <Object>[]});
        }
        return http.Response('not found', 404);
      });
}

Widget _app(ApiClient api) => MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SellInExplorerScreen(apiClient: api)),
      ),
    );

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opening Sell-In fetches exactly one 20-row page, not all 25k rows', (tester) async {
    _bigView(tester);
    final backend = _Backend();
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(ApiClient(tenantId: 'tenant-srv-page-open')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(backend.recordRequests, hasLength(1), reason: '${backend.recordRequests}');
      final q = backend.recordRequests.single.queryParameters;
      expect(q['limit'], '20');
      expect(q['offset'], '0');

      expect(find.textContaining('عرض 1–20 من $_bigTotal'), findsOneWidget);
      expect(find.textContaining('صفحة 1 من 1250'), findsOneWidget);
      expect(find.text('صف 0'), findsOneWidget);
      expect(find.text('صف 19'), findsOneWidget);
      expect(find.text('صف 20'), findsNothing);
      // KPI cards read the server totals for the whole filter.
      expect(find.textContaining('25,000 كرتونة'), findsWidgets);
    }, () => backend.client);
  });

  testWidgets('each page click is one request at that page offset', (tester) async {
    _bigView(tester);
    final backend = _Backend();
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(ApiClient(tenantId: 'tenant-srv-page-nav')));
      await tester.pumpAndSettle();

      final next = find.byKey(const ValueKey('sellin_records_next_btn'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(backend.recordRequests, hasLength(2));
      expect(backend.recordRequests.last.queryParameters['offset'], '20');
      expect(find.textContaining('عرض 21–40 من $_bigTotal'), findsOneWidget);
      expect(find.text('صف 20'), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_record_row_20')), findsOneWidget);

      final last = find.byKey(const ValueKey('sellin_records_last_btn'));
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(backend.recordRequests, hasLength(3));
      expect(backend.recordRequests.last.queryParameters['offset'], '${_bigTotal - 20}');
      expect(find.textContaining('صفحة 1250 من 1250'), findsOneWidget);
      expect(find.text('صف ${_bigTotal - 1}'), findsOneWidget);
    }, () => backend.client);
  });

  testWidgets('a page response arriving after dispose is dropped; no further requests', (tester) async {
    _bigView(tester);
    final gate = Completer<void>();
    final backend = _Backend(onRecords: (url, n) async {
      await gate.future;
      return null;
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(ApiClient(tenantId: 'tenant-srv-page-dispose')));
      await tester.pump();
      expect(backend.recordRequests, hasLength(1));
      expect(find.byKey(const ValueKey('sell_in_loading_bar')), findsOneWidget);

      // Navigate away while the first page is still in flight.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Sell-Out'))));
      gate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(backend.recordRequests, hasLength(1), reason: 'no orphan paging after dispose');
    }, () => backend.client);
  });

  testWidgets('a stale response for an older filter never replaces the current one', (tester) async {
    _bigView(tester);
    final slowFirst = Completer<void>();
    late _Backend backend;
    backend = _Backend(onRecords: (url, n) async {
      if (n == 1) {
        await slowFirst.future;
        return backend.page(url, prefix: 'قديم');
      }
      return backend.page(url, prefix: 'جديد');
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_app(ApiClient(tenantId: 'tenant-srv-page-stale')));
      await tester.pump();

      await tester.enterText(find.byKey(const ValueKey('sellin_records_search_field')), 'x');
      await tester.pumpAndSettle();
      expect(find.text('جديد 0'), findsOneWidget);

      slowFirst.complete();
      await tester.pumpAndSettle();
      expect(find.text('جديد 0'), findsOneWidget);
      expect(find.text('قديم 0'), findsNothing);
      expect(backend.recordRequests, hasLength(2));
      expect(backend.recordRequests.last.queryParameters['q'], 'x');
    }, () => backend.client);
  });

  group('SellInExplorerRepository.loadAllPages (exports) is bounded', () {
    Future<(List<SellInRecordItem>, int)> run(
      Map<String, Object?> Function(int limit, int offset) respond, {
      int pageSize = 100,
      int maxPages = SellInExplorerRepository.maxExportPages,
      bool Function()? isCancelled,
    }) async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return _json(respond(
          int.parse(req.url.queryParameters['limit']!),
          int.parse(req.url.queryParameters['offset']!),
        ));
      });
      final rows = await http.runWithClient(() async {
        final repo = SellInExplorerRepository(ApiClient(tenantId: 'tenant-srv-export', allowMockFallback: false));
        final res = await repo.loadAllPages(const SellInExplorerQuery(year: 2026),
            pageSize: pageSize, maxPages: maxPages, isCancelled: isCancelled);
        return res.valueOrNull!;
      }, () => client);
      return (rows, calls);
    }

    Map<String, Object?> honest(int total, int limit, int offset) => {
          'records': [for (var i = offset; i < (offset + limit).clamp(0, total); i++) _record(i)],
          'total_count': total,
        };

    test('walks to total_count and stops on the short last page', () async {
      final (rows, calls) = await run((l, o) => honest(250, l, o));
      expect(rows, hasLength(250));
      expect(calls, 3);
    });

    test('stops when the API ignores offset (same full page every time)', () async {
      final (rows, calls) = await run((l, o) => honest(1000000, l, 0));
      expect(rows, hasLength(100));
      expect(calls, 2);
    });

    test('stops at maxPages when full pages keep coming', () async {
      final (rows, calls) = await run((l, o) => honest(1 << 30, l, o), maxPages: 5);
      expect(rows, hasLength(500));
      expect(calls, 5);
    });

    test('stops at offset >= total even if the API over-fills pages', () async {
      final (rows, calls) = await run((l, o) => {
            'records': [for (var i = o; i < o + l; i++) _record(i)],
            'total_count': 150,
          });
      expect(calls, 2);
      expect(rows, hasLength(200));
    });

    test('stops once cancelled (page disposed / filter changed)', () async {
      var n = 0;
      final (rows, calls) = await run((l, o) => honest(100000, l, o), isCancelled: () => ++n > 3);
      // Checked before and after each request: the 2nd page arrives cancelled and is not kept.
      expect(calls, 2);
      expect(rows, hasLength(100));
    });
  });
}

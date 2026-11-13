// v130: the Files tables never hide row content under the horizontal
// scrollbar, and at 1280 (1030dp content) they fit without scrolling.
// Live-sized made-up fixture values (large totals, last-import date), real
// Cairo font.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

Map<String, dynamic> _file(String type, int i) => {
      'id': '${type}_$i',
      'file_type': type,
      'file_name': i == 0 ? 'out26.xlsx' : 'in26_${i}_long_name.xlsx',
      'retail_chain': 'fathalla',
      'target_year': '2026',
      'target_month': '01-10',
      'rows_ingested': 81294,
      'total_units': 1532854,
      'total_cases': 123456.0,
      'total_weight_tons': 1234.5,
      'total_revenue': 127133355.0,
      'file_size_bytes': 6633000,
      'uploaded_at': '2026-11-08T13:58:00Z',
      'last_ingested_at': '2026-11-13T09:12:00Z',
    };

MockClient _client(String type) => MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/ingest/archive')) {
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'tenant_id': 'tenant-adeco',
              'total_count': 2,
              'files': [_file(type, 0), _file(type, 1)],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response.bytes(
          utf8.encode(jsonEncode({'records': [], 'total_count': 0})), 200,
          headers: {'content-type': 'application/json'});
    });

Future<void> _pumpFiles(
    WidgetTester tester, Widget page, String type, double width) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: page)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(RegExp('^الملفات المرفوعة')).first);
    await tester.pumpAndSettle();
  }, () => _client(type));
}

ScrollPosition _hScroll(WidgetTester tester, Finder table) {
  final scrollable = find.ancestor(
      of: table,
      matching: find.byWidgetPredicate((w) =>
          w is Scrollable &&
          w.axisDirection != AxisDirection.down &&
          w.axisDirection != AxisDirection.up));
  return tester.state<ScrollableState>(scrollable.first).position;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final (name, type, key, build) in [
    (
      'Sell-Out',
      'sell_out',
      'uploaded_files_table',
      () =>
          SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco'))
    ),
    (
      'Sell-In',
      'sell_in',
      'sellin_uploaded_files_table',
      () => SellInExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco'))
    ),
  ]) {
    // 1280dp window minus the desktop sidebar.
    testWidgets('$name files table fits 1030dp without a scrollbar',
        (tester) async {
      await _pumpFiles(tester, build(), type, 1030);
      final table = find.byKey(ValueKey(key));
      expect(table, findsOneWidget);
      expect(find.textContaining('127,133,355'), findsWidgets);
      final pos = _hScroll(tester, table);
      expect(pos.maxScrollExtent, lessThan(0.01),
          reason: 'table overflows by ${pos.maxScrollExtent}dp');
      // No scrollbar track painted over a table that fits.
      final sb = tester.widget<Scrollbar>(
          find.ancestor(of: table, matching: find.byType(Scrollbar)).first);
      expect(sb.trackVisibility, isNot(true));
      expect(sb.thumbVisibility, isNot(true));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$name files table rows stay clear of the scrollbar when it '
        'must scroll (narrow)', (tester) async {
      await _pumpFiles(tester, build(), type, 700);
      final table = find.byKey(ValueKey(key));
      final pos = _hScroll(tester, table);
      expect(pos.maxScrollExtent, greaterThan(2.0));
      final scrollbar =
          find.ancestor(of: table, matching: find.byType(Scrollbar));
      final bar = tester.getRect(scrollbar.first);
      final t = tester.getRect(table);
      final thickness = tester.widget<Scrollbar>(scrollbar.first).thickness!;
      expect(t.bottom, lessThanOrEqualTo(bar.bottom - thickness),
          reason: 'last row ends at ${t.bottom}, scrollbar starts at '
              '${bar.bottom - thickness}');
    });
  }

  testWidgets(
      'TableScrollContainer: flex shares never force an overflow '
      'when the natural columns fit', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TableScrollContainer(
          showControls: false,
          // A tiny share for the wide column: content must win, the others
          // give up their slack instead of overflowing the table.
          columnFlex: const [3, 3, 0.2],
          child: DataTable(
            key: const ValueKey('t'),
            columns: const [
              DataColumn(label: Text('a')),
              DataColumn(label: Text('b')),
              DataColumn(label: Text('c')),
            ],
            rows: const [
              DataRow(cells: [
                DataCell(Text('1')),
                DataCell(Text('2')),
                DataCell(SizedBox(width: 200, child: Text('wide'))),
              ]),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final pos = _hScroll(tester, find.byKey(const ValueKey('t')));
    expect(pos.maxScrollExtent, lessThanOrEqualTo(2.0));
    // Still fills the width.
    expect(tester.getSize(find.byKey(const ValueKey('t'))).width,
        greaterThanOrEqualTo(600 - 1));
  });
}

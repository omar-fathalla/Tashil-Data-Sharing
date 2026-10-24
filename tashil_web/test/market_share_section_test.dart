import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';

/// Test fixture shaped like GET /api/v1/analytics/cpfr (test-only numbers).
final _cpfrFixture = {
  'monthly_reconciliation': [
    for (final m in [
      [1, 'January', 5200, 4100],
      [2, 'February', 4800, 4300],
      [3, 'March', 6100, 4700],
      [4, 'April', 3900, 4500],
    ])
      {
        'year': 2026,
        'month_num': m[0],
        'month_en': m[1],
        'has_actual_sell_out': true,
        'sell_in_units': m[2],
        'sell_out_units': m[3],
      },
  ],
  'inventory_and_po_items': [
    {'barcode': '1', 'item_code': 'A1', 'sku_name': 'Adeco Oil 1L', 'sell_in_units': 900, 'sell_out_units': 820, 'estimated_stock_units': 80, 'sell_through_pct': 91.1, 'stock_status': 'optimal'},
    {'barcode': '2', 'item_code': 'A2', 'sku_name': 'Adeco Ghee 1kg', 'sell_in_units': 700, 'sell_out_units': 300, 'estimated_stock_units': 400, 'sell_through_pct': 42.9, 'stock_status': 'overstock'},
    {'barcode': '3', 'item_code': 'A3', 'sku_name': 'Adeco Oil 2L', 'sell_in_units': 200, 'sell_out_units': 195, 'estimated_stock_units': 5, 'sell_through_pct': 97.5, 'stock_status': 'urgent_replenishment'},
  ],
};

MockClient _client() => MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
        return http.Response(jsonEncode(_cpfrFixture), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });

Future<void> _pumpAt(WidgetTester tester, double width) =>
    http.runWithClient(() => _pumpAtInner(tester, width), _client);

Future<void> _pumpAtInner(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: ExecutiveScreen(apiClient: ApiClient(tenantId: 'tenant-adeco'))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final width in [1280.0, 900.0]) {
    testWidgets('Market Share section renders with data at ${width.toInt()}px', (tester) async {
      await _pumpAt(tester, width);
      expect(tester.takeException(), isNull);

      expect(find.byKey(const ValueKey('market_share_section')), findsOneWidget);
      expect(find.byKey(const ValueKey('executive_period_segmented')), findsOneWidget);
      expect(find.byKey(const ValueKey('share_per_sku_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('share_per_sku_badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('share_per_category_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell_in_vs_out_section')), findsOneWidget);
      expect(find.byKey(const ValueKey('kpi_net_accumulation')), findsOneWidget);
      expect(find.byKey(const ValueKey('kpi_sell_through')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock_per_sku_table')), findsOneWidget);
      expect(find.byKey(const ValueKey('sell_in_vs_out_chart')), findsOneWidget);

      // New sections sit above the existing Bento KPI grid.
      final newTop = tester.getTopLeft(find.byKey(const ValueKey('market_share_section'))).dy;
      final trendTop = tester.getTopLeft(find.text('Category Contribution').first).dy;
      expect(newTop, lessThan(trendTop));
    });
  }

  testWidgets('Period segmented switches to quarterly and shows Q1–Q4', (tester) async {
    await _pumpAt(tester, 1280);
    expect(find.byKey(const ValueKey('executive_quarter_segmented')), findsNothing);
    await tester.tap(find.text('Quarterly'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('executive_quarter_segmented')), findsOneWidget);
    await tester.tap(find.text('Q2'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('market_share_section')), findsOneWidget);
  });

  testWidgets('No synthetic CPFR data: unavailable Sell In shows an honest empty state', (tester) async {
    await http.runWithClient(
      () => _pumpAtInner(tester, 1280),
      () => MockClient((req) async => req.url.path.endsWith('/api/v1/analytics/cpfr')
          ? http.Response('down', 503)
          : http.Response('not found', 404)),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('sell_in_vs_out_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_net_accumulation')), findsNothing);
  });
}

// v132 table rules follow-up: the Sell-Out «الباركود» header is centred over
// its cells, and CPFR Suggested Orders item names wrap up to 3 lines (rows
// grow) instead of ellipsizing after 1 line. Real Cairo font, 1280dp.
// All names and numbers are made-up fixtures.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'cpfr_dashboard_refinements_test.dart' show MockCPFRApiClient;
import 'support/real_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget page,
    {double width = 1280, double height = 3000}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
        textDirection: TextDirection.rtl, child: Scaffold(body: page)),
  ));
  await tester.pumpAndSettle();
}

double _glyphCenterX(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(finder);
  final len = p.text.toPlainText().length;
  final boxes =
      p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  final l = boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
  final r = boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
  return p.localToGlobal(Offset((l + r) / 2, 0)).dx;
}

const _longName =
    'منظف أرضيات تجريبي برائحة اللافندر عبوة اقتصادية كبيرة الحجم';

class _PoApi extends MockCPFRApiClient {
  @override
  Future<CPFRDashboardModel> fetchCPFRDashboard({
    String chain = 'all',
    String sector = 'all',
    String region = 'all',
    String brand = 'all',
    String rep = 'all',
    String stockStatus = 'all',
    int leadTimeDays = 4,
    int safetyStockDays = 7,
    int? year,
    bool allowLocalFallback = true,
  }) async =>
      CPFRDashboardModel.fromJson({
        'tenant_id': 'tenant-adeco',
        'retailer_chain': chain,
        'inventory_and_po_items': [
          for (final (i, n) in [_longName, 'صنف تجريبي قصير'].indexed)
            {
              'item_code': 'T-$i',
              'barcode': '00000000000$i',
              'sku_name': n,
              'brand': 'Test',
              'sector': 'MT',
              'governorate': 'القاهرة',
              'region_code': 'C1',
              'sales_rep': 'مندوب تجريبي',
              'sell_in_cases': 10.0,
              'estimated_stock_cases': 4.0,
              'stock_status': 'optimal',
            },
        ],
      });
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets('Sell-Out main table: «الباركود» header centred over its cells',
      (tester) async {
    await _pump(tester, SellOutExplorerScreen(apiClient: ApiClient()));
    expect(tester.takeException(), isNull);
    final head = find.descendant(
        of: find.byKey(const ValueKey('sort_header_barcode')),
        matching: find.text('الباركود'));
    expect(head, findsOneWidget);
    // The barcode value of the first row (monospace SelectableText).
    final first = find.byType(SelectableText).first;
    final cellRect = tester.getRect(first);
    final headX = _glyphCenterX(tester, head);
    expect(cellRect.center.dx, closeTo(headX, 12.0),
        reason: 'barcode cell centre ${cellRect.center.dx} vs header $headX');
    // Header column box: glyphs sit in its middle, not at the start.
    final col = tester.getRect(find.byKey(const ValueKey('sort_header_barcode')));
    expect(headX, closeTo(col.center.dx, 2.0));
  });

  testWidgets('CPFR Suggested Orders: item names wrap up to 3 lines',
      (tester) async {
    await _pump(tester, CPFRDashboardScreen(apiClient: _PoApi()),
        height: 4000);
    await tester.tap(find.text('2. Suggested PO & Replenishment').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final name = find.text(_longName);
    expect(name, findsWidgets);
    final p = tester.renderObject<RenderParagraph>(name.first);
    final t = tester.widget<Text>(name.first);
    expect(t.maxLines, 3);
    // Needs more than one line in the 210dp column, and is not cut early.
    final lineH = (p.text.style?.fontSize ?? 14) * 1.2;
    expect(p.size.height, greaterThan(1.5 * lineH));
    expect(p.didExceedMaxLines, isFalse);
    // The row grew: name + code line lay out without a RenderFlex overflow.
    expect(find.text('T-0 • 000000000000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

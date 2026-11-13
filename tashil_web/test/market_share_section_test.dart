import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/bento_kpi_grid.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/market_share_section.dart';

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

      // Row A: SKU share + stock by SKU; row B: category share + monthly chart.
      final skuR = tester.getRect(find.byKey(const ValueKey('share_per_sku_card')));
      final table = tester.getRect(find.byKey(const ValueKey('stock_per_sku_table')));
      final catR = tester.getRect(find.byKey(const ValueKey('share_per_category_card')));
      final chart = tester.getRect(find.byKey(const ValueKey('sell_in_vs_out_chart')));
      final tilesR = tester.getRect(find.byKey(const ValueKey('sell_in_vs_out_section')));
      expect(find.byKey(const ValueKey('exec_row_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('exec_row_b')), findsOneWidget);
      if (skuR.top == table.top) {
        // Wide (RTL): SKU at the start (right), equal heights per row.
        expect(skuR.height, closeTo(table.height, 1));
        final rtl = Directionality.of(tester.element(
                find.byKey(const ValueKey('share_per_sku_card')))) ==
            TextDirection.rtl;
        expect(rtl ? skuR.left : table.left,
            greaterThan((rtl ? table.right : skuR.right) - 1));
        expect(chart.top, closeTo(catR.top, 1));
        expect(chart.height, closeTo(catR.height, 1));
        expect(rtl ? catR.left : chart.left,
            greaterThan((rtl ? chart.right : catR.right) - 1));
      } else {
        // Narrow: one column — SKU, stock, tiles, category, monthly.
        expect(table.top, greaterThanOrEqualTo(skuR.bottom - 1));
        expect(catR.top, greaterThanOrEqualTo(table.bottom - 1));
        expect(chart.top, greaterThanOrEqualTo(catR.bottom - 1));
      }
      // The four Sell-In/Sell-Out tiles sit full width between the rows.
      expect(tilesR.top, greaterThanOrEqualTo(table.bottom - 1));
      expect(catR.top, greaterThanOrEqualTo(tilesR.bottom - 1));

      // The original four KPI cards open the page; market share sits under them,
      // and the older sections (category contribution, trend, Pareto) stay below that.
      final kpiTop = tester.getTopLeft(find.byType(BentoKpiGrid)).dy;
      final shareTop = tester.getTopLeft(find.byKey(const ValueKey('market_share_section'))).dy;
      final categoryTop = tester.getTopLeft(find.text('مساهمة الفئات').first).dy;
      expect(kpiTop, lessThan(shareTop));
      expect(shareTop, lessThan(categoryTop));
      expect(find.text('إجمالي Sell-Out'), findsOneWidget);
      expect(find.text('إجمالي الوحدات المباعة'), findsOneWidget);
      expect(find.text('الفروع النشطة'), findsOneWidget);
      expect(find.text('نسبة نفاد المخزون (OOS)'), findsOneWidget);
    });
  }

  testWidgets('Period segmented switches to quarterly and shows Q1–Q4', (tester) async {
    await _pumpAt(tester, 1280);
    expect(find.byKey(const ValueKey('executive_quarter_segmented')), findsNothing);
    await tester.tap(find.text('ربع سنوي'));
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

  testWidgets('Category tiles show our rank and named competitors from the backend', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final kpis = ExecutiveKPIsModel.fromJson({
      'category_contributions': [
        {
          'category': 'Laundry',
          'total_revenue': 300.0,
          'market_total_revenue': 1100.0,
          'tenant_category_share_pct': 27.3,
          'tenant_rank': 2,
          'supplier_count': 4,
          'top_competitors': [
            {'name': 'P&G', 'revenue': 500.0, 'share_pct': 45.5},
            {'name': 'Henkel', 'revenue': 200.0, 'share_pct': 18.2},
          ],
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarketShareSection(
            kpis: kpis,
            cpfr: null,
            cpfrLoading: false,
            cpfrError: null,
            periodMonths: const {1, 2, 3},
            year: 2026,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('المرتبة 2 من 4'), findsOneWidget);
    expect(find.text('P&G'), findsOneWidget);
    expect(find.text('Henkel'), findsOneWidget);
    expect(find.byKey(const ValueKey('category_competitor_Laundry_1')), findsOneWidget);
  });

  ExecutiveKPIsModel shareFixture({int skuCount = 6, bool tallCategories = false}) {
    final categories = [
      for (final spec in [
        ('Floor cleaner', 1, 14, 510.0, 51.0),
        ('Dish soap', 1, 9, 330.0, 33.0),
        ('Softener', 2, 8, 270.0, 27.0),
        ('Bleach', 1, 4, 580.0, 58.0),
      ])
        {
          'category': spec.$1,
          'total_revenue': spec.$4,
          'total_units': 10,
          'share_pct': spec.$5,
          'sku_count': 2,
          'market_total_revenue': 1000.0,
          'tenant_category_share_pct': spec.$5,
          'tenant_rank': spec.$2,
          'supplier_count': spec.$3,
          'top_competitors': [
            for (var i = 0; i < (tallCategories ? 3 : 2); i++)
              {'name': 'Competitor ${spec.$1} $i', 'revenue': 100.0 - i * 10, 'share_pct': 10.0 - i},
          ],
        },
    ];
    final skus = [
      for (var i = 0; i < skuCount; i++)
        {
          'barcode': 'sku-$i',
          'sku_name': 'Test SKU $i',
          'category': categories[i % categories.length]['category'],
          'total_revenue': 200.0 - i * 10,
          'total_units': 5,
          'revenue_share_pct': 10.0,
          'cumulative_share_pct': 10.0,
          'is_top_80_contributor': true,
        },
    ];
    return ExecutiveKPIsModel.fromJson({
      'category_contributions': categories,
      'pareto_skus': skus,
    });
  }

  Future<void> pumpShare(WidgetTester tester, double width, ExecutiveKPIsModel kpis) async {
    tester.view.physicalSize = Size(width, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MarketShareSection(
              kpis: kpis,
              cpfr: null,
              cpfrLoading: false,
              cpfrError: null,
              periodMonths: const {1, 2, 3, 4},
              year: 2026,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final width in [1280.0, 1440.0, 1920.0]) {
    testWidgets('Row A / row B cards are equal height at ${width.toInt()}px', (tester) async {
      await pumpShare(tester, width, shareFixture());
      expect(tester.takeException(), isNull);
      // Row A pairs SKU share with stock; row B pairs category with monthly.
      final sku = tester.getRect(find.byKey(const ValueKey('share_per_sku_card')));
      final stock = tester.getRect(find.byKey(const ValueKey('stock_per_sku_table')));
      final cat = tester.getRect(find.byKey(const ValueKey('share_per_category_card')));
      final bars = tester.getRect(find.byKey(const ValueKey('sell_in_vs_out_chart')));
      expect(sku.height, closeTo(stock.height, 1));
      expect(sku.top, closeTo(stock.top, 1));
      expect(cat.height, closeTo(bars.height, 1));
      expect(cat.top, closeTo(bars.top, 1));
      expect(cat.top, greaterThanOrEqualTo(sku.bottom - 1));
      // RTL: the stock / monthly cards are the second child, so they sit on the left.
      expect(stock.right, lessThanOrEqualTo(sku.left + 1));
      expect(bars.right, lessThanOrEqualTo(cat.left + 1));
      expect(find.text('Test SKU 0'), findsOneWidget);
      expect(find.text('Test SKU 5'), findsOneWidget);
      expect(find.text('المرتبة 1 من 14'), findsOneWidget);
      expect(find.text('Competitor Floor cleaner 0'), findsOneWidget);
      expect(find.text('هذا الصنف'), findsOneWidget);
      expect(find.text('أصنافنا الأخرى'), findsOneWidget);
      expect(find.text('المنافسون'), findsWidgets);
      final donut = tester.getSize(find.byKey(const ValueKey('category_donut_Floor cleaner')));
      // Compact 64dp unless row B stretches the category card.
      expect(donut.height, greaterThanOrEqualTo(64));
      expect(donut.width, closeTo(donut.height, 1));
    });
  }

  testWidgets('Tall category tiles: row B cards still match; SKU card keeps its bar', (tester) async {
    await pumpShare(tester, 1280, shareFixture(skuCount: 1, tallCategories: true));
    expect(tester.takeException(), isNull);
    final cat = tester.getRect(find.byKey(const ValueKey('share_per_category_card')));
    final bars = tester.getRect(find.byKey(const ValueKey('sell_in_vs_out_chart')));
    expect(cat.height, closeTo(bars.height, 1));
    expect(tester.getSize(find.byKey(const ValueKey('sku_share_bar_0'))).height, greaterThan(12));
    expect(find.text('Test SKU 0'), findsOneWidget);
    expect(find.text('المرتبة 2 من 8'), findsOneWidget);
    expect(find.text('Competitor Bleach 2'), findsOneWidget);
  });

  testWidgets('Narrow width stacks the share cards without dropping content', (tester) async {
    await pumpShare(tester, 700, shareFixture());
    expect(tester.takeException(), isNull);
    final sku = tester.getRect(find.byKey(const ValueKey('share_per_sku_card')));
    final cat = tester.getRect(find.byKey(const ValueKey('share_per_category_card')));
    expect(cat.top, greaterThanOrEqualTo(sku.bottom - 1));
    expect(sku.width, closeTo(cat.width, 1));
    expect(find.text('الحصة حسب الصنف'), findsOneWidget);
    expect(find.text('الحصة حسب الفئة'), findsOneWidget);
    expect(find.text('Test SKU 5'), findsOneWidget);
    expect(find.text('المرتبة 1 من 4'), findsOneWidget);
    // Compact donut when the card is not stretched to a sibling.
    expect(tester.getSize(find.byKey(const ValueKey('category_donut_Floor cleaner'))).height, closeTo(64, 1));
  });

  Future<void> pumpSellIn(WidgetTester tester, double width) async {
    final json = Map<String, dynamic>.from(_cpfrFixture);
    json['inventory_and_po_items'] = [
      for (var i = 0; i < 8; i++)
        {'barcode': 'b$i', 'item_code': 'I$i', 'sku_name': 'Stock SKU $i', 'sell_in_units': 1000 - i * 50, 'sell_out_units': 500, 'estimated_stock_units': 100, 'sell_through_pct': 50.0, 'stock_status': 'optimal'},
    ];
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarketShareSection(
            kpis: ExecutiveKPIsModel.fromJson(const {}),
            cpfr: CPFRDashboardModel.fromJson(json),
            cpfrLoading: false,
            cpfrError: null,
            periodMonths: const {1, 2, 3, 4},
            year: 2026,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final width in [1280.0, 1920.0]) {
    testWidgets('Stock per SKU sits in row A, monthly chart in row B at ${width.toInt()}px', (tester) async {
      await pumpSellIn(tester, width);
      expect(tester.takeException(), isNull);
      final sku = tester.getRect(find.byKey(const ValueKey('share_per_sku_card')));
      final table = tester.getRect(find.byKey(const ValueKey('stock_per_sku_table')));
      final cat = tester.getRect(find.byKey(const ValueKey('share_per_category_card')));
      final chart = tester.getRect(find.byKey(const ValueKey('sell_in_vs_out_chart')));
      expect(table.top, closeTo(sku.top, 1));
      expect(table.height, closeTo(sku.height, 1));
      expect(chart.top, closeTo(cat.top, 1));
      expect(chart.height, closeTo(cat.height, 1));
      expect(chart.top, greaterThanOrEqualTo(table.bottom - 1));
      for (var i = 0; i < 8; i++) {
        expect(find.text('Stock SKU $i'), findsOneWidget);
      }
    });
  }

  testWidgets('Narrow width stacks Stock per SKU above the monthly chart', (tester) async {
    await pumpSellIn(tester, 700);
    expect(tester.takeException(), isNull);
    final table = tester.getRect(find.byKey(const ValueKey('stock_per_sku_table')));
    final chart = tester.getRect(find.byKey(const ValueKey('sell_in_vs_out_chart')));
    expect(chart.top, greaterThanOrEqualTo(table.bottom - 1));
    expect(find.text('Stock SKU 7'), findsOneWidget);
  });

  test('Signed units keep the sign on the left in RTL (isolate + U+2212)', () {
    expect(formatSignedUnits(-45080), '\u2066\u221245,080\u2069');
    expect(formatSignedUnits(10000), '\u2066+10,000\u2069');
    expect(formatSignedUnits(0), '\u20660\u2069');
  });

  testWidgets('Inventory difference column uses the isolated signed format',
      (tester) async {
    await _pumpAt(tester, 1280.0);
    final table = find.byKey(const ValueKey('stock_per_sku_table'));
    expect(
        find.descendant(of: table, matching: find.text('\u2066+80\u2069')),
        findsOneWidget);
    expect(find.text('\u2066+2,400\u2069'), findsOneWidget); // net tile
  });
}

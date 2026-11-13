import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/core/utils/arabic_plural.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/chain_share_pie.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';

// v124 dashboard M3 follow-ups (F2-F7 of dashboard-verify-v112.md).
// All names and numbers below are made-up test fixtures.

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


/// Horizontal centre (global) of the painted glyphs of [finder]'s Text.
double _glyphCenterX(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(finder);
  final len = p.text.toPlainText().length;
  final boxes =
      p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  final l = boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
  final r = boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
  return p.localToGlobal(Offset((l + r) / 2, 0)).dx;
}

List<SupplierShareModel> _suppliers() => [
      for (var i = 0; i < 4; i++)
        SupplierShareModel(
          supplierName: 'مورد تجريبي ${i + 1} (Test Supplier ${i + 1})',
          totalRevenue: 400000.0 - i * 50000,
          totalUnits: 3000 - i * 200,
          marketSharePct: 20.0 - i * 3,
          skuCount: 10 + i,
          isTenant: i == 1,
          rank: i + 1,
        ),
    ];

Future<void> _pumpPareto(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: ParetoCategorySection(
            categories: const [],
            paretoSkus: const [],
            supplierShares: _suppliers(),
            totalMarketRevenue: 2000000,
            tenantMarketSharePct: 17.0,
            competitorsCount: 105,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('F4: competitor and active-chain counts use Arabic counted nouns', () {
    expect(countCompetitors(105), '105 منافسين');
    expect(countCompetitors(1), 'منافس واحد');
    expect(countCompetitors(2), 'منافسان');
    expect(countCompetitors(7), '7 منافسين');
    expect(countCompetitors(23), '23 منافسًا');
    expect(countCompetitors(100), '100 منافس');
    expect(countActiveChains(1), 'سلسلة نشطة واحدة');
    expect(countActiveChains(2), 'سلسلتان نشطتان');
    expect(countActiveChains(4), '4 سلاسل نشطة');
    expect(countActiveChains(12), '12 سلسلة نشطة');
  });

  testWidgets('F4/F5/F7/F3: supplier card counts, rank semantics, 8dp gaps',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpPareto(tester);
    expect(tester.takeException(), isNull);
    // F4
    expect(find.text('105 منافسين'), findsOneWidget);
    expect(find.text('105 منافس'), findsNothing);
    // F5: the bare rank number is announced as a rank.
    expect(find.bySemanticsLabel(RegExp('المركز 3')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('المركز 4')), findsWidgets);
    // F7: no 10dp wraps / gaps and no 5-6dp icon-label gaps in chips.
    for (final w in tester.widgetList<Wrap>(find.byType(Wrap))) {
      expect(w.spacing, isNot(10.0));
    }
    for (final b in tester.widgetList<SizedBox>(find.byType(SizedBox))) {
      expect(b.height, isNot(10.0));
    }
    final chipGaps = find.descendant(
        of: find.byType(M3ChipSurface), matching: find.byType(SizedBox));
    for (final b in tester.widgetList<SizedBox>(chipGaps)) {
      if (b.width != null && b.height == null) expect(b.width, 8.0);
    }
    // F3: neutral info chips use one fill (surfaceContainerLowest + outline);
    // only the non-tenant rank chips keep surfaceContainerHighest.
    final cs = Theme.of(tester.element(find.byType(ParetoCategorySection)))
        .colorScheme;
    for (final c in tester.widgetList<M3ChipSurface>(find.byType(M3ChipSurface))) {
      expect(c.color, isNot(cs.surfaceContainer));
      expect(c.color, isNot(cs.surfaceContainerHigh));
      if (c.color == cs.surfaceContainerHighest) {
        expect(c.child, isA<Text>(), reason: 'only the rank chip');
        expect(int.tryParse((c.child as Text).data ?? ''), isNotNull);
      }
    }
    handle.dispose();
  });

  testWidgets('F4/F3: one active chain reads "سلسلة نشطة واحدة"',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: ChainSharePie(chainShares: [
              ChainShareItem(
                retailerChain: 'chain_a',
                displayName: 'سلسلة تجريبية',
                totalRevenue: 100000,
                totalUnits: 900,
                marketShare: 100,
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('سلسلة نشطة واحدة'), findsOneWidget);
    expect(find.text('1 سلسلة نشطة'), findsNothing);
    final cs = Theme.of(tester.element(find.byType(ChainSharePie))).colorScheme;
    for (final c in tester.widgetList<M3ChipSurface>(find.byType(M3ChipSurface))) {
      expect(c.color, isNot(cs.surfaceContainerHigh));
    }
  });

  for (final width in [1920.0, 1440.0]) {
    testWidgets('F2: stock table headings sit over their numbers at '
        '${width.toInt()}', (tester) async {
      await _pumpAt(tester, width);
      expect(tester.takeException(), isNull);
      final tableKey = find.byKey(const ValueKey('stock_per_sku_table'));
      final table = tester.widget<Table>(
          find.descendant(of: tableKey, matching: find.byType(Table)));
      final heads = ['Sell-In', 'Sell-Out', 'الفرق', 'نسبة التصريف'];
      for (var c = 1; c <= 4; c++) {
        final head = find.descendant(
            of: tableKey, matching: find.text(heads[c - 1]));
        final cell = find.descendant(
            of: find.byWidget(table.children[1].children[c]),
            matching: find.byType(Text));
        expect(_glyphCenterX(tester, head),
            closeTo(_glyphCenterX(tester, cell), 1.0),
            reason: '${heads[c - 1]} at ${width.toInt()}');
      }
    });
  }

  testWidgets('F6: below 1600dp the stock table gets 7/12 of row A',
      (tester) async {
    await _pumpAt(tester, 1440);
    final sku = tester.getRect(find.byKey(const ValueKey('share_per_sku_card')));
    final stock =
        tester.getRect(find.byKey(const ValueKey('stock_per_sku_table')));
    expect(sku.top, closeTo(stock.top, 1));
    expect(stock.width / sku.width, closeTo(7 / 5, 0.02));
    expect(stock.height, closeTo(sku.height, 1));
  });
}

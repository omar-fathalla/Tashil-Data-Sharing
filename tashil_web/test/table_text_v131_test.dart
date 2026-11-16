// v131 table rules (owner): headers + cells centred (the item name stays
// start-aligned); item names, branch names and secondary details wrap up to
// 3 lines with no ellipsis before 3 lines; dropdowns never clip their value.
// Real Cairo font, 1280dp. All names and numbers are made-up fixtures.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart';

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

/// Horizontal centre of the painted glyphs of a Text.
double _glyphCenterX(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(finder);
  final len = p.text.toPlainText().length;
  final boxes =
      p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  final l = boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
  final r = boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
  return p.localToGlobal(Offset((l + r) / 2, 0)).dx;
}

/// Text under [scope] that is ellipsized although it has fewer than 3 lines
/// (or is capped below 3 lines). Returns readable descriptions.
List<String> _cutBeforeThreeLines(WidgetTester tester, Finder scope,
    {bool Function(Text t)? only}) {
  final out = <String>[];
  for (final e
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final t = e.widget as Text;
    if (only != null && !only(t)) continue;
    final p = tester
        .renderObject<RenderParagraph>(find.byElementPredicate((x) => x == e));
    if (p.didExceedMaxLines && (t.maxLines ?? 99) < 3) {
      out.add('"${t.data}" cut at maxLines ${t.maxLines}');
    }
  }
  return out;
}

/// Every visible DropdownMenu field must show its whole value.
List<String> _clippedDropdowns(WidgetTester tester) {
  final out = <String>[];
  for (final e in find
      .byType(DropdownMenu<int>)
      .evaluate()
      .followedBy(find.byType(DropdownMenu<String>).evaluate())) {
    final editable = find.descendant(
        of: find.byElementPredicate((x) => x == e),
        matching: find.byType(EditableText));
    if (editable.evaluate().isEmpty) continue;
    final et = tester.widget<EditableText>(editable.first);
    final text = et.controller.text;
    if (text.isEmpty) continue;
    final box = tester.renderObject<RenderBox>(editable.first);
    final tp = TextPainter(
      text: TextSpan(text: text, style: et.style),
      textDirection: Directionality.of(e),
      textScaler: MediaQuery.textScalerOf(e),
      maxLines: 1,
    )..layout();
    if (tp.width > box.size.width + 0.5) {
      out.add('"$text" ${tp.width.toStringAsFixed(1)} > '
          '${box.size.width.toStringAsFixed(1)}');
    }
  }
  return out;
}

const _longName =
    'زيت عباد الشمس النقي الممتاز عبوة بلاستيك اقتصادية كبيرة الحجم مع غطاء محكم ضد التسريب';

final _cpfrFixture = {
  'monthly_reconciliation': [
    for (final m in [
      [1, 'January', 5200, 4100],
      [2, 'February', 4800, 4300],
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
    {
      'barcode': '1',
      'item_code': 'A1',
      'sku_name': _longName,
      'department_ar': 'زيوت الطعام والسمن النباتي والحيواني ومشتقاتها',
      'sell_in_units': 900,
      'sell_out_units': 820,
      'estimated_stock_units': 80,
      'sell_through_pct': 91.1,
      'stock_status': 'optimal'
    },
    {
      'barcode': '2',
      'item_code': 'A2',
      'sku_name': 'سمن تجريبي 1 كجم',
      'sell_in_units': 700,
      'sell_out_units': 300,
      'estimated_stock_units': 400,
      'sell_through_pct': 42.9,
      'stock_status': 'overstock'
    },
  ],
};

MockClient _dashClient() => MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
        return http.Response(jsonEncode(_cpfrFixture), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });

SellOutExplorerData _priceData() => const SellOutExplorerData(
      records: [],
      summary: SellOutRecordsSummaryModel(
        totalCount: 2,
        totalNetRevenue: 1000,
        totalUnitsSold: 100,
        totalCartonsSold: 10,
        matchedSkusCount: 2,
        skuSummaries: [
          SellOutSkuSummaryModel(
            itemCode: 'T-1',
            skuName: _longName,
            unitsPerCarton: 12,
            officialConsumerRsp: 50,
            avgSellingPrice: 48.27,
            priceDeltaPct: -3.46,
            totalUnitsSold: 60,
          ),
          SellOutSkuSummaryModel(
            itemCode: 'T-2',
            skuName: 'صابون تجريبي',
            unitsPerCarton: 24,
            officialConsumerRsp: 20,
            avgSellingPrice: 22.4,
            priceDeltaPct: 12.0,
            totalUnitsSold: 40,
          ),
        ],
      ),
      stores: [],
      currentBranchMatrix: [],
      prevBranchMatrix: [],
      yoyCurrentBranchMatrix: [],
    );

class _OneShotRepo extends SellOutExplorerRepository {
  _OneShotRepo(this._data)
      : super(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
  final SellOutExplorerData _data;

  @override
  Future<Result<SellOutExplorerData>> load(SellOutExplorerQuery q,
          {bool forceRefresh = false}) async =>
      Success(_data);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  group('F1 Sell-Out sales', () {
    testWidgets('main table: branch names + details wrap to 3 lines, centred',
        (tester) async {
      await _pump(tester, SellOutExplorerScreen(apiClient: ApiClient()));
      expect(tester.takeException(), isNull);
      final table = find.byType(VirtualizedSkuTable);
      expect(table, findsOneWidget);
      for (final k in ['sku_table_sku_name', 'sku_table_store_name']) {
        final f = find.byKey(ValueKey(k));
        expect(f, findsWidgets, reason: k);
        for (final t in tester.widgetList<Text>(f)) {
          expect(t.maxLines, 3, reason: k);
        }
      }
      for (final t in tester.widgetList<Text>(
          find.byKey(const ValueKey('sku_table_store_name')))) {
        expect(t.textAlign, TextAlign.center);
      }
      expect(_cutBeforeThreeLines(tester, table), isEmpty);
      // Metric column: heading glyphs centred over the first row's value.
      final head =
          find.descendant(of: table, matching: find.text('الوحدات المباعة'));
      final units = find.byKey(const ValueKey('sku_table_units'));
      expect(units, findsWidgets);
      expect(_glyphCenterX(tester, units.first),
          closeTo(_glyphCenterX(tester, head), 2.0));
    });

    testWidgets('pricing table: name ≤2 lines + nested code, cells centred',
        (tester) async {
      await _pump(
          tester,
          SellOutExplorerScreen(
              apiClient:
                  ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
              repository: _OneShotRepo(_priceData())));
      final names = find.byKey(const ValueKey('price_matrix_sku_name'));
      expect(names, findsWidgets);
      for (final t in tester.widgetList<Text>(names)) {
        expect(t.maxLines, 2);
      }
      expect(find.byKey(const ValueKey('price_matrix_item_code')), findsWidgets);
      final table = find.byKey(const ValueKey('price_matrix_table'));
      // Official name intentionally caps at 2 lines (+ code line = ≤3 total).
      expect(
        _cutBeforeThreeLines(tester, table,
            only: (t) => t.key != const ValueKey('price_matrix_sku_name')),
        isEmpty,
      );
      String? colLabel(DataColumn c) {
        Widget w = c.label;
        while (true) {
          if (w is Text) return w.data;
          if (w is ConstrainedBox && w.child != null) {
            w = w.child!;
            continue;
          }
          if (w is Align && w.child != null) {
            w = w.child!;
            continue;
          }
          return null;
        }
      }

      final dt = tester.widget<DataTable>(
          find.descendant(of: table, matching: find.byType(DataTable)));
      for (final (i, c) in dt.columns.indexed) {
        final label = colLabel(c);
        expect(
            c.headingRowAlignment,
            label == 'الصنف الرسمي'
                ? isNot(MainAxisAlignment.center)
                : MainAxisAlignment.center,
            reason: label);
        if (label == 'وحدات/كرتونة') {
          final head = find.descendant(of: table, matching: find.text(label!));
          final cell = find.descendant(
              of: find.byWidget(dt.rows.first.cells[i].child),
              matching: find.byType(Text));
          expect(_glyphCenterX(tester, cell.first),
              closeTo(_glyphCenterX(tester, head), 2.0));
        }
      }
    });
  });

  testWidgets('F2 dashboard inventory-by-item: long names use 3 lines',
      (tester) async {
    await http.runWithClient(
        () => _pump(tester,
            ExecutiveScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
            height: 1400),
        _dashClient);
    final table = find.byKey(const ValueKey('stock_per_sku_table'));
    final name = find.descendant(of: table, matching: find.text(_longName));
    expect(name, findsOneWidget);
    expect(tester.widget<Text>(name).maxLines, 3);
    final p = tester.renderObject<RenderParagraph>(name);
    // The fixture name needs 3 lines at 1280: all 3 are shown, not 2 + "…".
    expect(
        p.size.height, greaterThan(2.5 * (p.text.style?.fontSize ?? 14) * 1.2));
    expect(_cutBeforeThreeLines(tester, table), isEmpty);
  });

  testWidgets('F3 CPFR reconciliation: numbers centred under headings',
      (tester) async {
    await _pump(tester, CPFRDashboardScreen(apiClient: MockCPFRApiClient()));
    expect(tester.takeException(), isNull);
    final head = find.text('الأصناف النشطة');
    expect(head, findsWidgets);
    final dt = tester.widget<DataTable>(
        find.ancestor(of: head.first, matching: find.byType(DataTable)));
    String? colLabel(DataColumn c) {
      Widget w = c.label;
      while (true) {
        if (w is Text) return w.data;
        if (w is ConstrainedBox && w.child != null) {
          w = w.child!;
          continue;
        }
        if (w is Align && w.child != null) {
          w = w.child!;
          continue;
        }
        return null;
      }
    }

    final i = dt.columns.indexWhere((c) => colLabel(c) == 'الأصناف النشطة');
    for (final c in dt.columns) {
      expect(c.headingRowAlignment, MainAxisAlignment.center,
          reason: colLabel(c));
    }
    expect(dt.rows, isNotEmpty);
    final cell = find.descendant(
        of: find.byWidget(dt.rows.first.cells[i].child),
        matching: find.byType(Text));
    expect(_glyphCenterX(tester, cell.first),
        closeTo(_glyphCenterX(tester, head.first), 2.0));
  });

  // 1000 ≈ the content width at a 1280 window beside the navigation rail.
  for (final width in [1280.0, 1000.0]) {
    testWidgets(
        'F4 Sell-In stock: brand dropdown shows its whole value at '
        '${width.toInt()}', (tester) async {
      await _pump(tester,
          SellInExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
          width: width);
      await tester.tap(find.textContaining('المخزون وإعادة الطلب').first);
      await tester.pumpAndSettle();
      expect(_clippedDropdowns(tester), isEmpty);
      expect(find.byKey(const ValueKey('sellin_stock_brand_dropdown')),
          findsOneWidget);
    });
  }
}

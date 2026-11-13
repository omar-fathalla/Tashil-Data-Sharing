// v133: Data Quality issues table centres every column except the item name
// (headers + cells) and fills its card; the Sell-In stock «Sell-In للفترة
// المطابقة» KPI never cuts its title/period at 1280. Real Cairo font.
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
import 'package:tashil_web/features/data_quality/data/data_quality_repository.dart';
import 'package:tashil_web/features/data_quality/presentation/screens/data_quality_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

import 'support/real_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget page,
    {double width = 1280, double height = 2400}) async {
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

class _Src implements DataQualityDataSource {
  @override
  Future<DataQualitySummary> summary() async => const DataQualitySummary(
        types: [],
        totalRows: 10,
        criticalRows: 1,
        cleanlinessPct: 90,
        open: 1,
      );

  @override
  Future<List<DataQualityIssue>> issues(DataQualityFilter f) async => const [
        DataQualityIssue(
          id: 't1',
          source: 'product_master',
          type: 'duplicate_barcode',
          typeLabel: 'باركود مكرر',
          severity: kDqCritical,
          row: 12,
          itemCode: 'TEST-0001',
          barcode: '0000000000001',
          itemName: 'صنف تجريبي',
          status: kDqOpen,
        ),
      ];

  @override
  Future<DataQualityIssue> updateStatus(
          String id, String status, String reason) async =>
      throw UnimplementedError();
}

class _MatchedApi extends ApiClient {
  _MatchedApi() : super(tenantId: 'tenant-adeco');

  @override
  Future<CPFRDashboardModel> fetchCPFRDashboard({
    String chain = 'all',
    String sector = 'all',
    String region = 'all',
    String brand = 'all',
    String rep = 'all',
    String stockStatus = 'all',
    int? year,
    int leadTimeDays = 4,
    int safetyStockDays = 7,
    bool allowLocalFallback = true,
  }) async =>
      CPFRDashboardModel.fromJson({
        'tenant_id': 'tenant-adeco',
        'retailer_chain': chain,
        'matched_months_count': 10,
        'matched_period_label': 'يناير - أكتوبر 2026 (10 أشهر متطابقة)',
        'matched_sell_in_cases': 1234.0,
        'matched_sell_in_value_excl_vat_egp': 4567890.0,
      });
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets('Data Quality table: columns centred except the item name',
      (tester) async {
    await _pump(tester, DataQualityScreen(dataSource: _Src(),
        pollInterval: const Duration(hours: 1)));
    expect(tester.takeException(), isNull);
    final table = find.byKey(const ValueKey('dq_table'));
    expect(table, findsOneWidget);
    final dt = tester.widget<DataTable>(table);
    for (final c in dt.columns) {
      final label = (c.label as Text).data;
      expect(c.headingRowAlignment,
          label == 'اسم الصنف' ? isNot(MainAxisAlignment.center) : MainAxisAlignment.center,
          reason: label);
    }
    for (final (head, cell) in [
      ('كود الصنف', 'TEST-0001'),
      ('الباركود', '0000000000001'),
      ('النوع', 'باركود مكرر'),
    ]) {
      final h = find.descendant(of: table, matching: find.text(head));
      final c = find.descendant(of: table, matching: find.text(cell));
      expect(_glyphCenterX(tester, c), closeTo(_glyphCenterX(tester, h), 2.0),
          reason: head);
    }
    // Fills its card (no empty band beside a narrow table).
    final card = find.ancestor(of: table, matching: find.byType(Card)).first;
    expect(tester.getSize(table).width,
        greaterThanOrEqualTo(tester.getSize(card).width - 1));
  });

  // 1024 ≈ the content width at a 1280 window beside the navigation rail (4 KPI cards per row, the narrowest case).
  for (final width in [1280.0, 1024.0]) {
    testWidgets('Sell-In stock matched-period KPI is not cut at '
        '${width.toInt()}', (tester) async {
      await _pump(tester, SellInExplorerScreen(apiClient: _MatchedApi()),
          width: width, height: 3000);
      await tester.tap(find.textContaining('المخزون وإعادة الطلب').first);
      await tester.pumpAndSettle();
      final card =
          find.byKey(const ValueKey('kpi_card_Sell-In (matched period)'));
      expect(card, findsOneWidget);
      // The matched period is shown, and no text in the card is cut.
      expect(
          find.descendant(
              of: card, matching: find.textContaining('أكتوبر 2026')),
          findsWidgets);
      final cut = <String>[];
      for (final p in tester
          .renderObjectList<RenderParagraph>(
              find.descendant(of: card, matching: find.byType(RichText)))) {
        if (p.didExceedMaxLines) cut.add(p.text.toPlainText());
      }
      expect(cut, isEmpty);
    });
  }
}

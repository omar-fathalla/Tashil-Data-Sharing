// v186 follow-up after #184: CPFR 6-KPI even widths @ ~880, short Arabic
// page headlines, sidebar taps register from every page.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_button.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/data_quality/presentation/screens/data_quality_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/navigation/presentation/app_shell.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/oos_monitor/presentation/screens/oos_dashboard_screen.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/screens/sell_in_returns_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/store_benchmark/presentation/screens/store_matrix_screen.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

import 'pricing_m3_support.dart' as pricing_support;
import 'support/cpfr_fixtures.dart';
import 'support/product_master_m3_support.dart' show ignoreGoogleFontLoadErrors;
import 'support/real_fonts.dart';

const _kContent880 = 880.0;

const _cpfrKpiKeys = [
  'kpi_card_Sell-In',
  'kpi_card_Sell-Out',
  'kpi_card_Sell-Through Rate',
  'kpi_card_Inventory Gap',
  'kpi_card_Chain Margin',
  'kpi_card_Sell-Out Growth YoY',
];

/// Sidebar English labels (desktop_sidebar.dart) → expected screen type.
final _sidebarDestinations = <({String label, Type screen})>[
  (label: 'Dashboard', screen: ExecutiveScreen),
  (label: 'Sell-Out', screen: SellOutExplorerScreen),
  (label: 'Sell-In', screen: SellInExplorerScreen),
  (label: 'Returns', screen: SellInReturnsScreen),
  (label: 'OOS Monitor', screen: OOSDashboardScreen),
  (label: 'Store Matrix', screen: StoreMatrixScreen),
  (label: 'Pricing & Promos', screen: PricingComplianceScreen),
  (label: 'Compare', screen: CompetitorComparisonScreen),
  (label: 'Trade Marketing & ROI', screen: TradeMarketingRoiScreen),
  (label: 'CPFR Replenishment', screen: CPFRDashboardScreen),
  (label: 'Product Master', screen: ProductMasterScreen),
  (label: 'Errors', screen: DataQualityScreen),
];

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  double width = _kContent880,
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: page),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

bool _titleOneLine(WidgetTester tester, String title) {
  final finder = find.text(title);
  expect(finder, findsOneWidget, reason: title);
  final para = tester.renderObject<RenderParagraph>(finder);
  return !para.didExceedMaxLines && para.size.height < 40;
}

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(() async {
    await loadRealCairoFont();
    await pricing_support.loadPricingFonts();
  });

  group('M3KpiGridColumns.forWidthAndCount count=6', () {
    test('6 cards divide evenly: 3+3 at ~880 and at ≥960', () {
      expect(M3KpiGridColumns.forWidthAndCount(880, 6), 3);
      expect(M3KpiGridColumns.forWidthAndCount(1030, 6), 3);
      expect(M3KpiGridColumns.forWidthAndCount(700, 6), 3);
      expect(M3KpiGridColumns.forWidthAndCount(580, 6), 2);
      expect(M3KpiGridColumns.forWidthAndCount(400, 6), 1);
      // Existing contracts for other counts stay intact.
      expect(M3KpiGridColumns.forWidthAndCount(1030, 5), 3);
      expect(M3KpiGridColumns.forWidthAndCount(700, 5), 2);
      expect(M3KpiGridColumns.forWidthAndCount(400, 5), 1);
    });
  });

  testWidgets(
      'CPFR reconciliation KPIs: all 6 cards equal width at 880 content',
      (tester) async {
    await _pumpPage(
      tester,
      CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
      width: _kContent880,
    );
    expect(tester.takeException(), isNull);

    final widths = <double>[];
    for (final key in _cpfrKpiKeys) {
      final card = find.byKey(ValueKey(key));
      expect(card, findsOneWidget, reason: key);
      widths.add(tester.getSize(card).width);
    }
    final first = widths.first;
    for (var i = 0; i < widths.length; i++) {
      expect(
        widths[i],
        closeTo(first, 1.0),
        reason: '${_cpfrKpiKeys[i]} width ${widths[i]} vs $first',
      );
    }
    // 3 columns at 880 → card width well under half the content.
    expect(first, lessThan(_kContent880 / 2));
    expect(find.byType(M3SummaryKpiCard), findsWidgets);
  });

  testWidgets('Pricing & CPFR Arabic headlines stay one line at 880 content',
      (tester) async {
    await pricing_support.pumpPricing(
      tester,
      PricingComplianceScreen(
        apiClient: pricing_support.PricingShotApiClient(),
      ),
      width: _kContent880,
    );
    expect(_titleOneLine(tester, 'الأسعار والعروض'), isTrue);
    expect(find.text('Pricing & Promos'), findsOneWidget);
    expect(
      find.textContaining('كشف الفروق السعرية عن السعر الاسترشادي'),
      findsOneWidget,
    );

    await _pumpPage(
      tester,
      CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
      width: _kContent880,
    );
    expect(_titleOneLine(tester, 'التخطيط المشترك وأوامر التوريد'), isTrue);
    expect(find.text('CPFR & Inventory Replenishment'), findsOneWidget);
  });

  testWidgets(
      'sidebar page titles one-line Arabic at 880 content (all destinations)',
      (tester) async {
    final pages = <(String, Widget)>[
      (
        'الأسعار والعروض',
        PricingComplianceScreen(
          apiClient: pricing_support.PricingShotApiClient(),
        )
      ),
      (
        'التخطيط المشترك وأوامر التوريد',
        CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
      ),
      ('مراقب النواقص', OOSDashboardScreen(apiClient: ApiClient())),
      (
        'التسويق التجاري والعائد',
        TradeMarketingRoiScreen(apiClient: ApiClient()),
      ),
      ('مصفوفة الفروع', StoreMatrixScreen(apiClient: ApiClient())),
      ('المرتجعات', SellInReturnsScreen(apiClient: ApiClient())),
      ('الأخطاء وجودة البيانات', DataQualityScreen(apiClient: ApiClient())),
      (
        'مبيعات السلاسل للمستهلك وأداء الفروع والمستهدفات',
        SellOutExplorerScreen(apiClient: ApiClient()),
      ),
      (
        'التوريد للسلاسل والمخزون المتبقي والمستهدفات',
        SellInExplorerScreen(apiClient: ApiClient()),
      ),
      (
        'مقارنة المنافسين',
        CompetitorComparisonScreen(apiClient: ApiClient()),
      ),
      (
        'رفع البيانات الذكي',
        UploadPortalScreen(apiClient: ApiClient()),
      ),
    ];

    for (final (title, page) in pages) {
      await _pumpPage(tester, page, width: _kContent880, height: 3200);
      final header = find.byType(M3PageHeader);
      expect(header, findsOneWidget, reason: title);
      final titleFinder = find.descendant(
        of: header,
        matching: find.text(title),
      );
      expect(titleFinder, findsOneWidget, reason: 'header title: $title');
      final para = tester.renderObject<RenderParagraph>(titleFinder);
      expect(
        para.didExceedMaxLines,
        isFalse,
        reason: 'title wraps at 880: $title',
      );
      expect(
        para.size.height,
        lessThan(40),
        reason: 'title not one line ($title): h=${para.size.height}',
      );
    }
  });

  testWidgets('AppShell: tap each sidebar item from each page navigates',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
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
      home: AppShell(
        apiClient: ApiClient(),
        activeTenant: 'adeco',
        onTenantChanged: (_) {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> tapSidebar(String label) async {
      final item = find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text(label),
      );
      expect(item, findsOneWidget, reason: 'sidebar item $label');
      await tester.ensureVisible(item);
      await tester.pump();
      await tester.tap(item);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    for (final from in _sidebarDestinations) {
      await tapSidebar(from.label);
      expect(
        find.byType(from.screen),
        findsOneWidget,
        reason: 'failed to open starting page ${from.label}',
      );

      for (final to in _sidebarDestinations) {
        await tapSidebar(to.label);
        expect(
          find.byType(to.screen),
          findsOneWidget,
          reason: 'from ${from.label} tap ${to.label} → ${to.screen}',
        );
      }
    }
  });
}

// Live-harness Dashboard pass: Chrome 150% zoom fullscreen is a 1280×800
// CSS viewport with the 250dp DesktopSidebar (content 1030dp). Tests use
// that exact width and 1024 (both with the sidebar, which the live
// shell shows at >= 840dp), real Cairo, the ▲▼ fallback font, and
// live-scale (made-up) values. The Dashboard KPI row must use the
// same column count, card width, and 138px height as Sell-Out;
// the stock table must fit with no horizontal scroll; empty last-year
// shows «—» + «لا توجد بيانات للعام السابق»; shared prefix is stripped.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/bento_kpi_grid.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/chain_share_pie.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/market_share_section.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/real_fonts.dart';

const kLiveViewportWidth = 1280.0;
const kSellOutKpiHeight = 138.0;
const kLongSku =
    'عرض شنطة تجريبية (3 عبوة 1050 جم مبيض & 1 عبوة 1 ك *2 )- 3 مجموعة';
const kLongCategory = 'صابون سائل أطباق برائحة الليمون المركز';
const kLongCompetitor = 'إيما التجارية للمنظفات والعناية المنزلية';

final _prefixedChains = [
  ChainShareItem(
    retailerChain: 'chain_nsr',
    displayName: 'عائلة فتح الله ماركت - مدينة نصر',
    totalRevenue: 128400000,
    totalUnits: 214000,
    marketShare: 48.0,
  ),
  ChainShareItem(
    retailerChain: 'chain_alex',
    displayName: 'عائله فتح الله ماركت - الإسكندرية',
    totalRevenue: 71200000,
    totalUnits: 118000,
    marketShare: 27.0,
  ),
  ChainShareItem(
    retailerChain: 'chain_moh',
    displayName: 'عائلة فتح الله ماركت - المهندسين',
    totalRevenue: 66100000,
    totalUnits: 109000,
    marketShare: 25.0,
  ),
];

ExecutiveKPIsModel _liveKpis({bool yoyAvailable = false}) => ExecutiveKPIsModel(
      totalRevenue: 128400000,
      revenueGrowthPct: 8.4,
      revenueMomPct: 8.4,
      revenueYoyPct: 12.1,
      yoyAvailable: yoyAvailable,
      totalUnitsSold: 441000,
      unitsGrowthPct: 5.2,
      unitsMomPct: 5.2,
      unitsYoyPct: 9.8,
      activeStoresCount: 16,
      oosRatePct: 3.2,
      osaRatePct: 96.8,
      totalOOSIncidents: 42,
      estimatedLostRevenue: 1850000,
      currency: 'EGP',
      reportingPeriod: '2026',
      chainShares: _prefixedChains,
      dailyTrends: const [],
      categoryContributions: [
        CategoryContributionModel(
          category: kLongCategory,
          totalRevenue: 34200000,
          totalUnits: 89000,
          sharePct: 27.1,
          skuCount: 32,
          marketTotalRevenue: 102220000,
          tenantCategorySharePct: 33.7,
          tenantRank: 1,
          supplierCount: 13,
          topCompetitors: const [
            CategoryCompetitorModel(
              name: kLongCompetitor,
              revenue: 29600000,
              sharePct: 29.0,
            ),
            CategoryCompetitorModel(
              name: 'هندل بريسل للمنتجات المنزلية',
              revenue: 26600000,
              sharePct: 26.0,
            ),
          ],
        ),
        CategoryContributionModel(
          category: 'كلور عادى',
          totalRevenue: 15720000,
          totalUnits: 41000,
          sharePct: 12.4,
          skuCount: 41,
          marketTotalRevenue: 26620000,
          tenantCategorySharePct: 59.0,
          tenantRank: 1,
          supplierCount: 5,
        ),
      ],
      paretoSkus: [
        ParetoSkuItemModel(
          itemCode: 'PRHC-0003-0009',
          barcode: '6224000000009',
          skuName: kLongSku,
          category: kLongCategory,
          totalRevenue: 12840000,
          totalUnits: 21400,
          revenueSharePct: 16.5,
          cumulativeSharePct: 16.5,
          isTop80Contributor: true,
        ),
      ],
    );

final _liveCpfr = CPFRDashboardModel.fromJson({
  'monthly_reconciliation': [
    for (final m in [
      [1, 'January', 1284000, 1217000],
      [2, 'February', 1190000, 1105000],
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
      'item_code': 'T-1',
      'sku_name': kLongSku,
      'sell_in_units': 1284000,
      'sell_out_units': 1217000,
      'estimated_stock_units': 67000,
      'sell_through_pct': 94.8,
      'stock_status': 'overstock',
    },
    {
      'barcode': '2',
      'item_code': 'T-2',
      'sku_name': 'صنف تجريبي قصير',
      'sell_in_units': 214000,
      'sell_out_units': 198000,
      'estimated_stock_units': 16000,
      'sell_through_pct': 92.5,
      'stock_status': 'urgent_replenishment',
    },
  ],
});

TextTheme _withFallback(TextTheme t, List<String> fb) {
  TextStyle? f(TextStyle? s) =>
      s?.copyWith(fontFamilyFallback: [...?s.fontFamilyFallback, ...fb]);
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

ThemeData _liveTheme() {
  final theme = AppTheme.light();
  return theme.copyWith(
    textTheme: _withFallback(theme.textTheme, const ['NotoSansSymbols2']),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget page, {
  double width = kLiveViewportWidth,
  double height = 4000,
  bool sidebar = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: _liveTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: sidebar && width >= 840
            ? Row(children: [
                DesktopSidebar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  activeTenant: 'adeco',
                  onTenantChanged: (_) {},
                ),
                Expanded(child: page),
              ])
            : page,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Widget _dashboardBody({bool yoy = false}) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            BentoKpiGrid(kpis: _liveKpis(yoyAvailable: yoy)),
            const SizedBox(height: 16),
            MarketShareSection(
              kpis: _liveKpis(yoyAvailable: yoy),
              cpfr: _liveCpfr,
              cpfrLoading: false,
              periodMonths: const {1, 2},
              year: 2026,
            ),
            const SizedBox(height: 16),
            ChainSharePie(chainShares: _prefixedChains),
            const SizedBox(height: 16),
            ParetoCategorySection(
              categories: _liveKpis(yoyAvailable: yoy).categoryContributions,
              paretoSkus: _liveKpis(yoyAvailable: yoy).paretoSkus,
              totalMarketRevenue: 265700000,
              tenantMarketSharePct: 48.0,
              competitorsCount: 6,
            ),
          ],
        ),
      ),
    );

double _hScrollExtent(WidgetTester tester, Finder scope) {
  final scrollable =
      find.descendant(of: scope, matching: find.byType(Scrollable));
  if (scrollable.evaluate().isEmpty) return 0;
  for (final el in scrollable.evaluate()) {
    final s = el.widget as Scrollable;
    if (s.axisDirection == AxisDirection.right ||
        s.axisDirection == AxisDirection.left) {
      final state = tester.state<ScrollableState>(find.byWidget(s));
      if (state.position.hasContentDimensions) {
        return state.position.maxScrollExtent;
      }
    }
  }
  return 0;
}

const _dashboardKpiKeys = [
  'kpi_card_exec_sellout',
  'kpi_card_exec_units',
  'kpi_card_exec_stores',
  'kpi_card_exec_oos',
];

const _sellOutKpiKeys = [
  'kpi_card_Net Sales (EGP)',
  'kpi_card_Total Units Sold',
  'kpi_card_Active SKUs',
  'kpi_card_Active Stores',
];

int _kpiColumnCount(WidgetTester tester, List<String> keys) {
  final tops = [
    for (final key in keys) tester.getRect(find.byKey(ValueKey(key))).top,
  ];
  final first = tops.first;
  return tops.where((top) => (top - first).abs() < 1.0).length;
}

bool _paragraphExceeded(WidgetTester tester, Finder finder) {
  for (final el in finder.evaluate()) {
    final ro = el.renderObject;
    if (ro is RenderParagraph && ro.didExceedMaxLines) return true;
  }
  return false;
}

void _expectUncut(WidgetTester tester, Finder finder,
    {required String reason}) {
  expect(finder, findsWidgets, reason: reason);
  expect(_paragraphExceeded(tester, finder), isFalse, reason: reason);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    await loadRealCairoFont();
  });
  setUp(AppCache.clear);

  testWidgets(
      'Dashboard KPI row matches Sell-Out column count, width and height at live 1280+sidebar and 1024+sidebar',
      (tester) async {
    Future<({int columns, double width, double height})> measureSellOut(
      double width,
    ) async {
      await _pumpAt(
        tester,
        SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
        width: width,
      );
      for (final key in _sellOutKpiKeys) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      final size = tester.getSize(
        find.byKey(ValueKey(_sellOutKpiKeys.first)),
      );
      return (
        columns: _kpiColumnCount(tester, _sellOutKpiKeys),
        width: size.width,
        height: size.height,
      );
    }

    Future<void> expectDashboardMatches(
      ({int columns, double width, double height}) sellOut, {
      required double width,
      required String label,
    }) async {
      await _pumpAt(tester, _dashboardBody(), width: width);
      expect(tester.takeException(), isNull);
      expect(
        _kpiColumnCount(tester, _dashboardKpiKeys),
        sellOut.columns,
        reason: 'Dashboard columns vs Sell-Out at $label',
      );
      for (final key in _dashboardKpiKeys) {
        final card = find.byKey(ValueKey(key));
        expect(card, findsOneWidget, reason: key);
        final size = tester.getSize(card);
        expect(size.height, closeTo(sellOut.height, 2.0),
            reason:
                '$key height ${size.height} vs Sell-Out ${sellOut.height} at $label');
        expect(size.width, closeTo(sellOut.width, 2.0),
            reason:
                '$key width ${size.width} vs Sell-Out ${sellOut.width} at $label');
        expect(size.height, closeTo(kSellOutKpiHeight, 2.0),
            reason: '$key height ${size.height} at $label');
        final kpi = tester.widget<M3SummaryKpiCard>(card);
        expect(kpi.titleMaxLines, 1, reason: key);
        expect(kpi.subtitleMaxLines, 1, reason: key);
      }
    }

    final at1280 = await measureSellOut(kLiveViewportWidth);
    expect(at1280.height, closeTo(kSellOutKpiHeight, 2.0),
        reason: 'Sell-Out reference height is ${at1280.height}');
    expect(at1280.columns, 4,
        reason: 'Sell-Out at live 1280+sidebar should be 4-up '
            '(content after padding is ~982dp, breakpoint 960)');
    await expectDashboardMatches(at1280,
        width: kLiveViewportWidth, label: 'live 1280+sidebar');

    // Empty last year: «—» on the detail line, phrase uncut, no fake YoY %.
    expect(
        find.textContaining('لا توجد بيانات للعام السابق'), findsNWidgets(2));
    expect(find.textContaining('—'), findsWidgets);
    expect(find.textContaining('مقارنة بالعام السابق'), findsNothing);

    final at1024 = await measureSellOut(1024);
    expect(at1024.height, closeTo(kSellOutKpiHeight, 2.0),
        reason: 'Sell-Out height at 1024+sidebar is ${at1024.height}');
    expect(at1024.columns, 2,
        reason: 'Sell-Out at live 1024+sidebar should be 2-up '
            '(content after padding is ~726dp, below 960)');
    await expectDashboardMatches(at1024,
        width: 1024, label: 'live 1024+sidebar');
  });

  testWidgets(
      'at live 1280+sidebar, the stock table fits with no horizontal scroll',
      (tester) async {
    await _pumpAt(tester, _dashboardBody());
    expect(tester.takeException(), isNull);
    final stock = find.byKey(const ValueKey('stock_per_sku_table'));
    expect(stock, findsOneWidget);
    expect(_hScrollExtent(tester, stock), lessThanOrEqualTo(2.0),
        reason: 'stock table still scrolls at live 1280');
    final name = find.byKey(const ValueKey('stock_sku_name'));
    expect(name, findsWidgets);
    final r = tester.getRect(name.first);
    expect(r.left, greaterThanOrEqualTo(-0.5));
    expect(r.right, lessThanOrEqualTo(kLiveViewportWidth + 0.5));
    // Status and item visible together.
    expect(find.text('مخزون زائد'), findsOneWidget);
    final status = tester.getRect(find.text('مخزون زائد'));
    expect(status.right, lessThanOrEqualTo(kLiveViewportWidth + 0.5));
    expect(status.overlaps(r) || status.left < r.left || r.left < status.left,
        isTrue);

    await _pumpAt(tester, _dashboardBody(), width: 1024);
    expect(
        _hScrollExtent(
            tester, find.byKey(const ValueKey('stock_per_sku_table'))),
        lessThanOrEqualTo(2.0),
        reason: 'stock table still scrolls at live 1024+sidebar');
  });

  testWidgets(
      'shared branch prefix is display-stripped; last-year value is — when missing',
      (tester) async {
    await _pumpAt(tester, _dashboardBody());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('عائلة فتح الله ماركت -'), findsNothing);
    expect(find.textContaining('عائله فتح الله ماركت -'), findsNothing);
    expect(find.textContaining('مدينة نصر'), findsWidgets);
    expect(find.textContaining('الإسكندرية'), findsWidgets);
    expect(find.textContaining('المهندسين'), findsWidgets);

    await _pumpAt(tester, _dashboardBody(yoy: true));
    expect(find.textContaining('لا توجد بيانات للعام السابق'), findsNothing);
    expect(find.textContaining('مقارنة بالعام السابق'), findsNWidgets(2));
  });

  testWidgets(
      'at the live shell, secondary cards are 138px and long names wrap without ellipsis',
      (tester) async {
    Future<void> assertAt(double width, String label) async {
      await _pumpAt(tester, _dashboardBody(), width: width);
      expect(tester.takeException(), isNull);

      const secondary = [
        'kpi_card_exec_sellin',
        'kpi_card_exec_cpfr_sellout',
        'kpi_net_accumulation',
        'kpi_sell_through',
      ];
      for (final key in secondary) {
        final card = find.byKey(ValueKey(key));
        expect(card, findsOneWidget, reason: '$key at $label');
        expect(
          tester.getSize(card).height,
          closeTo(kSellOutKpiHeight, 2.0),
          reason: '$key height ${tester.getSize(card).height} at $label',
        );
      }

      // Main 4-up OOS title and store names stay uncut.
      _expectUncut(tester, find.text('نسبة النفاد'),
          reason: 'OOS title cut at $label');
      _expectUncut(
        tester,
        find.textContaining('مدينة نصر'),
        reason: 'store subtitle cut at $label',
      );

      // Stock item name: 3 lines, no ellipsis, full live-length name.
      final stockName = find.byKey(const ValueKey('stock_sku_name'));
      expect(stockName, findsWidgets, reason: 'stock name at $label');
      final nameText = tester.widget<Text>(stockName.first);
      expect(nameText.maxLines, 3);
      expect(nameText.overflow, isNot(TextOverflow.ellipsis));
      expect(nameText.data, kLongSku);
      expect(_paragraphExceeded(tester, stockName.first), isFalse,
          reason: 'stock name ellipsized or overflowed 3 lines at $label');
      expect(find.text(kLongSku), findsWidgets);

      _expectUncut(tester, find.text(kLongCategory),
          reason: 'category label cut at $label');
      _expectUncut(tester, find.text(kLongCompetitor),
          reason: 'competitor label cut at $label');
      _expectUncut(
        tester,
        find.byKey(const ValueKey('pareto_sku_name')),
        reason: 'Pareto SKU name cut at $label',
      );
      _expectUncut(
        tester,
        find.byKey(const ValueKey('pareto_sku_meta')),
        reason: 'Pareto metadata cut at $label',
      );
    }

    await assertAt(kLiveViewportWidth, 'live 1280+sidebar');
    await assertAt(1024, 'live 1024+sidebar');
  });
}

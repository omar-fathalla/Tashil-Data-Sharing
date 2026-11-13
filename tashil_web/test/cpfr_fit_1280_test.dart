// Live-harness follow-up: Chrome 150% zoom fullscreen on the box is a
// 1280×800 CSS viewport with the 250dp DesktopSidebar, so the page
// content is 1030dp. Tests use that exact width, real Cairo, and
// live-scale (made-up) values. KPI cards must be 138px like Sell-Out;
// every tab table must fit with no horizontal scroll.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';
import 'package:tashil_web/features/navigation/presentation/desktop_sidebar.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/cpfr_fixtures.dart';
import 'support/real_fonts.dart';

/// Live review viewport: 1280×800 at 150% zoom, sidebar 250dp → 1030dp content.
const kLiveViewportWidth = 1280.0;
const kLiveSidebarWidth = 250.0;
const kSellOutKpiHeight = 138.0;

Future<void> _pumpLive(
  WidgetTester tester,
  Widget page, {
  double height = 4000,
}) async {
  tester.view.physicalSize = Size(kLiveViewportWidth, height);
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
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Row(children: [
          DesktopSidebar(
            selectedIndex: 9,
            onDestinationSelected: (_) {},
            activeTenant: 'adeco',
            onTenantChanged: (_) {},
          ),
          Expanded(child: page),
        ]),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

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

void _expectInContent(WidgetTester tester, Finder f, String what) {
  expect(f, findsWidgets, reason: what);
  final r = tester.getRect(f.first);
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$what $r');
  expect(r.right, lessThanOrEqualTo(kLiveViewportWidth + 0.5),
      reason: '$what $r');
}

void _expectOneLineUncut(WidgetTester tester, Finder f, String what) {
  expect(f, findsWidgets, reason: what);
  final p = tester.renderObject<RenderParagraph>(f.first);
  expect(p.didExceedMaxLines, isFalse, reason: '$what is ellipsized');
  final font = p.text.style?.fontSize ?? 24;
  expect(
    p.size.height,
    lessThanOrEqualTo(font * 1.35 + 8),
    reason:
        '$what wrapped to more than one line (h=${p.size.height}, font=$font)',
  );
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  testWidgets(
      'at live 1280+sidebar, CPFR KPI cards are 138px like Sell-Out; values and details stay one line',
      (tester) async {
    await _pumpLive(
      tester,
      SellOutExplorerScreen(apiClient: ApiClient(tenantId: 'tenant-adeco')),
    );
    final sellOutCard = find.byKey(const ValueKey('kpi_card_Net Sales (EGP)'));
    expect(sellOutCard, findsOneWidget);
    final sellOutH = tester.getSize(sellOutCard).height;
    expect(sellOutH, closeTo(kSellOutKpiHeight, 2.0),
        reason: 'Sell-Out reference height at live width is $sellOutH');

    await _pumpLive(
      tester,
      CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
    );
    expect(tester.takeException(), isNull);

    const cards = [
      'kpi_card_Sell-In',
      'kpi_card_Sell-Out',
      'kpi_card_Sell-Through Rate',
      'kpi_card_Inventory Gap',
    ];
    for (final key in cards) {
      final card = find.byKey(ValueKey(key));
      expect(card, findsOneWidget, reason: key);
      expect(tester.getSize(card).height, closeTo(kSellOutKpiHeight, 2.0),
          reason:
              '$key height ${tester.getSize(card).height} vs Sell-Out $sellOutH');
      final kpi = tester.widget<M3SummaryKpiCard>(card);
      expect(kpi.titleMaxLines, 1, reason: key);
      expect(kpi.subtitleMaxLines, 1, reason: key);
    }
    _expectOneLineUncut(tester, find.byKey(const ValueKey('kpi_value_Sell-In')),
        'Sell-In value');
    _expectOneLineUncut(tester,
        find.byKey(const ValueKey('kpi_subtitle_Sell-In')), 'Sell-In detail');
    _expectOneLineUncut(
        tester,
        find.byKey(const ValueKey('kpi_subtitle_Sell-Through Rate')),
        'turnover detail');

    await _openTab(tester, 'Suggested PO & Replenishment');
    expect(
      tester
          .getSize(find.byKey(const ValueKey('kpi_card_Urgent replenishment')))
          .height,
      closeTo(kSellOutKpiHeight, 2.0),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('kpi_card_Overstock'))).height,
      closeTo(kSellOutKpiHeight, 2.0),
    );

    await _openTab(tester, 'Demand Forecasting & Promos (EXP)');
    expect(
      tester
          .getSize(find.byKey(const ValueKey('kpi_card_W1+W2 actual')))
          .height,
      closeTo(kSellOutKpiHeight, 2.0),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('kpi_card_Promotions'))).height,
      closeTo(kSellOutKpiHeight, 2.0),
    );
  });

  testWidgets(
      'at live 1280+sidebar, every CPFR tab table fits with no horizontal scroll',
      (tester) async {
    await _pumpLive(
      tester,
      CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
    );
    expect(tester.takeException(), isNull);

    final recon = find.byKey(const ValueKey('cpfr_reconciliation_table'));
    expect(recon, findsOneWidget);
    expect(recon.evaluate().first.widget, isA<TableScrollContainer>());
    expect(_hScrollExtent(tester, recon), lessThanOrEqualTo(2.0),
        reason: 'reconciliation still scrolls at live 1280');
    _expectInContent(
        tester, find.byKey(const ValueKey('cpfr_recon_month_name_1')), 'month');
    _expectInContent(
        tester, find.byKey(const ValueKey('cpfr_recon_str_exp_1')), 'STR/EXP');

    await _openTab(tester, 'Suggested PO & Replenishment');
    final po = find.byKey(const ValueKey('cpfr_po_table'));
    expect(po, findsOneWidget);
    expect(_hScrollExtent(tester, po), lessThanOrEqualTo(2.0),
        reason: 'PO table still scrolls at live 1280');
    _expectInContent(
        tester, find.byKey(const ValueKey('cpfr_po_sku_name')), 'PO item');
    // Item and stock status visible together.
    _expectInContent(tester, find.text('نفاد عاجل'), 'PO stock status');

    await _openTab(tester, 'Demand Forecasting & Promos (EXP)');
    final forecast = find.byKey(const ValueKey('cpfr_forecast_table'));
    expect(forecast, findsOneWidget);
    expect(_hScrollExtent(tester, forecast), lessThanOrEqualTo(2.0),
        reason: 'forecast table still scrolls at live 1280');
    final returns = find.byKey(const ValueKey('cpfr_returns_table'));
    expect(returns, findsOneWidget);
    expect(_hScrollExtent(tester, returns), lessThanOrEqualTo(2.0),
        reason: 'returns table still scrolls at live 1280');

    await _openTab(tester, 'أداء فريق المبيعات وهيكل الحسابات');
    final reps = find.byKey(const ValueKey('cpfr_rep_table'));
    expect(reps, findsOneWidget);
    expect(_hScrollExtent(tester, reps), lessThanOrEqualTo(2.0),
        reason: 'reps table still scrolls at live 1280');
    _expectInContent(
        tester, find.byKey(const ValueKey('cpfr_rep_name')), 'rep name');
  });

  testWidgets(
      'at live 1280+sidebar and at 1024, the tab number is a badge and does not sit mid-label',
      (tester) async {
    await _pumpLive(
      tester,
      CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
    );
    expect(tester.takeException(), isNull);
    for (var i = 1; i <= 4; i++) {
      expect(find.byKey(ValueKey('cpfr_tab_badge_$i')), findsOneWidget);
      expect(find.byKey(ValueKey('cpfr_tab_label_$i')), findsOneWidget);
    }
    final label =
        tester.widget<Text>(find.byKey(const ValueKey('cpfr_tab_label_3')));
    expect(label.data, 'Demand Forecasting & Promos (EXP)');
    expect(find.text('3. Demand Forecasting & Promos (EXP)'), findsNothing);
    expect(find.textContaining('Forecasting & 3'), findsNothing);
    final badgeBox =
        tester.getRect(find.byKey(const ValueKey('cpfr_tab_badge_3')));
    final labelBox =
        tester.getRect(find.byKey(const ValueKey('cpfr_tab_label_3')));
    expect(
      badgeBox.overlaps(labelBox),
      isFalse,
      reason: 'badge $badgeBox must sit beside the label $labelBox',
    );

    tester.view.physicalSize = const Size(1024, 4000);
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
          child: Scaffold(
            body: CPFRDashboardScreen(apiClient: RichCPFRApiClient()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('cpfr_tab_badge_3')), findsOneWidget);
    expect(find.textContaining('Forecasting & 3'), findsNothing);
    final badge1024 =
        tester.getRect(find.byKey(const ValueKey('cpfr_tab_badge_3')));
    final label1024 =
        tester.getRect(find.byKey(const ValueKey('cpfr_tab_label_3')));
    expect(
      badge1024.overlaps(label1024),
      isFalse,
      reason: 'at 1024 badge $badge1024 overlaps label $label1024',
    );
  });
}

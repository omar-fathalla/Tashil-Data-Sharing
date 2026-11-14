// Trade Marketing & ROI full pass: KPI cards = Sell-Out (shared card and
// grid), tables fit 1280-with-sidebar (≈1024 content) with no horizontal
// scroll and wrap ≤3 lines, «—» + «لا توجد بيانات للعام السابق» without
// last-year data, Arabic plurals. Real Cairo font; made-up fixtures.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/widgets/m3_button.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';
import 'package:tashil_web/features/trade_marketing/domain/roi_lift.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

import 'support/live_viewport.dart';
import 'support/real_fonts.dart';
import 'support/tm_fixture.dart';

Future<void> _pump(WidgetTester tester, double width, Widget page) async {
  tester.view.physicalSize = Size(width, 4000);
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
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Widget _tm({bool withLastYear = true}) => TradeMarketingRoiScreen(
    apiClient: ApiClient(),
    repository: TmLiveScaleRepo(withLastYear: withLastYear));

const _kpiKeys = ['tm_kpi_spend', 'tm_kpi_mom', 'tm_kpi_yoy', 'tm_kpi_romi'];

void _expectNoClippedText(WidgetTester tester, Finder scope) {
  for (final e in find
      .descendant(of: scope, matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
  }
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

double _hScrollExtent(WidgetTester tester) {
  final s = find.descendant(
      of: find.byType(TableScrollContainer),
      matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection != AxisDirection.down));
  expect(s, findsWidgets);
  return tester.state<ScrollableState>(s.first).position.maxScrollExtent;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in const [1280.0, 1024.0]) {
    testWidgets('KPI cards are the shared Sell-Out card, same height @$width',
        (tester) async {
      await _pump(tester, width, SellOutExplorerScreen(apiClient: ApiClient()));
      await tester.pumpAndSettle();
      final ref = tester
          .getSize(find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')));
      await _pump(tester, width, _tm());
      expect(tester.takeException(), isNull);
      for (final k in _kpiKeys) {
        final card = find.byKey(ValueKey(k));
        expect(tester.widget(card), isA<M3SummaryKpiCard>());
        final size = tester.getSize(card);
        expect(size.height, closeTo(ref.height, 0.5),
            reason: '$k $size vs Sell-Out $ref');
        expect(size.width, closeTo(ref.width, 0.5));
        _expectNoClippedText(tester, card);
        // Value on one line (headlineSmall 24 → 32dp line).
        final v = tester.getSize(find.byKey(ValueKey('${k}_value')));
        expect(v.height, 32.0, reason: '$k value wraps');
      }
      expect(find.text('49.52${CurrencyFormatter.scaleJoiner}M ج.م'), findsOneWidget);
      expect(find.textContaining('180 نشاطًا'), findsOneWidget);
    });
  }

  testWidgets('no last-year data: «—» + «لا توجد بيانات للعام السابق»',
      (tester) async {
    await _pump(tester, 1024, _tm(withLastYear: false));
    final value = tester.widget<Text>(
        find.byKey(const ValueKey('tm_kpi_yoy_value')));
    expect(value.data, '—');
    final detail = tester.widget<Text>(
        find.byKey(const ValueKey('tm_kpi_yoy_detail')));
    expect(detail.data, 'لا توجد بيانات للعام السابق');
    // Matrix YoY cells: «—» with the description under it, no chip.
    expect(find.text('لا توجد بيانات للعام السابق'), findsWidgets);
    expect(find.textContaining('% YoY'), findsNothing);
  });

  testWidgets(
      'matrix + ledger fit 1024 content with no horizontal scroll; '
      'long text wraps ≤3 lines', (tester) async {
    await _pump(tester, 1024, _tm());
    expect(find.byKey(const ValueKey('tm_matrix_table')), findsOneWidget);
    expect(_hScrollExtent(tester), 0.0, reason: 'matrix scrolls');
    expect(find.text('يمين'), findsNothing);
    _expectNoClippedText(
        tester, find.byKey(const ValueKey('tm_matrix_table')));

    await _tab(tester, 'Campaigns & Expense Ledger');
    expect(find.byKey(const ValueKey('tm_ledger_table')), findsOneWidget);
    expect(_hScrollExtent(tester), 0.0, reason: 'ledger scrolls');
    expect(find.text('يمين'), findsNothing);
    // The long campaign title is shown wrapped (≤3 lines), not cut to 1.
    final title = find.text(tmLongCampaignTitle).first;
    final p = tester.renderObject<RenderParagraph>(find
        .descendant(of: title, matching: find.byType(RichText))
        .first);
    final lines = p.size.height / (p.text.style?.fontSize ?? 14);
    expect(lines, greaterThan(1.5), reason: 'title is not wrapped');
    expect(tester.widget<Text>(title).maxLines, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category cards: equal-height grid, nothing clipped',
      (tester) async {
    await _pump(tester, 1024, _tm());
    await _tab(tester, 'Activity & Brand Analytics');
    expect(find.byKey(const ValueKey('tm_category_grid')), findsOneWidget);
    final hs = find
        .byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('tm_cat_') &&
            !(w.key as ValueKey<String>).value.startsWith('tm_cat_value_'))
        .evaluate()
        .map((e) => tester.getSize(find.byWidget(e.widget)).height)
        .toSet();
    expect(hs.length, 1, reason: 'unequal heights $hs');
    _expectNoClippedText(
        tester, find.byKey(const ValueKey('tm_category_grid')));
  });

  test('Arabic plural for activities', () {
    expect(tmActivitiesCount(1), 'نشاط واحد');
    expect(tmActivitiesCount(2), 'نشاطان');
    expect(tmActivitiesCount(5), '5 أنشطة');
    expect(tmActivitiesCount(30), '30 نشاطًا');
    expect(tmActivitiesCount(300), '300 نشاط');
  });

  testWidgets(
      'header, tabs and KPI cards stay inside 1280-with-sidebar content',
      (tester) async {
    await _pump(tester, kLiveContentWidth, _tm());
    expect(tester.takeException(), isNull);
    final header = find.byType(M3PageHeader);
    expect(header, findsOneWidget);
    expect(tester.getSize(header).width,
        lessThanOrEqualTo(kLiveContentWidth + 0.5));
    final romi = tester.getRect(find.byKey(const ValueKey('tm_kpi_romi')));
    expect(romi.right, lessThanOrEqualTo(kLiveContentWidth + 0.5));
    expect(romi.left, greaterThanOrEqualTo(-0.5));
    final spend = tester.getRect(find.byKey(const ValueKey('tm_kpi_spend')));
    expect(spend.left, greaterThanOrEqualTo(-0.5));
    expect(find.text('Trade Marketing & Promo ROI'), findsOneWidget);
    expect(find.text('Activity & Brand Analytics'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);
  });

  testWidgets('ROMI method tooltip appears on card hover', (tester) async {
    await _pump(tester, kLiveContentWidth, _tm());
    final tooltip = tester.widget<Tooltip>(find
        .descendant(
          of: find.byKey(const ValueKey('tm_kpi_romi')),
          matching: find.byType(Tooltip),
        )
        .first);
    expect(tooltip.message, kRoiLiftMethodExplainerAr);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('tm_kpi_romi'))));
    addTearDown(gesture.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('العائد = الزيادة عن المبيعات المتوقعة'),
        findsWidgets);
  });

  testWidgets('ROI simulator dialog stays inside a 1280 viewport',
      (tester) async {
    await _pump(tester, kLiveViewportWidth, _tm());
    await tester.ensureVisible(find.byKey(const ValueKey('btn_roi_simulator')));
    await tester.tap(find.byKey(const ValueKey('btn_roi_simulator')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final rect = tester.getRect(dialog);
    expect(rect.left, greaterThanOrEqualTo(-0.5),
        reason: 'dialog clipped on the start: $rect');
    expect(rect.right, lessThanOrEqualTo(kLiveViewportWidth + 0.5),
        reason: 'dialog clipped on the end: $rect');
    expect(find.text('محاكي العائد التسويقي الذكي'), findsOneWidget);
  });
}

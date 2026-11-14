// Product Master: Sell-Out M3 treatment — live 1280+250dp sidebar, Cairo,
// live-scale values, and the Noto Sans Symbols 2 fallback used for ▲▼.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_equal_height_grid.dart';
import 'package:tashil_web/core/widgets/m3_responsive_tab_bar.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_toolbar_button.dart';
import 'package:tashil_web/core/widgets/m3_wrap_text.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/live_viewport.dart';
import 'support/product_master_m3_support.dart';
import 'support/text_visibility.dart';

class _KpiMetrics {
  _KpiMetrics(this.size, this.padding, this.iconSize, this.fonts, this.weights);
  final Size size;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final List<double?> fonts;
  final List<FontWeight?> weights;
  @override
  String toString() =>
      'size=$size padding=$padding icon=$iconSize fonts=$fonts weights=$weights';
}

_KpiMetrics _kpi(WidgetTester tester, Finder card) {
  final texts = find.descendant(of: card, matching: find.byType(Text));
  final styles = [
    for (final e in texts.evaluate())
      (find
              .descendant(
                  of: find.byWidget(e.widget), matching: find.byType(RichText))
              .evaluate()
              .first
              .widget as RichText)
          .text
          .style,
  ];
  return _KpiMetrics(
    tester.getSize(card),
    tester
        .widget<Container>(
            find.descendant(of: card, matching: find.byType(Container)).first)
        .padding,
    tester
        .widget<Icon>(
            find.descendant(of: card, matching: find.byType(Icon)).first)
        .size,
    [for (final st in styles) st?.fontSize],
    [for (final st in styles) st?.fontWeight],
  );
}

double? _horizontalExtent(WidgetTester tester) {
  final table = find.byType(TableScrollContainer);
  if (table.evaluate().isEmpty) return null;
  final hScroll = find.descendant(
    of: table.first,
    matching: find.byWidgetPredicate((w) =>
        w is Scrollable &&
        (w.axisDirection == AxisDirection.left ||
            w.axisDirection == AxisDirection.right)),
  );
  if (hScroll.evaluate().isEmpty) return 0;
  return tester.state<ScrollableState>(hScroll.first).position.maxScrollExtent;
}

Finder _pmCards() => find.byWidgetPredicate((w) =>
    w is M3SummaryKpiCard &&
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('pm_kpi_card_'));

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadProductMasterFonts);
  setUp(AppCache.clear);

  testWidgets(
      'live 1280 shell: KPI height matches Sell-Out 138, typography, no h-scroll',
      (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 2400,
      withSidebar: true,
      page: SellOutExplorerScreen(apiClient: ApiClient()),
    );
    final ref = _kpi(
      tester,
      find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')),
    );

    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 2400,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    final cards = _pmCards();
    expect(cards, findsNWidgets(5));
    final pmGrid = tester.widget<M3EqualHeightGrid>(
        find.byKey(const ValueKey('product_master_kpi_grid')));
    expect(pmGrid.columns, 3,
        reason: '5 KPI cards fill evenly as 3+2 (not a lonely 4+1)');
    final cardYs = [
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy
    ];
    expect(cardYs[0], closeTo(cardYs[1], 1.0));
    expect(cardYs[0], closeTo(cardYs[2], 1.0));
    expect(cardYs[3], closeTo(cardYs[4], 1.0));
    expect(cardYs[3], greaterThan(cardYs[0] + 100),
        reason: '2nd row holds cards 4–5 (3+2 even fill)');
    expect(find.text('إجمالي الأصناف'), findsWidgets);
    expect(find.text('أصناف العروض'), findsWidgets);
    expect(find.text('الباركودات الفريدة'), findsWidgets);
    expect(find.text('التغطية بالسلاسل'), findsWidgets);
    expect(find.text('إجمالي الأصناف المسجلة بالكارتة'), findsNothing);
    expect(find.text('الباركودات الفريدة وسعة الكرتونة'), findsNothing);

    for (final e in cards.evaluate()) {
      final m = _kpi(tester, find.byWidget(e.widget));
      final why = 'live-shell ${e.widget.key}: $m\nsell-out: $ref';
      expect(m.padding, ref.padding, reason: why);
      expect(m.iconSize, ref.iconSize, reason: why);
      expect(m.iconSize, M3SummaryKpiStyle.iconSize, reason: why);
      expect(m.padding, M3SummaryKpiStyle.padding, reason: why);
      expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
      expect(m.size.height, closeTo(138.0, 1.0), reason: why);
    }

    expect(find.textContaining('كلوريل أبيض مركز'), findsWidgets);
    expect(_horizontalExtent(tester), lessThanOrEqualTo(2.0),
        reason: 'catalog still scrolls horizontally');

    final button =
        find.byKey(const ValueKey('product_master_export_csv_btn'));
    expect(button, findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('تصدير Excel (CSV)')),
        findsOneWidget);
    final material =
        find.descendant(of: button, matching: find.byType(Material)).first;
    expect(
        tester.getSize(material).height, closeTo(M3ToolbarButton.height, 0.5));
    expect(tester.widget<Material>(material).shape, isA<StadiumBorder>());

    expect(find.textContaining('البادئة'), findsWidgets);
    expect(find.textContaining('العلامة'), findsWidgets);
    expect(find.text('بحث بكود الصنف أو الباركود أو الاسم'), findsWidgets);

    // Sell-Out / TM symmetry: responsive tabs + short M3 chips.
    expect(find.byKey(const ValueKey('product_master_tabs')), findsOneWidget);
    expect(find.byType(M3ResponsiveTabBar<int>), findsOneWidget);
    expect(find.byType(M3ChipSurface), findsWidgets);
    expect(find.text('مسحوب'), findsWidgets);
    expect(find.text('غير مسحوب'), findsWidgets);
    expect(find.textContaining('تغير السعر'), findsOneWidget);
    expect(find.textContaining('زاد ↑'), findsOneWidget);

    // Catalog name wrap ≤3 (Sell-Out / TM hard rule).
    final nameWraps = tester
        .widgetList<M3WrapText>(find.byType(M3WrapText))
        .where((w) => w.text.contains('كلوريل أبيض مركز'));
    expect(nameWraps, isNotEmpty);
    expect(nameWraps.every((w) => w.maxLines >= 3), isTrue);
  });

  testWidgets('1024+sidebar: KPI height 138, no horizontal scroll, no overflow',
      (tester) async {
    await pumpProductMaster(
      tester,
      width: 1024,
      height: 2400,
      withSidebar: true,
      page: SellOutExplorerScreen(apiClient: ApiClient()),
    );
    final ref = _kpi(
      tester,
      find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')),
    );
    final errors = await pumpProductMaster(
      tester,
      width: 1024,
      height: 2400,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));
    final cards = _pmCards();
    expect(cards, findsNWidgets(5));
    for (final e in cards.evaluate()) {
      final m = _kpi(tester, find.byWidget(e.widget));
      final why = '1024 ${e.widget.key}: $m\nsell-out: $ref';
      expect(m.padding, ref.padding, reason: why);
      expect(m.iconSize, ref.iconSize, reason: why);
      expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
      expect(m.size.height, closeTo(138.0, 1.0), reason: why);
    }
    expect(_horizontalExtent(tester), lessThanOrEqualTo(2.0),
        reason: 'catalog still scrolls horizontally at 1024');
    expect(find.textContaining('كلوريل أبيض مركز'), findsWidgets);
  });

  testWidgets(
      'calculator output cards match Sell-Out 138 at the live 1280 shell',
      (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 3600,
      withSidebar: true,
      page: SellOutExplorerScreen(apiClient: ApiClient()),
    );
    final ref = _kpi(
      tester,
      find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')),
    );

    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 3600,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    await tester.tap(find.textContaining('حاسبة الطلبيات والخصومات والهامش'));
    await tester.pumpAndSettle();

    final cards = find.byWidgetPredicate((w) =>
        w is M3SummaryKpiCard &&
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('pm_calc_card_'));
    expect(cards, findsNWidgets(6));
    expect(find.byKey(const ValueKey('pm_calc_result_grid')), findsOneWidget);

    for (final e in cards.evaluate()) {
      final m = _kpi(tester, find.byWidget(e.widget));
      final why = 'calc ${e.widget.key}: $m\nsell-out: $ref';
      expect(m.padding, ref.padding, reason: why);
      expect(m.iconSize, ref.iconSize, reason: why);
      expect(m.iconSize, M3SummaryKpiStyle.iconSize, reason: why);
      expect(m.padding, M3SummaryKpiStyle.padding, reason: why);
      expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
      expect(m.size.height, closeTo(138.0, 1.0), reason: why);
    }

    // Short on-card titles (full phrase lives in titleTooltip) so the
    // 138 Sell-Out KPI height budget stays one line.
    for (final title in [
      'إجمالي الوحدات',
      'القيمة قبل الضريبة',
      'ضريبة القيمة المضافة',
      'الخصومات التجارية',
      'صافي الفاتورة',
      'هامش ربح السلسلة',
    ]) {
      final card = cards
          .evaluate()
          .map((e) => e.widget)
          .cast<M3SummaryKpiCard>()
          .firstWhere(
            (c) => c.title == title,
            orElse: () => throw StateError('missing calc card $title'),
          );
      expect(
        labelFullyVisible(
          tester,
          title,
          scope: find.byWidget(card),
          minMaxLines: 1,
        ),
        isTrue,
        reason: 'calculator title "$title" must sit fully inside the 138 card',
      );
    }
  });

  testWidgets(
      'calculator margin shows «—» when shelf price is missing, not fake 0.0%',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 3600,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    await tester.tap(find.textContaining('حاسبة الطلبيات والخصومات والهامش'));
    await tester.pumpAndSettle();

    final shelfField = find.widgetWithText(
      TextField,
      'سعر بيع السلسلة للمستهلك (Shelf EGP)',
    );
    expect(shelfField, findsOneWidget);
    await tester.enterText(shelfField, '0');
    await tester.pumpAndSettle();

    final marginCard = tester.widget<M3SummaryKpiCard>(
      find.byKey(const ValueKey('pm_calc_card_margin')),
    );
    expect(marginCard.value, '—');
    expect(marginCard.subtitle, contains('أدخل سعر بيع السلسلة'));
    expect(find.textContaining('0.0%'), findsNothing);
  });
}

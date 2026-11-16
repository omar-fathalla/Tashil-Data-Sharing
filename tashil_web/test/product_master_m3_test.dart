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
import 'package:tashil_web/core/widgets/m3_wrap_text.dart';
import 'package:tashil_web/core/widgets/table_scroll_container.dart';
import 'package:tashil_web/features/product_master/data/chain_discount_repository.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/live_viewport.dart';
import 'support/product_master_m3_support.dart';

class _MemoryChainRepository extends ChainDiscountRepository {
  _MemoryChainRepository(super.api);
  List<ChainDiscountProfileModel> _saved = const [];

  @override
  Future<List<ChainDiscountProfileModel>> load() async => _saved;

  @override
  Future<List<ChainDiscountProfileModel>> save(
      List<ChainDiscountProfileModel> profiles) async {
    _saved = profiles;
    return profiles;
  }
}

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
    // Incomplete last row is stretched — no empty third slot.
    final gridWidth =
        tester.getSize(find.byKey(const ValueKey('product_master_kpi_grid')))
            .width;
    final row1 = [
      for (final e in cards.evaluate().skip(3))
        tester.getSize(find.byWidget(e.widget)).width
    ];
    expect(row1, hasLength(2));
    expect(row1[0], closeTo(row1[1], 1.0));
    expect(row1[0] + row1[1] + pmGrid.spacing, closeTo(gridWidth, 2.0),
        reason: 'last-row cards share the full grid width');
    final row0W = tester.getSize(find.byWidget(cards.evaluate().first.widget)).width;
    expect(row1[0], greaterThan(row0W + 10),
        reason: 'stretched last-row cards are wider than 1/3 columns');
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

    // Sell-Out / Errors / OOS symmetry: M3PageHeader + tonal M3ButtonGroup.
    expect(find.byKey(const ValueKey('product_master_page_header')),
        findsOneWidget);
    expect(find.text('Product Master & Price List'), findsOneWidget);
    expect(find.text('كارتة الأصناف والأسعار'), findsOneWidget);
    final button =
        find.byKey(const ValueKey('product_master_export_csv_btn'));
    expect(button, findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('تصدير Excel (CSV)')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('product_master_upload_btn')),
        findsOneWidget);

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
      'order-economics tab is a chain terms table: no SKU picker, no simulator cards',
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

    expect(find.byKey(const ValueKey('chain_discount_profiles_card')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chain_discount_add_btn')), findsOneWidget);
    // The single-SKU simulator is gone.
    expect(find.byKey(const ValueKey('pm_calc_result_grid')), findsNothing);
    expect(find.byKey(const ValueKey('calc_chain_dropdown')), findsNothing);
    expect(find.byKey(const ValueKey('product_master_export_order_csv_btn')),
        findsNothing);
    expect(find.textContaining('اختر الصنف'), findsNothing);
    expect(find.textContaining('سعر بيع السلسلة للمستهلك'), findsNothing);
    expect(find.textContaining('عدد الكراتين'), findsNothing);
  });

  testWidgets(
      'chain terms: add a chain (VAT / invoice / extra), see it in the table, edit it by tapping the row',
      (tester) async {
    final api = liveScaleProductMasterClient();
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 3600,
      withSidebar: true,
      apiClient: api,
      page: ProductMasterScreen(
          apiClient: api, chainRepository: _MemoryChainRepository(api)),
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));
    await tester.tap(find.textContaining('حاسبة الطلبيات والخصومات والهامش'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    // Defaults are prefilled: VAT 14, invoice 10, extra 0.
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chain_discount_vat_field')))
            .controller!
            .text,
        '14');
    await tester.enterText(
        find.byKey(const ValueKey('chain_discount_chain_field')), 'm3-chain');
    await tester.enterText(
        find.byKey(const ValueKey('chain_discount_vat_field')), '5');
    await tester.enterText(
        find.byKey(const ValueKey('chain_discount_invoice_field')), '12');
    await tester.enterText(
        find.byKey(const ValueKey('chain_discount_additional_field')), '20');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('chain_terms_row_m3-chain'));
    expect(row, findsOneWidget);
    for (final col in ['المؤسسة / السلسلة', 'الضريبة', 'خصم الفاتورة', 'الخصم الإضافي', 'آخر تحديث']) {
      expect(find.text(col), findsOneWidget, reason: col);
    }
    expect(find.text('5%'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('chain_discount_vat_field')), '8.5');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(find.text('8.50%'), findsOneWidget);
  });

  bool onScreen(WidgetTester tester, Finder f, {double width = 1280}) {
    expect(f, findsWidgets);
    final box = tester.getRect(f.first);
    return box.left < width - 1 &&
        box.right > 1 &&
        box.top < 8000 &&
        box.bottom > 0;
  }

  testWidgets(
      'catalog tonal surface + per-row type strip visible at 1280/1920',
      (tester) async {
    for (final width in [1280.0, 1920.0]) {
      final errors = await pumpProductMaster(
        tester,
        width: width,
        height: 2400,
        withSidebar: width <= 1280,
      );
      expect(errors, isEmpty,
          reason: errors.map((e) => e.exception).join('\n'));

      final surface = find.byKey(const ValueKey('pm_catalog_tonal_surface'));
      expect(surface, findsOneWidget, reason: 'tonal surface @ $width');
      expect(onScreen(tester, surface, width: width), isTrue,
          reason: 'tonal surface on screen @ $width');

      final table = find.byKey(const ValueKey('pm_catalog_table'));
      expect(table, findsOneWidget, reason: 'catalog table @ $width');
      final dt = tester.widget<DataTable>(table);
      expect(dt.dataRowMinHeight, greaterThanOrEqualTo(72.0),
          reason: 'chip + description row budget @ $width');
      for (final (i, c) in dt.columns.indexed) {
        expect(c.headingRowAlignment, MainAxisAlignment.center,
            reason: 'column $i centered @ $width');
      }

      final strip =
          find.byKey(const ValueKey('pm_row_type_strip_FGCL-0550-0001'));
      expect(strip, findsOneWidget, reason: 'row type strip @ $width');
      expect(onScreen(tester, strip, width: width), isTrue,
          reason: 'row type strip on screen @ $width');
      final stripBox = tester.widget<DecoratedBox>(strip);
      final deco = stripBox.decoration as BoxDecoration;
      final border = deco.border! as BorderDirectional;
      expect(border.start.width, 4.0,
          reason: '4dp per-type tonal strip @ $width');
      expect(border.start.color.a, greaterThan(0.0),
          reason: 'strip colour visible @ $width');

      final rowChip =
          find.byKey(const ValueKey('pm_row_type_chip_FGCL-0550-0001'));
      expect(rowChip, findsOneWidget, reason: 'row type chip @ $width');
      final chipText = tester.widget<Text>(
          find.descendant(of: rowChip, matching: find.byType(Text)).first);
      expect(chipText.data, 'عادي');
      expect(chipText.maxLines, 1);

      // Short chip + description underneath (مسحوب + units / فرصة توزيع).
      expect(find.descendant(of: table, matching: find.text('مسحوب')),
          findsWidgets);
      expect(find.descendant(of: table, matching: find.textContaining('وحدة')),
          findsWidgets);
      expect(
          find.descendant(of: table, matching: find.text('فرصة توزيع')),
          findsWidgets);

      // Official name wrap ≤3 (text snapshot of long live-scale name).
      final nameWraps = tester
          .widgetList<M3WrapText>(find.byType(M3WrapText))
          .where((w) => w.text.contains('كلوريل أبيض مركز'));
      expect(nameWraps, isNotEmpty);
      expect(nameWraps.every((w) => w.maxLines >= 3), isTrue);
      expect(nameWraps.every((w) => w.textAlign == TextAlign.center), isTrue);
    }
  });

  testWidgets(
      'empty catalog KPIs show «—» + note, never fake 0% / 0.0 averages',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 2400,
      withSidebar: true,
      apiClient: liveScaleProductMasterClient(emptyCatalog: true),
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    for (final key in [
      'pm_kpi_card_Total Registered',
      'pm_kpi_card_Regular Catalog',
      'pm_kpi_card_Promos',
      'pm_kpi_card_Unique Barcodes',
      'pm_kpi_card_Chain Coverage',
    ]) {
      final card =
          tester.widget<M3SummaryKpiCard>(find.byKey(ValueKey(key)));
      expect(card.value, '—', reason: key);
      expect(card.textValue, isTrue, reason: key);
      expect(card.subtitle, isNot(contains('0.0')), reason: key);
      expect(card.subtitle, isNot(contains('تمثل 0%')), reason: key);
    }
    expect(find.text('لا توجد أصناف في الكارتة'), findsOneWidget);
    expect(find.textContaining('0.0%'), findsNothing);
  });
}

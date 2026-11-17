// Product Master M3 layout at the live 1280+250dp sidebar shell: title, then
// fixed primary tabs (SKU card first), one toolbar row per tab, and a catalog
// table that fits without horizontal scroll (merged barcode/code cell,
// sticky header, column-visibility menu).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/storage/session_storage.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/features/product_master/data/chain_discount_repository.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';
import 'package:tashil_web/features/product_master/presentation/widgets/pm_catalog_table.dart';

import 'helpers/m3_dropdown_tester.dart';
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

  @override
  Future<List<KnownChain>> loadKnownChains() async => const [
        KnownChain(key: 'm3-chain', displayName: 'm3-chain'),
      ];
}

/// First load times out exactly like the live bug, the retry succeeds.
class _TimeoutOnceChainRepository extends ChainDiscountRepository {
  _TimeoutOnceChainRepository(super.api);
  int loads = 0;

  @override
  Future<List<ChainDiscountProfileModel>> load() async {
    loads++;
    if (loads == 1) {
      throw ChainDiscountException(friendlyChainDiscountError(TimeoutException(
          'Future not completed', const Duration(seconds: 10))));
    }
    return const [
      ChainDiscountProfileModel(
          chain: 'kazyon', invoiceDiscountPct: 12, additionalDiscountPct: 0),
    ];
  }

  @override
  Future<List<ChainDiscountProfileModel>> save(
          List<ChainDiscountProfileModel> profiles) async =>
      profiles;
}

/// The first save gets no answer and cannot be verified; the retry succeeds.
class _UnverifiedOnceChainRepository extends ChainDiscountRepository {
  _UnverifiedOnceChainRepository(super.api);
  int saves = 0;
  List<ChainDiscountProfileModel> sent = const [];

  @override
  Future<List<ChainDiscountProfileModel>> load() async => const [];

  @override
  Future<List<ChainDiscountProfileModel>> save(
      List<ChainDiscountProfileModel> profiles) async {
    saves++;
    sent = profiles;
    if (saves == 1) throw const ChainDiscountSaveUnverifiedException();
    return profiles;
  }

  @override
  Future<List<KnownChain>> loadKnownChains() async => const [
        KnownChain(key: 'm3-chain', displayName: 'm3-chain'),
      ];
}

Finder _header(String label) => find.descendant(
    of: find.byKey(const ValueKey('pm_catalog_header')),
    matching: find.text(label));

void main() {
  ignoreGoogleFontLoadErrors();
  setUpAll(loadProductMasterFonts);
  setUp(AppCache.clear);

  testWidgets(
      'live 1280 shell: title, then fixed primary tabs (SKU card first), no header actions / KPIs / chips',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    final header = find.byKey(const ValueKey('product_master_page_header'));
    expect(header, findsOneWidget);
    expect(find.text('كارتة الأصناف والأسعار'), findsOneWidget);
    expect(
        find.descendant(of: header, matching: find.byType(ButtonStyleButton)),
        findsNothing,
        reason: 'nothing remains in the page header');
    expect(find.byWidgetPredicate((w) => w is M3SummaryKpiCard), findsNothing);
    for (final gone in [
      'إجمالي الأصناف',
      'أصناف البيع العادي',
      'أصناف العروض',
      'الباركودات الفريدة',
      'التغطية بالسلاسل',
      'تحديث 01-09-2026',
      'خصم فاتورة 10%',
      'ضريبة 14%',
      'شيتات الأسعار (',
      'File Sheets',
      'رفع تحديث شيت الأسعار',
      'إضافة صنف جديد',
      'تصدير Excel (CSV)',
    ]) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }

    final tabBar = tester
        .widget<TabBar>(find.byKey(const ValueKey('product_master_tabs')));
    expect(tabBar.isScrollable, isFalse);
    expect(tabBar.dividerHeight, 1.0);
    final catalog = find.byKey(const ValueKey('pm_tab_catalog'));
    final sheets = find.byKey(const ValueKey('pm_tab_sheets'));
    final calc = find.byKey(const ValueKey('pm_tab_calculator'));
    expect(find.text('كارتة الأصناف (3)'), findsOneWidget);
    expect(find.text('الشيتات المرفوعة (1)'), findsOneWidget);
    expect(find.text('حاسبة الطلبيات'), findsOneWidget);
    expect(find.textContaining('والخصومات'), findsNothing);
    for (final t in [catalog, sheets, calc]) {
      expect(tester.getSize(t).height, 48.0);
    }
    // RTL: first tab is the rightmost.
    expect(
        tester.getCenter(catalog).dx, greaterThan(tester.getCenter(sheets).dx));
    expect(tester.getCenter(sheets).dx, greaterThan(tester.getCenter(calc).dx));
    // Directly under the title (16dp gap).
    final tabsTop =
        tester.getTopLeft(find.byKey(const ValueKey('product_master_tabs'))).dy;
    expect(tabsTop - tester.getBottomLeft(header).dy, closeTo(16.0, 0.5));

    final selected = tester
        .widget<TabBar>(find.byKey(const ValueKey('product_master_tabs')))
        .controller!
        .index;
    expect(selected, 0, reason: 'SKU card is the default tab');
  });

  testWidgets(
      'catalog toolbar: one 40dp row — search at start, chips, actions at end (filled «إضافة صنف»)',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    final toolbar = find.byKey(const ValueKey('pm_catalog_toolbar'));
    expect(tester.getSize(toolbar).height, 40.0);
    final search = find.byKey(const ValueKey('product_master_search_input'));
    final chips = find.byKey(const ValueKey('pm_catalog_filter_chips'));
    final add = find.byKey(const ValueKey('product_master_add_sku_btn'));
    final csv = find.byKey(const ValueKey('product_master_export_csv_btn'));
    expect(tester.widget(add), isA<ButtonStyleButton>());
    expect(find.descendant(of: toolbar, matching: find.byType(FilledButton)),
        findsOneWidget,
        reason: 'one filled button per tab');
    expect(tester.widget<IconButton>(csv).tooltip, 'تصدير CSV');
    // RTL order: search (right) → chips → actions (left).
    expect(tester.getRect(search).left,
        greaterThanOrEqualTo(tester.getRect(chips).right - 1));
    expect(tester.getRect(chips).left,
        greaterThanOrEqualTo(tester.getRect(csv).right - 1));
    expect(tester.getRect(csv).left, greaterThan(tester.getRect(add).right));
    // Toolbar sits 16dp below the tab divider.
    final tabsBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('product_master_tabs')))
        .dy;
    expect(tester.getTopLeft(toolbar).dy - tabsBottom, closeTo(16.0, 0.5));

    for (final label in [
      'البادئة',
      'العلامة',
      'النوع',
      'التعبئة',
      'السحب',
      'تغير السعر'
    ]) {
      expect(find.descendant(of: chips, matching: find.text(label)),
          findsOneWidget,
          reason: label);
    }

    // Filter via chip menu.
    await tester.tap(find.byKey(const ValueKey('pm_filter_item_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pm_filter_item_type_عرض')));
    await tester.pumpAndSettle();
    expect(find.text('النوع: عرض'), findsOneWidget);
    expect(find.byKey(const ValueKey('pm_catalog_row_PRCL-0102-0015')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pm_catalog_row_FGCL-0550-0001')),
        findsNothing);

    // Rare actions live in the overflow menu.
    await tester.tap(find.byKey(const ValueKey('pm_catalog_more_btn')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('product_master_reset_filters_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pm_catalog_row_FGCL-0550-0001')),
        findsOneWidget);
  });

  testWidgets(
      'barcode + code share one cell: barcode on top (bodyMedium), code below (bodySmall), LTR, tabular, never truncated',
      (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
    );
    final cell = find.byKey(const ValueKey('pm_barcode_cell_FGCL-0550-0001'));
    expect(cell, findsOneWidget);
    final barcode =
        find.descendant(of: cell, matching: find.text('6221133000181'));
    final code =
        find.descendant(of: cell, matching: find.text('FGCL-0550-0001'));
    expect(barcode, findsOneWidget);
    expect(code, findsOneWidget);
    expect(tester.getTopLeft(code).dy,
        greaterThan(tester.getBottomLeft(barcode).dy),
        reason: 'code sits below the barcode');
    final theme = Theme.of(tester.element(cell));
    final bStyle = tester.widget<Text>(barcode).style!;
    final cStyle = tester.widget<Text>(code).style!;
    expect(bStyle.fontSize, theme.textTheme.bodyMedium!.fontSize);
    expect(bStyle.color, theme.colorScheme.onSurface);
    expect(cStyle.fontSize, theme.textTheme.bodySmall!.fontSize);
    expect(cStyle.color, theme.colorScheme.onSurfaceVariant);
    expect(bStyle.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(Directionality.of(tester.element(barcode)), TextDirection.ltr);
    // Not scaled down / not clipped at 1280.
    expect(tester.getRect(barcode).width,
        closeTo(tester.getSize(barcode).width, 0.5));
    expect(
        tester
            .renderObject<RenderParagraph>(
                find.descendant(of: barcode, matching: find.byType(RichText)))
            .didExceedMaxLines,
        isFalse);
    // Single semantics label for the cell.
    expect(find.bySemanticsLabel('باركود 6221133000181، كود FGCL-0550-0001'),
        findsOneWidget);
    // Old separate columns are gone.
    expect(_header('كود الصنف'), findsNothing);
    expect(_header('الباركود'), findsNothing);
    expect(_header('الباركود / الكود'), findsOneWidget);

    await tester.tap(cell);
    await tester.pump();
    expect(find.text('تم النسخ'), findsOneWidget);
  });

  for (final (width, sidebar) in [
    (1280.0, true),
    (1024.0, true),
    (1920.0, false)
  ]) {
    testWidgets(
        'catalog table fits ${width.toInt()}${sidebar ? '+sidebar' : ''}: no horizontal scroll, no overflow, 56dp header/rows',
        (tester) async {
      final errors = await pumpProductMaster(
        tester,
        width: width,
        height: 1600,
        withSidebar: sidebar,
      );
      expect(errors, isEmpty,
          reason: errors.map((e) => e.exception).join('\n'));

      final surface = find.byKey(const ValueKey('pm_catalog_tonal_surface'));
      final headerRow = find.byKey(const ValueKey('pm_catalog_header'));
      final contentLeft = sidebar ? 0.0 : 0.0;
      final contentRight = width - (sidebar ? kLiveSidebarWidth : 0.0);
      final hr = tester.getRect(headerRow);
      expect(hr.left, greaterThanOrEqualTo(contentLeft + 24.0 - 0.5));
      expect(hr.right, lessThanOrEqualTo(contentRight - 24.0 + 0.5));
      expect(tester.getSize(headerRow).height, 57.0,
          reason: '56dp header + 1dp divider');
      expect(
          find.descendant(
              of: surface,
              matching: find.byWidgetPredicate((w) =>
                  w is Scrollable &&
                  (w.axisDirection == AxisDirection.left ||
                      w.axisDirection == AxisDirection.right))),
          findsNothing,
          reason: 'the table never scrolls horizontally');
      expect(surface, findsOneWidget);

      final row = find.byKey(const ValueKey('pm_catalog_row_FGCL-0550-0001'));
      expect(tester.getSize(row).height, inInclusiveRange(56.0, 58.0));
      expect(tester.getRect(row).right, lessThanOrEqualTo(hr.right + 0.5));

      // Essentials always visible.
      for (final label in [
        'الباركود / الكود',
        'اسم الصنف',
        'السعر ش.ض',
        'النوع / السحب'
      ]) {
        expect(_header(label), findsOneWidget, reason: '$label @ $width');
      }
      final name = tester
          .getSize(find.byKey(const ValueKey('pm_row_name_FGCL-0550-0001')));
      expect(name.width, greaterThanOrEqualTo(240.0 - 16.0 - 0.5),
          reason: 'name column ≥ 240dp @ $width');
      final nameText = tester.widget<Text>(
          find.byKey(const ValueKey('pm_row_name_FGCL-0550-0001')));
      expect(nameText.maxLines, 2);
      expect(nameText.overflow, TextOverflow.ellipsis);

      if (width >= 1920) {
        for (final label in [
          'سعر الوحدة',
          'سعر الكرتونة',
          'التعبئة',
          'العلامة / الفئة'
        ]) {
          expect(_header(label), findsOneWidget, reason: '$label @ $width');
        }
      }
    });
  }

  testWidgets('header stays pinned while the catalog scrolls', (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 500,
      withSidebar: true,
    );
    final scroll = find.byType(CustomScrollView);
    await tester.drag(scroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('pm_catalog_header'));
    expect(header, findsOneWidget);
    expect(tester.getTopLeft(header).dy, greaterThanOrEqualTo(0.0));
    expect(tester.getTopLeft(header).dy, lessThan(500.0));
  });

  testWidgets(
      'column menu brings back hidden columns (carton price) without overflow',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
    );
    expect(errors, isEmpty);
    expect(_header('سعر الكرتونة'), findsNothing,
        reason: 'lowest-priority columns hidden at 1280 so the table fits');

    await tester.tap(find.byKey(const ValueKey('pm_columns_menu_btn')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('pm_column_toggle_carton')).first);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_header('سعر الكرتونة'), findsOneWidget);
    final hr = tester.getRect(find.byKey(const ValueKey('pm_catalog_header')));
    expect(hr.right, lessThanOrEqualTo(kLiveContentWidth - 24.0 + 0.5));
    expect(tester.takeException(), isNull);
  });

  test('column fitting: autoVisible by priority, widths fill the table', () {
    const live = 982.0;
    final auto = PmCatalogTableStyle.autoVisible(live);
    expect(auto, containsAll([PmCatalogColumn.net, PmCatalogColumn.brand]));
    expect(auto, isNot(contains(PmCatalogColumn.carton)));
    final visible = PmCatalogTableStyle.visibleColumns(live, const {});
    final w = PmCatalogTableStyle.widths(live, visible);
    final total = w.values.fold<double>(0, (a, b) => a + b) +
        PmCatalogTableStyle.outerExtra;
    expect(total, closeTo(live, 0.01));
    expect(w[PmCatalogColumn.barcode], 156.0);
    expect(w[PmCatalogColumn.name], greaterThanOrEqualTo(240.0));

    // Forcing every column on still fits; the barcode never shrinks.
    final all = PmCatalogTableStyle.visibleColumns(live, {
      for (final c in PmCatalogTableStyle.columns) c.id: true,
    });
    final wAll = PmCatalogTableStyle.widths(live, all);
    expect(
        wAll.values.fold<double>(0, (a, b) => a + b) +
            PmCatalogTableStyle.outerExtra,
        closeTo(live, 0.01));
    expect(wAll[PmCatalogColumn.barcode], 156.0);
  });

  testWidgets(
      'order calculator tab is a chain terms table: no SKU picker, no simulator cards',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 3600,
      withSidebar: true,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));

    await tester.tap(find.text('حاسبة الطلبيات'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chain_discount_profiles_card')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('chain_discount_add_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('pm_calc_result_grid')), findsNothing);
    expect(find.byKey(const ValueKey('calc_chain_dropdown')), findsNothing);
    expect(find.textContaining('اختر الصنف'), findsNothing);
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
    await tester.tap(find.text('حاسبة الطلبيات'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('chain_discount_vat_field')))
            .controller!
            .text,
        '14');
    expect(find.byKey(const ValueKey('chain_discount_chain_field')), findsNothing);
    await selectM3Option(
      tester,
      find.byKey(const ValueKey('chain_discount_chain_dropdown')),
      'm3-chain',
    );
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

  testWidgets(
      'chain terms load timeout: friendly Arabic error + retry, never the raw TimeoutException or «no chains»',
      (tester) async {
    final api = liveScaleProductMasterClient();
    final repo = _TimeoutOnceChainRepository(api);
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
      apiClient: api,
      page: ProductMasterScreen(apiClient: api, chainRepository: repo),
    );
    await tester.tap(find.text('حاسبة الطلبيات'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chain_discount_error_banner')),
        findsOneWidget);
    expect(find.text('تعذّر تحميل إعدادات السلاسل'), findsOneWidget);
    expect(find.text(kChainDiscountTimeoutMessage), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
    expect(find.textContaining('Future not completed'), findsNothing);
    expect(find.textContaining('لا توجد سلاسل مضافة'), findsNothing);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(repo.loads, 2);
    expect(find.byKey(const ValueKey('chain_discount_error_banner')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('chain_terms_row_kazyon')), findsOneWidget);
  });

  testWidgets(
      'chain terms save that cannot be confirmed: «تعذّر التأكد من الحفظ» + retry re-sends the same list',
      (tester) async {
    final api = liveScaleProductMasterClient();
    final repo = _UnverifiedOnceChainRepository(api);
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 3600,
      withSidebar: true,
      apiClient: api,
      page: ProductMasterScreen(apiClient: api, chainRepository: repo),
    );
    await tester.tap(find.text('حاسبة الطلبيات'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    await selectM3Option(
      tester,
      find.byKey(const ValueKey('chain_discount_chain_dropdown')),
      'm3-chain',
    );
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chain_discount_error_banner')),
        findsOneWidget);
    expect(find.text(kChainDiscountSaveUnverifiedTitle), findsOneWidget);
    expect(find.text('تعذّر حفظ إعدادات السلاسل'), findsNothing);
    expect(find.text(kChainDiscountSaveUnverifiedMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('chain_terms_row_m3-chain')), findsNothing,
        reason: 'an unconfirmed save does not touch the table');

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(repo.saves, 2);
    expect(repo.sent.single.chain, 'm3-chain');
    expect(find.byKey(const ValueKey('chain_discount_error_banner')),
        findsNothing);
    expect(find.byKey(const ValueKey('chain_terms_row_m3-chain')),
        findsOneWidget);
  });

  testWidgets('selected tab persists in the ?tab= URL query', (tester) async {
    SessionStorage.replaceBrowserQueryParam('tab', 'calculator');
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
      resetTabQuery: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_profiles_card')),
        findsOneWidget,
        reason: 'refresh with ?tab=calculator reopens the calculator');

    await tester.tap(find.byKey(const ValueKey('pm_tab_sheets')));
    await tester.pumpAndSettle();
    expect(SessionStorage.browserQueryParam('tab'), 'sheets');
    expect(find.byKey(const ValueKey('product_master_upload_btn')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pm_tab_catalog')));
    await tester.pumpAndSettle();
    expect(SessionStorage.browserQueryParam('tab'), isNull,
        reason: 'the default tab keeps a clean URL');
  });

  testWidgets(
      'uploaded-sheets tab: one toolbar row with the single filled upload button',
      (tester) async {
    await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
    );
    await tester.tap(find.byKey(const ValueKey('pm_tab_sheets')));
    await tester.pumpAndSettle();
    final toolbar = find.byKey(const ValueKey('pm_sheets_toolbar'));
    expect(tester.getSize(toolbar).height, 40.0);
    expect(find.descendant(of: toolbar, matching: find.byType(FilledButton)),
        findsOneWidget);
    expect(find.text('رفع شيت أسعار'), findsOneWidget);
    expect(
        find.textContaining(
            'adeco_product_master_2026_09_01_canonical_official_price_list'),
        findsOneWidget);
  });

  testWidgets('empty catalog: empty table state, no fake KPI numbers',
      (tester) async {
    final errors = await pumpProductMaster(
      tester,
      width: kLiveViewportWidth,
      height: 1600,
      withSidebar: true,
      apiClient: liveScaleProductMasterClient(emptyCatalog: true),
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.exception).join('\n'));
    expect(find.text('لا توجد أصناف مطابقة لمعايير البحث الحالية'),
        findsOneWidget);
    expect(find.text('0 صنف'), findsOneWidget);
    expect(find.textContaining('0.0%'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is M3SummaryKpiCard), findsNothing);
  });
}

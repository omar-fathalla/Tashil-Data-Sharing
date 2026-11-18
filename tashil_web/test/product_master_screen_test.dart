import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/storage/session_storage.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';

import 'support/real_fonts.dart';

class _FakeProductMasterApiClient extends ApiClient {
  _FakeProductMasterApiClient() : super();

  final List<ArchivedExcelFileModel> archivedSheets = [
    const ArchivedExcelFileModel(
      id: 'pm-seed-2',
      tenantId: 'tenant-adeco',
      fileType: 'product_master',
      fileName: 'adeco_product_master_2026_09_01.xlsx',
      contentType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileSizeBytes: 54200,
      retailChain: 'product-master',
      chainNameAr: 'كارتة الأصناف والأسعار (Product Master)',
      chainNameEn: 'Product Master',
      targetYear: '2026',
      rowsIngested: 390,
      branchesCount: 0,
      totalRevenue: 0.0,
      uploadedAt: '2026-09-01T10:00:00Z',
    ),
    const ArchivedExcelFileModel(
      id: 'pm-seed-1',
      tenantId: 'tenant-adeco',
      fileType: 'product_master',
      fileName: 'adeco_product_master_2026_08_01.xlsx',
      contentType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileSizeBytes: 51200,
      retailChain: 'product-master',
      chainNameAr: 'كارتة الأصناف والأسعار (Product Master)',
      chainNameEn: 'Product Master',
      targetYear: '2026',
      rowsIngested: 389,
      branchesCount: 0,
      totalRevenue: 0.0,
      uploadedAt: '2026-08-01T10:00:00Z',
    ),
  ];

  bool sheet2Deleted = false;

  @override
  Future<ProductMasterSummaryModel> getProductMaster({
    String? search,
    String? brand,
    String? category,
    String? prefix,
    String? itemType,
    String? packaging,
    String? pullStatus,
    String? priceChange,
  }) async {
    return ProductMasterSummaryModel(
      tenantId: 'tenant-adeco',
      companyName: 'شركة الإسكندرية للمنظفات والكيماويات (ادكو - Adeco)',
      sheetDateLabel: sheet2Deleted ? 'تحديث 01-08-2026' : 'تحديث 01-09-2026',
      sourceFilename: sheet2Deleted
          ? 'adeco_product_master_2026_08_01.xlsx'
          : 'adeco_product_master_2026_09_01.xlsx',
      totalSkus: 389,
      regularSkusCount: 280,
      promoSkusCount: 109,
      uniqueBarcodesCount: 363,
      activeInChainsCount: 185,
      unpulledSkusCount: 204,
      priceIncreasedCount: sheet2Deleted ? 0 : 1,
      priceDecreasedCount: sheet2Deleted ? 0 : 1,
      priceUnchangedCount: sheet2Deleted ? 2 : 0,
      newSkusCount: sheet2Deleted ? 0 : 1,
      diffSummary: sheet2Deleted
          ? null
          : const ProductMasterDiffSummaryModel(
              comparedAgainstFile: 'adeco_product_master_2026_08_01.xlsx',
              newFileName: 'adeco_product_master_2026_09_01.xlsx',
              comparedAt: '2026-09-01T10:00:00Z',
              totalSkusCompared: 390,
              priceIncreasedCount: 1,
              priceDecreasedCount: 1,
              priceUnchangedCount: 387,
              newSkusCount: 1,
              avgPriceIncreasePct: 12.5,
              avgPriceDecreasePct: -8.3,
              topChangedItems: [
                ProductMasterDiffItemModel(
                  itemCode: 'FGCL-0550-0001',
                  officialName: 'كلوريل أبيض 1050 جم عبوة',
                  brand: 'كلوريل (Clorel)',
                  direction: 'up',
                  oldUnitPriceIncl: 16.00,
                  newUnitPriceIncl: 18.00,
                  oldCartonPriceIncl: 192.00,
                  newCartonPriceIncl: 216.00,
                  diffEgp: 2.00,
                  diffPct: 12.5,
                ),
                ProductMasterDiffItemModel(
                  itemCode: 'PRCL-0102-0015',
                  officialName: 'عرض فيبا توفير 3 لتر + 600 مل هدية شرنك',
                  brand: 'فيبا (Feba)',
                  direction: 'down',
                  oldUnitPriceIncl: 120.00,
                  newUnitPriceIncl: 110.00,
                  oldCartonPriceIncl: 720.00,
                  newCartonPriceIncl: 660.00,
                  diffEgp: -10.00,
                  diffPct: -8.3,
                ),
              ],
            ),
      avgUnitsPerCarton: 12.0,
      defaultDiscountPct: 10.0,
      availablePrefixes: const ['FGCL', 'FGDW', 'PRCL'],
      availableBrands: const ['كلوريل (Clorel)', 'فيبا (Feba)'],
      availablePackaging: const ['عبوة', 'جركن', 'شرنك'],
      items: [
        ProductMasterItemModel(
          serialNo: 1,
          itemCode: 'FGCL-0550-0001',
          itemCodePrefix: 'FGCL',
          erpPrefix: 'FGCL',
          departmentAr: 'قسم الكلور والمبيضات',
          officialName: 'كلوريل أبيض 1050 جم عبوة',
          barcode: '6221133000181',
          category: 'الكلور والمطهرات',
          brand: 'كلوريل (Clorel)',
          packagingType: 'عبوة',
          unitsPerCarton: 12,
          unitPriceExclVat: 15.79,
          vatRate: 0.14,
          unitPriceInclVat: sheet2Deleted ? 16.00 : 18.00,
          cartonPriceExclVat: 189.47,
          cartonPriceInclVat: sheet2Deleted ? 192.00 : 216.00,
          invoiceDiscountPct: 10.0,
          extraDiscountPct: 0.0,
          netUnitInvoiceCost: sheet2Deleted ? 14.40 : 16.20,
          netCartonInvoiceCost: sheet2Deleted ? 172.80 : 194.40,
          prevUnitPriceInclVat: sheet2Deleted ? 0.0 : 16.00,
          priceChangeDirection: sheet2Deleted ? 'same' : 'up',
          priceChangeDiffEgp: sheet2Deleted ? 0.0 : 2.00,
          priceChangePct: sheet2Deleted ? 0.0 : 12.5,
          itemType: 'عادي',
          isActiveInChains: true,
          totalPosUnitsSold: 4200,
          totalPosCartonsSold: 350,
          totalPosRevenue: 81900,
          avgRetailSellingPrice: 19.50,
          activeChains: const ['carrefour', 'fathalla'],
        ),
        ProductMasterItemModel(
          serialNo: 210,
          itemCode: 'PRCL-0102-0015',
          itemCodePrefix: 'PRCL',
          erpPrefix: 'PRCL',
          departmentAr: 'عروض الكلور والمبيضات',
          officialName: 'عرض فيبا توفير 3 لتر + 600 مل هدية شرنك',
          barcode: '6221133994121',
          category: 'منظفات الأطباق',
          brand: 'فيبا (Feba)',
          packagingType: 'شرنك',
          unitsPerCarton: 6,
          unitPriceExclVat: 96.49,
          vatRate: 0.14,
          unitPriceInclVat: sheet2Deleted ? 120.00 : 110.00,
          cartonPriceExclVat: 578.95,
          cartonPriceInclVat: sheet2Deleted ? 720.00 : 660.00,
          invoiceDiscountPct: 10.0,
          extraDiscountPct: 0.0,
          netUnitInvoiceCost: sheet2Deleted ? 108.00 : 99.00,
          netCartonInvoiceCost: sheet2Deleted ? 648.00 : 594.00,
          prevUnitPriceInclVat: sheet2Deleted ? 0.0 : 120.00,
          priceChangeDirection: sheet2Deleted ? 'same' : 'down',
          priceChangeDiffEgp: sheet2Deleted ? 0.0 : -10.00,
          priceChangePct: sheet2Deleted ? 0.0 : -8.3,
          itemType: 'عرض',
          isActiveInChains: false,
        ),
        if (!sheet2Deleted)
          const ProductMasterItemModel(
            serialNo: 390,
            itemCode: 'FGDW-0200-0099',
            itemCodePrefix: 'FGDW',
            erpPrefix: 'FGDW',
            departmentAr: 'قسم غسالات الأطباق',
            officialName: 'أقراص فيبا غسالات أطباق 30 قرص جديد',
            barcode: '6221133009999',
            category: 'منظفات الأطباق',
            brand: 'فيبا (Feba)',
            packagingType: 'عبوة',
            unitsPerCarton: 12,
            unitPriceExclVat: 131.58,
            vatRate: 0.14,
            unitPriceInclVat: 150.00,
            cartonPriceExclVat: 1578.95,
            cartonPriceInclVat: 1800.00,
            invoiceDiscountPct: 10.0,
            extraDiscountPct: 0.0,
            netUnitInvoiceCost: 135.00,
            netCartonInvoiceCost: 1620.00,
            priceChangeDirection: 'new',
            itemType: 'عادي',
            isActiveInChains: false,
          ),
      ],
    );
  }

  @override
  Future<UploadedFilesArchiveResponse> getUploadedFilesArchive({
    String? chain,
    String? year,
    String? searchQuery,
    String? targetTenant,
    String? fileType,
    bool forceRefresh = false,
  }) async {
    return UploadedFilesArchiveResponse(
      tenantId: 'tenant-adeco',
      totalCount: archivedSheets.length,
      chainCounts: {'product-master': archivedSheets.length},
      files: List.unmodifiable(archivedSheets),
    );
  }

  @override
  Future<bool> deleteArchivedFile(
    String archiveId, {
    String? targetTenant,
    String? fileName,
    bool isSellIn = false,
    bool isProductMaster = false,
  }) async {
    archivedSheets.removeWhere((f) => f.id == archiveId);
    if (archiveId == 'pm-seed-2') {
      sheet2Deleted = true;
    }
    return true;
  }
}

// The barcode/code cell carries one label: «باركود …، كود …».
Finder itemCode(String code) =>
    find.bySemanticsLabel(RegExp('كود ${RegExp.escape(code)}\$'));

void main() {

  setUpAll(loadRealCairoFont);
  setUp(() => SessionStorage.replaceBrowserQueryParam('tab', null));

  group('ProductMasterItemModel & ProductMasterSummaryModel JSON normalization', () {
    test('normalizes backend decimal discount ratios (0.10 -> 10.0%), price diffs, and preserves >1 percentages', () {
      final summary = ProductMasterSummaryModel.fromJson({
        'tenant_id': 'tenant-adeco',
        'total_skus': 389,
        'active_in_chains_count': 185,
        'unpulled_skus_count': 204,
        'price_increased_count': 12,
        'price_decreased_count': 3,
        'new_skus_count': 2,
        'default_discount_pct': 0.10,
        'diff_summary': {
          'compared_against_file': 'old.xlsx',
          'new_file_name': 'new.xlsx',
          'price_increased_count': 12,
          'price_decreased_count': 3,
          'new_skus_count': 2,
          'avg_price_increase_pct': 5.4,
          'top_changed_items': [
            {
              'item_code': 'FGGC-0600-0007',
              'official_name': 'ملمع زجاج جلاسى أزرق 600 مل بمسدس',
              'direction': 'up',
              'old_unit_price_incl': 25.0,
              'new_unit_price_incl': 28.0,
              'diff_egp': 3.0,
              'diff_pct': 12.0,
            }
          ],
        },
        'items': [
          {
            'serial_no': 1,
            'item_code': 'FGGC-0600-0007',
            'item_code_prefix': 'FGGC',
            'erp_prefix': 'FGGC',
            'department_ar': 'قسم منظفات الزجاج والأسطح',
            'official_name': 'ملمع زجاج جلاسى أزرق 600 مل بمسدس',
            'category': 'ملمع زجاج وكريستال',
            'brand': 'جلاسي (Glassy)',
            'invoice_discount_pct': 0.10,
            'extra_discount_pct': 0.05,
            'prev_unit_price_incl_vat': 25.0,
            'price_change_direction': 'up',
            'price_change_diff_egp': 3.0,
            'price_change_pct': 12.0,
            'is_active_in_chains': true,
            'total_pos_units_sold': 1200,
          }
        ],
      });

      expect(summary.defaultDiscountPct, closeTo(10.0, 0.001));
      expect(summary.activeInChainsCount, equals(185));
      expect(summary.unpulledSkusCount, equals(204));
      expect(summary.priceIncreasedCount, equals(12));
      expect(summary.priceDecreasedCount, equals(3));
      expect(summary.newSkusCount, equals(2));
      expect(summary.diffSummary, isNotNull);
      expect(summary.diffSummary!.topChangedItems.first.direction, equals('up'));
      expect(summary.items.first.invoiceDiscountPct, closeTo(10.0, 0.001));
      expect(summary.items.first.extraDiscountPct, closeTo(5.0, 0.001));
      expect(summary.items.first.priceChangeDirection, equals('up'));
      expect(summary.items.first.prevUnitPriceInclVat, closeTo(25.0, 0.001));
      expect(summary.items.first.priceChangePct, closeTo(12.0, 0.001));
      expect(summary.items.first.erpPrefix, equals('FGGC'));
      expect(summary.items.first.departmentAr, equals('قسم منظفات الزجاج والأسطح'));
      expect(summary.items.first.isActiveInChains, isTrue);
    });

    test('sets empty sourceFilename when total_skus is 0 and items is empty so no zombie seed bubble is synthesized', () {
      final emptySummary = ProductMasterSummaryModel.fromJson({
        'tenant_id': 'tenant-adeco',
        'total_skus': 0,
        'items': const [],
      });
      expect(emptySummary.totalSkus, equals(0));
      expect(emptySummary.sourceFilename, isEmpty);
    });
  });

  group('ApiClient.matchesProductSearch', () {
    test('matches exact itemCode, compact itemCode, prefix, FGSL phonetic alias, and barcode', () {
      expect(
        ApiClient.matchesProductSearch(
          'FGCL-0550-0001',
          itemCode: 'FGCL-0550-0001',
          barcode: '6221133000181',
          skuName: 'كلوريل أبيض 1050 جم عبوة',
        ),
        isTrue,
      );

      // Compact without hyphens
      expect(
        ApiClient.matchesProductSearch(
          'fgcl05500001',
          itemCode: 'FGCL-0550-0001',
          barcode: '6221133000181',
          skuName: 'كلوريل أبيض 1050 جم عبوة',
        ),
        isTrue,
      );

      // Phonetic alias FGSL -> FGCL / FGLC
      expect(
        ApiClient.matchesProductSearch(
          'FGSL-0550',
          itemCode: 'FGCL-0550-0001',
          barcode: '6221133000181',
          skuName: 'كلوريل أبيض 1050 جم عبوة',
        ),
        isTrue,
      );

      // Barcode search
      expect(
        ApiClient.matchesProductSearch(
          '6221133000181',
          itemCode: 'FGCL-0550-0001',
          barcode: '6221133000181',
          skuName: 'كلوريل أبيض 1050 جم عبوة',
        ),
        isTrue,
      );

      // Non-matching query
      expect(
        ApiClient.matchesProductSearch(
          '9999999999999',
          itemCode: 'FGCL-0550-0001',
          barcode: '6221133000181',
          skuName: 'كلوريل أبيض 1050 جم عبوة',
        ),
        isFalse,
      );
    });
  });

  testWidgets('ProductMasterScreen renders title + tabs (no header actions / KPIs), filters by Item Code / Barcode, and switches tabs',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = _FakeProductMasterApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductMasterScreen(apiClient: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Title only: no header actions, no KPI cards, no summary chips.
    final header = find.byKey(const ValueKey('product_master_page_header'));
    expect(header, findsOneWidget);
    expect(find.text('Product Master & Price List'), findsOneWidget);
    expect(find.text('كارتة الأصناف والأسعار'), findsOneWidget);
    expect(find.descendant(of: header, matching: find.byType(ButtonStyleButton)),
        findsNothing);
    for (final gone in [
      'التغطية بالسلاسل',
      'إجمالي الأصناف',
      'الباركودات الفريدة',
      'رفع تحديث شيت الأسعار',
      'إضافة صنف جديد',
      'تصدير Excel (CSV)',
      'File Sheets',
      'خصم فاتورة',
      'شيتات الأسعار (',
    ]) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
    expect(find.byKey(const ValueKey('product_master_tabs')), findsOneWidget);
    expect(find.text('مسحوب'), findsWidgets);
    expect(find.text('غير مسحوب'), findsWidgets);
    expect(itemCode('FGCL-0550-0001'), findsWidgets);
    expect(itemCode('PRCL-0102-0015'), findsWidgets);

    // Search by Item Code
    final searchInput = find.byKey(const ValueKey('product_master_search_input'));
    expect(searchInput, findsOneWidget);
    await tester.enterText(searchInput, 'PRCL-0102-0015');
    await tester.pumpAndSettle();

    expect(itemCode('PRCL-0102-0015'), findsWidgets);
    expect(itemCode('FGCL-0550-0001'), findsNothing);

    // Search by FGSL phonetic alias
    await tester.enterText(searchInput, 'FGSL-0550');
    await tester.pumpAndSettle();

    expect(itemCode('FGCL-0550-0001'), findsWidgets);
    expect(itemCode('PRCL-0102-0015'), findsNothing);

    // Switch to the order calculator tab (chain terms) and verify the per-chain table with its add action
    expect(find.textContaining('حاسبة الطلبيات والخصومات'), findsNothing);
    await tester.tap(find.text('حاسبة الطلبيات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_profiles_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('chain_discount_add_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('product_master_export_order_csv_btn')), findsNothing);
  });

  testWidgets(
      'ProductMasterScreen displays price change indicators, filters by price changes, opens Diff Summary modal, and manages File Sheets with rollback on delete',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = _FakeProductMasterApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductMasterScreen(apiClient: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify inline price change indicators next to product prices
    expect(
      find.byKey(const ValueKey('price_indicator_FGCL-0550-0001_up')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('price_indicator_PRCL-0102-0015_down')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('price_indicator_FGDW-0200-0099_new')),
      findsOneWidget,
    );

    // 2. Price-change filter chip menu (زاد السعر / انخفض السعر / أصناف جديدة)
    Future<void> pickPriceFilter(String key) async {
      await tester.tap(find.byKey(const ValueKey('pm_filter_price_change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    await pickPriceFilter('price_filter_up');
    expect(itemCode('FGCL-0550-0001'), findsWidgets);
    expect(itemCode('PRCL-0102-0015'), findsNothing);
    expect(itemCode('FGDW-0200-0099'), findsNothing);

    await pickPriceFilter('price_filter_down');
    expect(itemCode('PRCL-0102-0015'), findsWidgets);
    expect(itemCode('FGCL-0550-0001'), findsNothing);

    await pickPriceFilter('price_filter_new');
    expect(itemCode('FGDW-0200-0099'), findsWidgets);
    expect(itemCode('FGCL-0550-0001'), findsNothing);

    // Reset back to all
    await pickPriceFilter('price_filter_all');
    expect(itemCode('FGCL-0550-0001'), findsWidgets);
    expect(itemCode('PRCL-0102-0015'), findsWidgets);

    // 3. Open Diff Summary Modal (toolbar overflow menu) and click "عرض الأصناف المتغيرة فقط في الجدول"
    await tester.tap(find.byKey(const ValueKey('pm_catalog_more_btn')));
    await tester.pumpAndSettle();
    final diffBtn = find.byKey(const ValueKey('product_master_open_diff_summary_btn'));
    expect(diffBtn, findsOneWidget);
    await tester.tap(diffBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('ملخص مقارنة الشيت الجديد'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diff_dialog_filter_changed_btn')));
    await tester.pumpAndSettle();

    // 4. Uploaded-sheets tab: delete the latest sheet to trigger rollback
    await tester.tap(find.byKey(const ValueKey('pm_tab_sheets')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product_master_upload_btn')), findsOneWidget);
    expect(find.text('adeco_product_master_2026_09_01.xlsx'), findsWidgets);
    expect(find.text('adeco_product_master_2026_08_01.xlsx'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('archive_tab_delete_sheet_pm-seed-2')));
    await tester.pumpAndSettle();

    // Confirm deletion in confirmation dialog
    expect(find.textContaining('حذف شيت الأسعار وإلغاء تأثيراته'), findsOneWidget);
    await tester.tap(find.text('تأكيد الحذف واسترجاع الأسعار'));
    await tester.pumpAndSettle();

    // Rollback: sheet2Deleted is true, the 09-01 sheet is gone and new SKU FGDW-0200-0099 is gone
    expect(client.sheet2Deleted, isTrue);
    expect(find.text('adeco_product_master_2026_09_01.xlsx'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pm_tab_catalog')));
    await tester.pumpAndSettle();
    expect(itemCode('FGDW-0200-0099'), findsNothing);
  });
}

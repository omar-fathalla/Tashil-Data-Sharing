import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';

class _FakeProductMasterApiClient extends ApiClient {
  _FakeProductMasterApiClient() : super();

  @override
  Future<ProductMasterSummaryModel> getProductMaster({
    String? search,
    String? brand,
    String? category,
    String? prefix,
    String? itemType,
    String? packaging,
    String? pullStatus,
  }) async {
    return const ProductMasterSummaryModel(
      tenantId: 'tenant-adeco',
      companyName: 'شركة الإسكندرية للمنظفات والكيماويات (أدكو - Adeco)',
      sheetDateLabel: 'تحديث 01-08-2026',
      sourceFilename: 'adeco_product_master_2026_08_01.xlsx',
      totalSkus: 389,
      regularSkusCount: 280,
      promoSkusCount: 109,
      uniqueBarcodesCount: 363,
      activeInChainsCount: 185,
      unpulledSkusCount: 204,
      avgUnitsPerCarton: 12.0,
      defaultDiscountPct: 10.0,
      availablePrefixes: ['FGCL', 'FGDW', 'PRCL'],
      availableBrands: ['كلوريل (Clorel)', 'فيبا (Feba)'],
      availablePackaging: ['عبوة', 'جركن', 'شرنك'],
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
          unitPriceInclVat: 18.00,
          cartonPriceExclVat: 189.47,
          cartonPriceInclVat: 216.00,
          invoiceDiscountPct: 10.0,
          extraDiscountPct: 0.0,
          netUnitInvoiceCost: 16.20,
          netCartonInvoiceCost: 194.40,
          itemType: 'عادي',
          isActiveInChains: true,
          totalPosUnitsSold: 4200,
          totalPosCartonsSold: 350,
          totalPosRevenue: 81900,
          avgRetailSellingPrice: 19.50,
          activeChains: ['carrefour', 'fathalla'],
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
          unitPriceInclVat: 110.00,
          cartonPriceExclVat: 578.95,
          cartonPriceInclVat: 660.00,
          invoiceDiscountPct: 10.0,
          extraDiscountPct: 0.0,
          netUnitInvoiceCost: 99.00,
          netCartonInvoiceCost: 594.00,
          itemType: 'عرض',
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
  }) async {
    return const UploadedFilesArchiveResponse(
      tenantId: 'tenant-adeco',
      totalCount: 1,
      chainCounts: {'product-master': 1},
      files: [
        ArchivedExcelFileModel(
          id: 'pm-seed-1',
          tenantId: 'tenant-adeco',
          fileType: 'product_master',
          fileName: 'adeco_product_master_2026_08_01.xlsx',
          contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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
      ],
    );
  }
}

void main() {
  group('ProductMasterItemModel & ProductMasterSummaryModel JSON normalization', () {
    test('normalizes backend decimal discount ratios (0.10 -> 10.0%) and preserves >1 percentages', () {
      final summary = ProductMasterSummaryModel.fromJson({
        'tenant_id': 'tenant-adeco',
        'total_skus': 389,
        'active_in_chains_count': 185,
        'unpulled_skus_count': 204,
        'default_discount_pct': 0.10,
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
            'is_active_in_chains': true,
            'total_pos_units_sold': 1200,
          }
        ],
      });

      expect(summary.defaultDiscountPct, closeTo(10.0, 0.001));
      expect(summary.activeInChainsCount, equals(185));
      expect(summary.unpulledSkusCount, equals(204));
      expect(summary.items.first.invoiceDiscountPct, closeTo(10.0, 0.001));
      expect(summary.items.first.extraDiscountPct, closeTo(5.0, 0.001));
      expect(summary.items.first.erpPrefix, equals('FGGC'));
      expect(summary.items.first.departmentAr, equals('قسم منظفات الزجاج والأسطح'));
      expect(summary.items.first.isActiveInChains, isTrue);
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

  testWidgets('ProductMasterScreen renders KPIs, filters by Item Code / Barcode, and switches tabs',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
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

    // Verify header, 5th KPI card, and both SKUs are rendered
    expect(find.textContaining('كارتة الأصناف والأسعار المعتمدة'), findsOneWidget);
    expect(find.textContaining('التغطية والسحب بالسلاسل'), findsOneWidget);
    expect(find.text('FGCL-0550-0001'), findsWidgets);
    expect(find.text('PRCL-0102-0015'), findsWidgets);

    // Search by Item Code
    final searchInput = find.byKey(const ValueKey('product_master_search_input'));
    expect(searchInput, findsOneWidget);
    await tester.enterText(searchInput, 'PRCL-0102-0015');
    await tester.pumpAndSettle();

    expect(find.text('PRCL-0102-0015'), findsWidgets);
    expect(find.text('FGCL-0550-0001'), findsNothing);

    // Search by FGSL phonetic alias
    await tester.enterText(searchInput, 'FGSL-0550');
    await tester.pumpAndSettle();

    expect(find.text('FGCL-0550-0001'), findsWidgets);
    expect(find.text('PRCL-0102-0015'), findsNothing);

    // Switch to Tab 2 (Calculator) and verify Order CSV export button
    await tester.tap(find.textContaining('حاسبة الطلبيات والخصومات والهامش'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product_master_export_order_csv_btn')), findsOneWidget);
  });
}

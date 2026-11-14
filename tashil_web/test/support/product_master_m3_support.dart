import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/product_master/presentation/screens/product_master_screen.dart';

import 'live_viewport.dart';
import 'real_fonts.dart';

const ValueKey<String> kProductMasterShotRoot =
    ValueKey('product_master_shot_root');

/// Registers Cairo plus the Noto Sans Symbols 2 arrows the browser uses
/// as a fallback for ▲▼ (Cairo has no those glyphs).
Future<void> loadProductMasterFonts() async {
  await loadRealCairoFont();
  final cairo = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
  final cairoData = ByteData.view(Uint8List.fromList(cairo).buffer);
  const cairoAliases = [
    'Cairo-Regular',
    'Cairo-Medium',
    'Cairo-SemiBold',
    'Cairo-Bold',
    'Cairo-ExtraBold',
    'Cairo-Black',
    'Cairo-Light',
    'Cairo-ExtraLight',
  ];
  for (final family in cairoAliases) {
    await (FontLoader(family)..addFont(Future.value(cairoData))).load();
  }
  // NotoSansSymbols2 is already registered by loadRealCairoFont.
}

void ignoreGoogleFontLoadErrors() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final previous = reportTestException;
  reportTestException = (details, testDescription) {
    final s = '${details.exception}\n${details.exceptionAsString()}';
    if (s.contains('google_fonts') ||
        s.contains('Failed to load font') ||
        s.contains('allowRuntimeFetching')) {
      return;
    }
    previous(details, testDescription);
  };
}

FakeProductMasterApiClient liveScaleProductMasterClient({
  bool includeLongName = true,
}) =>
    FakeProductMasterApiClient(includeLongName: includeLongName);

class FakeProductMasterApiClient extends ApiClient {
  FakeProductMasterApiClient({this.includeLongName = true}) : super();

  final bool includeLongName;

  static const longOfficialName =
      'كلوريل أبيض مركز 1050 جم عبوة اقتصادية مع غطاء أمان للأطفال للتحقق من لف الاسم حتى ثلاثة أسطر دون قص';

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
    final items = <ProductMasterItemModel>[
      const ProductMasterItemModel(
        serialNo: 1,
        itemCode: 'FGCL-0550-0001',
        itemCodePrefix: 'FGCL',
        officialName: 'كلوريل أبيض 1050 جم عبوة',
        barcode: '6221133000181',
        category: 'الكلور والمطهرات (Chlorine & Disinfectants)',
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
        totalPosUnitsSold: 12500,
      ),
      const ProductMasterItemModel(
        serialNo: 2,
        itemCode: 'PRCL-0102-0015',
        itemCodePrefix: 'PRCL',
        officialName: 'عرض فيبا توفير 3 لتر + 600 مل هدية شرنك',
        barcode: '6221133000999',
        category: 'سائل الأطباق',
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
        totalPosUnitsSold: 0,
      ),
      const ProductMasterItemModel(
        serialNo: 3,
        itemCode: 'FGDW-0200-0099',
        itemCodePrefix: 'FGDW',
        officialName: 'أقراص فيبا غسالات أطباق 30 قرص جديد',
        barcode: '6221133000777',
        category: 'غسالات الأطباق',
        brand: 'فيبا (Feba)',
        packagingType: 'عبوة',
        unitsPerCarton: 8,
        unitPriceExclVat: 70.18,
        vatRate: 0.14,
        unitPriceInclVat: 80.00,
        cartonPriceExclVat: 561.40,
        cartonPriceInclVat: 640.00,
        invoiceDiscountPct: 10.0,
        extraDiscountPct: 0.0,
        netUnitInvoiceCost: 72.00,
        netCartonInvoiceCost: 576.00,
        itemType: 'عادي',
        isActiveInChains: true,
        totalPosUnitsSold: 4200,
      ),
    ];
    if (includeLongName) {
      items[0] = items[0].copyWith(officialName: longOfficialName);
    }
    var filtered = List<ProductMasterItemModel>.from(items);
    final q = search?.trim() ?? '';
    if (q.isNotEmpty) {
      filtered = filtered
          .where((i) =>
              i.itemCode.contains(q) ||
              i.barcode.contains(q) ||
              i.officialName.contains(q) ||
              i.brand.contains(q))
          .toList();
    }
    return ProductMasterSummaryModel(
      tenantId: 'tenant-adeco',
      companyName: 'شركة الإسكندرية للمنظفات والكيماويات (أدكو - Adeco)',
      sheetDateLabel: 'تحديث 01-09-2026',
      sourceFilename: 'adeco_product_master_2026_09_01.xlsx',
      totalSkus: 389,
      regularSkusCount: 280,
      promoSkusCount: 109,
      uniqueBarcodesCount: 363,
      activeInChainsCount: 185,
      unpulledSkusCount: 204,
      priceIncreasedCount: 1,
      priceDecreasedCount: 1,
      priceUnchangedCount: 387,
      newSkusCount: 1,
      avgUnitsPerCarton: 12.0,
      defaultDiscountPct: 10.0,
      availablePrefixes: const ['FGCL', 'FGDW', 'PRCL'],
      availableBrands: const ['كلوريل (Clorel)', 'فيبا (Feba)'],
      availablePackaging: const ['عبوة', 'جركن', 'شرنك'],
      items: filtered,
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
    const files = [
      ArchivedExcelFileModel(
        id: 'pm-seed-2',
        tenantId: 'tenant-adeco',
        fileType: 'product_master',
        fileName:
            'adeco_product_master_2026_09_01_canonical_official_price_list.xlsx',
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
    ];
    return const UploadedFilesArchiveResponse(
      tenantId: 'tenant-adeco',
      totalCount: 1,
      chainCounts: {'product-master': 1},
      files: files,
    );
  }
}

Future<List<FlutterErrorDetails>> pumpProductMaster(
  WidgetTester tester, {
  double width = kLiveViewportWidth,
  double height = 2400,
  bool withSidebar = false,
  ApiClient? apiClient,
  Widget? page,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) errors.add(d);
  };
  addTearDown(() => FlutterError.onError = old);

  final body = page ??
      ProductMasterScreen(
        apiClient: apiClient ?? liveScaleProductMasterClient(),
      );
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
        body: RepaintBoundary(
          key: kProductMasterShotRoot,
          child: withSidebar
              ? Row(
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      width: kLiveSidebarWidth,
                      child: ColoredBox(color: Color(0xFF1A1C19)),
                    ),
                    Expanded(child: body),
                  ],
                )
              : body,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  FlutterError.onError = old;
  return errors;
}

Future<void> saveProductMasterShot(WidgetTester tester, String path) async {
  final finder = find.byKey(kProductMasterShotRoot);
  expect(finder, findsOneWidget);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

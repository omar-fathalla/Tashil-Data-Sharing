import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/pricing_compliance/presentation/screens/pricing_compliance_screen.dart';

import 'support/real_fonts.dart';

/// Made-up fixture names long enough to need 3 lines at 1024–1280dp.
const kLongSkuName =
    'زيت عباد الشمس النقي الممتاز عبوة بلاستيك اقتصادية كبيرة الحجم مع غطاء محكم ضد التسريب';
const kLongStoreName =
    'فرع الإسكندرية محطة الرمل بجوار سوق الجملة التجاري الجديد الدور الأرضي';
const kLongCategory = 'منظفات أرضيات متعددة الأغراض ومعطرات جو';

class PricingShotApiClient extends ApiClient {
  PricingShotApiClient()
      : super(tenantId: 'tenant-adeco', allowMockFallback: false);

  @override
  Future<List<PricingComplianceItem>> getPricingCompliance({
    String? chain,
    String? category,
    bool? violationOnly,
    bool? promoOnly,
    int? year,
    int? month,
    int? limit,
    int? offset,
    String? search,
  }) async {
    final items = <PricingComplianceItem>[
      PricingComplianceItem(
        itemCode: 'FGCL-0550-0001',
        skuName: kLongSkuName,
        barcode: '6221133011903',
        category: kLongCategory,
        retailerChain: 'fathalla',
        storeName: kLongStoreName,
        actualPrice: 89.5,
        recommendedPrice: 100.0,
        factoryUnitCost: 42.0,
        retailerMarginPct: 18.5,
        unitsPerCarton: 12,
        priceDeltaPct: -10.5,
        violationType: 'under_cutting',
        isPromoActive: true,
        promoUpliftPct: 18.5,
      ),
      PricingComplianceItem(
        itemCode: 'FGSL-1200-0002',
        skuName: 'صابون سائل للأطباق برائحة الليمون المركز عبوة اقتصادية كبيرة',
        barcode: '6221133011904',
        category: 'صابون سائل اطباق',
        retailerChain: 'gomla',
        storeName: 'جملة ماركت سيدي بشر الفرع الرئيسي',
        actualPrice: 100.0,
        recommendedPrice: 100.0,
        factoryUnitCost: 40.0,
        retailerMarginPct: 22.0,
        unitsPerCarton: 24,
        priceDeltaPct: 0.0,
        violationType: 'compliant',
        isPromoActive: false,
        promoUpliftPct: 0.0,
      ),
      PricingComplianceItem(
        itemCode: 'FGCL-0800-0003',
        skuName: 'كلور ملابس ملونة لطيف على الأقمشة الرقيقة',
        barcode: '6221133011905',
        category: 'كلور ألوان',
        retailerChain: 'carrefour',
        storeName: 'كارفور سيتي سنتر الإسكندرية',
        actualPrice: 115.0,
        recommendedPrice: 100.0,
        factoryUnitCost: 38.0,
        retailerMarginPct: -5.0,
        unitsPerCarton: 12,
        priceDeltaPct: 15.0,
        violationType: 'price_gouging',
        isPromoActive: true,
        promoUpliftPct: 9.25,
      ),
    ];
    lastPricingComplianceMeta = PricingCompliancePageResult(
      items: items,
      totalCount: items.length,
      summaryTotalCount: items.length,
      limit: limit ?? items.length,
      offset: offset ?? 0,
      compliantCount: 1,
      violationCount: 2,
      complianceRatePct: 33.3,
      avgPromoUpliftPct: 13.9,
      availableCategories: const [
        kLongCategory,
        'منظفات سجاد ومفروشات',
        'مسحوق غسالات اطباق',
        'صابون سائل اطباق',
        'كلور ألوان',
        'منظف ارضيات',
      ],
      monthlyElasticity: const [
        MonthlyPriceElasticityPoint(
          monthKey: '2026-01',
          monthLabel: 'يناير 2026',
          averagePrice: 92.0,
          recommendedPrice: 100.0,
          totalRevenue: 120000,
          totalUnits: 1400,
          priceChangePct: -2.0,
          revenueChangePct: 6.5,
          unitsChangePct: 8.0,
          elasticityVerdict: 'انخفاض السعر صاحبه نمو في الإيرادات',
        ),
        MonthlyPriceElasticityPoint(
          monthKey: '2026-02',
          monthLabel: 'فبراير 2026',
          averagePrice: 95.0,
          recommendedPrice: 100.0,
          totalRevenue: 110000,
          totalUnits: 1200,
          priceChangePct: 3.3,
          revenueChangePct: -8.3,
          unitsChangePct: -14.3,
          elasticityVerdict: 'رفع السعر خفض الإيرادات',
        ),
      ],
      elasticitySummary: const PriceElasticitySummaryModel(
        overallVerdict:
            'الانخفاض المحدود في متوسط السعر قابله نمو أوضح في الإيرادات خلال الفترة',
        avgPriceCurrent: 93.5,
        avgPriceBaseline: 92.0,
        netPriceChangePct: 1.6,
        netRevenueGrowthPct: 6.5,
      ),
    );
    return items;
  }
}

Future<void> pumpPricing(
  WidgetTester tester,
  Widget page, {
  double width = 1280,
  double height = 2800,
}) async {
  tester.view.physicalSize = Size(width, height);
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
        body: RepaintBoundary(
          key: const ValueKey('pricing_shot_root'),
          child: page,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> saveShot(WidgetTester tester, String path) async {
  final finder = find.byKey(const ValueKey('pricing_shot_root'));
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

void disableGoogleFontsFetch() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// [loadRealCairoFont] registers `Cairo` / `Cairo_regular`. GoogleFonts looks
/// up `Cairo-Regular`, `Cairo-Bold`, … — register those too so shots render
/// with the real family when runtime fetching is off.
Future<void> loadPricingFonts() async {
  await loadRealCairoFont();
  final bytes = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
  final data = ByteData.view(Uint8List.fromList(bytes).buffer);
  const families = [
    'Cairo-Regular',
    'Cairo-Medium',
    'Cairo-SemiBold',
    'Cairo-Bold',
    'Cairo-ExtraBold',
    'Cairo-Black',
    'Cairo-Light',
    'Cairo-ExtraLight',
  ];
  for (final family in families) {
    await (FontLoader(family)..addFont(Future.value(data))).load();
  }
}

/// GoogleFonts.cairoTextTheme() tries to fetch Cairo-Regular during tests.
/// Flutter's test binding blocks HTTP, so the async load throws. The bundled
/// Cairo family from [loadPricingFonts] still paints glyphs via the fallback.
void ignoreGoogleFontLoadErrors() {
  final previous = reportTestException;
  reportTestException = (details, testDescription) {
    final s = '${details.exception}\n${details.exceptionAsString()}';
    if (s.contains('google_fonts') ||
        s.contains('Failed to load font') ||
        s.contains('allowRuntimeFetching') ||
        s.contains('Cairo-Regular') ||
        s.contains('Cairo-')) {
      return;
    }
    previous(details, testDescription);
  };
}

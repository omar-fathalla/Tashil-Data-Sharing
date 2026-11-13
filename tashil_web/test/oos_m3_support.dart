import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';

import 'support/real_fonts.dart';

/// Made-up live-like names long enough to wrap, including the real-world
/// Fathalla branch prefix Mohamed reported on Returns.
const kLongSkuName =
    'فيبا سائل غسيل أطباق بالليمون المركز عبوة اقتصادية كبيرة الحجم مع مضخة معطرة للأواني الزجاجية والبلاستيك';
const kLongStoreName = 'عائلة فتح الله ماركت - مخزن الافوكادو';
const kLongStoreName2 =
    'عائلة فتح الله ماركت - دمنهور الفرع الرئيسي بجوار سوق الجملة التجاري الجديد';
const kLongBrand = 'فيبا / فيفا (Feba / Viva)';

class OosShotApiClient extends ApiClient {
  OosShotApiClient()
      : super(tenantId: 'tenant-adeco', allowMockFallback: false);

  @override
  Future<ExecutiveKPIsModel> getExecutiveKPIs({
    String period = 'MTD',
    String? startDate,
    String? endDate,
    String? chain,
  }) async {
    return ExecutiveKPIsModel(
      totalRevenue: 18450000,
      revenueGrowthPct: 12.4,
      totalUnitsSold: 842000,
      unitsGrowthPct: 8.1,
      activeStoresCount: 46,
      oosRatePct: 12.6,
      osaRatePct: 87.4,
      totalOOSIncidents: 243,
      estimatedLostRevenue: 2430000,
      currency: 'EGP',
      reportingPeriod: '2026-10',
      chainShares: const [],
      dailyTrends: const [],
    );
  }

  @override
  Future<OOSMonitorResponseModel> getOOSMonitorReport() async {
    final alerts = [
      OOSAlertModel(
        alertId: 'oos_fix_001',
        retailerChain: 'fathalla',
        storeId: 'fat_avocado_wh',
        storeName: kLongStoreName,
        itemCode: 'FGCL-0550-0001',
        barcode: '6221133011903',
        skuName: kLongSkuName,
        brand: kLongBrand,
        category: 'منظفات منزلية متعددة الأغراض',
        estimatedLostDailyCost: 243000.0,
        consecutiveDaysOOS: 14,
        severity: 'critical',
      ),
      OOSAlertModel(
        alertId: 'oos_fix_002',
        retailerChain: 'fathalla',
        storeId: 'fat_damanhur_main',
        storeName: kLongStoreName2,
        itemCode: 'FGSL-1200-0002',
        barcode: '6221133011904',
        skuName:
            'ديفا مسحوق غسيل أوتوماتيك مركز للأقمشة الملونة والبيضاء عبوة 8 كجم اقتصادية',
        brand: 'ديفا (Diva)',
        category: 'مساحيق غسيل',
        estimatedLostDailyCost: 187500.0,
        consecutiveDaysOOS: 9,
        severity: 'high',
      ),
      OOSAlertModel(
        alertId: 'oos_fix_003',
        retailerChain: 'fathalla',
        storeId: 'fat_avocado_wh',
        storeName: kLongStoreName,
        itemCode: 'FGNV-0800-0003',
        barcode: '6221133011905',
        skuName: 'نيفيا كريم ترطيب عميق للبشرة الجافة 250 مل',
        brand: 'نيفيا (Nivea)',
        category: 'عناية شخصية',
        estimatedLostDailyCost: 96500.0,
        consecutiveDaysOOS: 6,
        severity: 'critical',
      ),
      OOSAlertModel(
        alertId: 'oos_fix_004',
        retailerChain: 'fathalla',
        storeId: 'fat_damanhur_main',
        storeName: kLongStoreName2,
        itemCode: 'FGMX-0400-0004',
        barcode: '6221133011906',
        skuName: 'ماكسيل ماجيك منظف أفران وشوايات مركّز 500 مل',
        brand: 'ماكسيل (Maxell)',
        category: 'منظفات متخصصة',
        estimatedLostDailyCost: 74200.0,
        consecutiveDaysOOS: 4,
        severity: 'high',
      ),
    ];
    final lost =
        alerts.fold<double>(0, (s, a) => s + a.estimatedLostDailyCost);
    return OOSMonitorResponseModel(
      totalIncidents: alerts.length,
      totalLostDailyCost: lost,
      alerts: alerts,
      brandSummaries: [
        OOSBrandSummaryModel(
          brand: kLongBrand,
          oosItemsCount: 1,
          impactedBranches: const [kLongStoreName],
          branchesCount: 1,
          totalLostDailyCost: 243000.0,
          maxDaysOOS: 14,
        ),
      ],
      branchSummaries: [
        OOSBranchSummaryModel(
          branchName: kLongStoreName,
          retailerChain: 'fathalla',
          oosItemsCount: 2,
          brandsAffected: const [kLongBrand, 'نيفيا (Nivea)'],
          totalLostDailyCost: 339500.0,
        ),
      ],
      aiAnalysis: OOSAIAnalysisModel(
        modelUsed: 'Gemini 1.5 Pro',
        generatedAt: '2026-11-13T21:00:00Z',
        executiveSummaryAr:
            'تم رصد انعدام متكرر في المخزون للأصناف الأساسية ذات الدوران السريع مثل $kLongBrand في فروع رئيسية تتصدرها $kLongStoreName.',
        executiveSummaryEn: 'Repeated OOS on high-velocity SKUs.',
        rootCausesAr: const [
          'تأخر دورات التوريد وإعادة الطلب مقارنة بمعدلات السحب اليومي المرتفعة.',
          'تركّز العجز في علامات تجارية أساسية عالية الدوران.',
        ],
        immediateActionsAr: const [
          'إصدار أمر توريد طارئ خلال 24 ساعة للأصناف الحرجة.',
          'إعادة موازنة المخزون لصالح مخزن الافوكادو من أقرب مستودع إقليمي.',
        ],
        criticalSKUsCount: 2,
        topImpactedBranch: kLongStoreName,
        topImpactedBrand: kLongBrand,
        projectedMonthlyLossEGP: lost * 30,
      ),
    );
  }
}

Future<void> pumpOos(
  WidgetTester tester,
  Widget page, {
  double width = 1280,
  double height = 3600,
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
          key: const ValueKey('oos_shot_root'),
          child: page,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> saveOosShot(WidgetTester tester, String path) async {
  final finder = find.byKey(const ValueKey('oos_shot_root'));
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

Future<void> loadOosFonts() async {
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

void disableGoogleFontsFetch() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

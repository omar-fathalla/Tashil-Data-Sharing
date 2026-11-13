import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/data_quality/data/data_quality_repository.dart';

import 'support/real_fonts.dart';

/// Live production values from the v148 Errors review (1280 shell, Cairo).
/// The previous over-long type/found/expected fixtures were longer than
/// production and starved the code and name columns in the 1030 budget.
const kLongSkuName =
    'عرض شركه 1 عبوة رابيدو 700 مل منظف وملمع الاطارات والجنوط & 1 عبوة رابيدو 300 مل ووش اند واكس - 7 مج';
const kLongSkuName2 = 'رابيدو 700 مل منظف وملمع الاطارات والجنوط';
const kLiveMissingCode = 'QA-NOT-IN-MASTER-999';
const kLiveFgccCode = 'FGCC-0700-0002';
const kLivePrccCode = 'PRCC-0700-0005';
const kLongTypeMissing = 'صنف مش موجود في كارتة الأصناف';
const kLongTypeDuplicate = 'باركود مكرر على أكثر من صنف';
const kLongTypeMismatch = 'سعر البيع أقل من التكلفة';
const kLongFound = '86 صف';
const kLongExpected = 'الصنف يتضاف لكارتة الأصناف';
const kLiveArabicCode = 'ماكسيل ماجيك متخصص عادي عادي';
const kLongReason = 'نفس الباركود مستخدم لصنفين في شيت نوفمبر بعد الدمج اليدوي';

class ErrorsShotSource implements DataQualityDataSource {
  DataQualitySummary sum;
  List<DataQualityIssue> list;
  final List<String> calls = [];

  ErrorsShotSource({DataQualitySummary? sum, List<DataQualityIssue>? list})
      : sum = sum ?? kErrorsLiveSummary,
        list = list ?? kErrorsLiveIssues;

  @override
  Future<DataQualitySummary> summary() async => sum;

  @override
  Future<List<DataQualityIssue>> issues(DataQualityFilter f) async {
    calls.add('issues:${f.status}');
    return list;
  }

  @override
  Future<DataQualityIssue> updateStatus(
      String id, String status, String reason) async {
    calls.add('patch:$id:$status:$reason');
    return list.firstWhere((i) => i.id == id, orElse: () => list.first);
  }
}

final kErrorsLiveSummary = DataQualitySummary(
  types: const [
    DataQualityTypeSummary(
      source: 'product_master',
      type: 'duplicate_barcode',
      typeLabel: kLongTypeDuplicate,
      severity: kDqCritical,
      total: 45,
      open: 41,
      impactEgp: 1845000,
    ),
    DataQualityTypeSummary(
      source: 'sell_out',
      type: 'missing_sku',
      typeLabel: kLongTypeMissing,
      severity: kDqCritical,
      total: 86,
      open: 72,
      impactEgp: 6012000,
    ),
    DataQualityTypeSummary(
      source: 'sell_in',
      type: 'price_mismatch',
      typeLabel: kLongTypeMismatch,
      severity: kDqWarning,
      total: 128,
      open: 64,
      impactEgp: 243750.5,
    ),
  ],
  totalRows: 12847,
  criticalRows: 113,
  cleanlinessPct: 90.23,
  open: 2004,
  resolved: 312,
  ignored: 18,
  updatedAt: DateTime.utc(2026, 11, 13, 18),
);

const kErrorsLiveIssues = [
  DataQualityIssue(
    id: 'e1',
    source: 'sell_out',
    type: 'missing_sku',
    typeLabel: kLongTypeMissing,
    severity: kDqCritical,
    sheet: 'مبيعات نوفمبر',
    row: 1284,
    column: 'اسم الصنف',
    itemCode: kLiveMissingCode,
    barcode: '6221133011903',
    itemName: kLongSkuName,
    foundValue: kLongFound,
    expectedValue: kLongExpected,
    impactEgp: 1845320.75,
    status: kDqOpen,
    statusReason: kLongReason,
  ),
  DataQualityIssue(
    id: 'e2',
    source: 'product_master',
    type: 'duplicate_barcode',
    typeLabel: kLongTypeDuplicate,
    severity: kDqCritical,
    sheet: 'كارتة الأصناف',
    row: 299,
    column: 'الباركود',
    itemCode: kLiveFgccCode,
    barcode: '6223000233436',
    itemName: kLongSkuName2,
    foundValue: '2 صف',
    expectedValue: 'باركود فريد لكل صنف',
    impactEgp: 601200,
    status: kDqOpen,
    statusReason: '',
  ),
  DataQualityIssue(
    id: 'e3',
    source: 'sell_in',
    type: 'price_mismatch',
    typeLabel: kLongTypeMismatch,
    severity: kDqWarning,
    sheet: 'توريد أكتوبر',
    row: 88,
    column: 'السعر',
    itemCode: kLivePrccCode,
    barcode: '6221133011905',
    itemName:
        'نيفيا كريم ترطيب عميق للبشرة الجافة 250 مل عبوة التوفير العائلية',
    foundValue: '9.5',
    expectedValue: '18.75',
    impactEgp: 96500,
    status: kDqIgnored,
    statusReason: kLongReason,
    autoClosed: false,
  ),
  DataQualityIssue(
    id: 'e4',
    source: 'sell_out',
    type: 'missing_sku',
    typeLabel: kLongTypeMissing,
    severity: kDqWarning,
    row: 42,
    itemCode: kLiveArabicCode,
    barcode: '6221133011906',
    itemName: 'ماكسيل ماجيك منظف أفران وشوايات مركّز 500 مل',
    foundValue: 'صنف غير مربوط',
    expectedValue: 'ربط بالكارتة',
    impactEgp: 74200,
    status: kDqResolved,
    statusReason: 'اتربط تلقائيًا بعد تحديث الكارتة',
    autoClosed: true,
  ),
];

Future<void> pumpErrors(
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
          key: const ValueKey('errors_shot_root'),
          child: page,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> saveErrorsShot(WidgetTester tester, String path) async {
  final finder = find.byKey(const ValueKey('errors_shot_root'));
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

Future<void> loadErrorsFonts() async {
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
  final arrows =
      File('test/fonts/NotoSansSymbols2-Arrows.ttf').readAsBytesSync();
  await (FontLoader('NotoSansSymbols2')
        ..addFont(Future.value(ByteData.view(
          Uint8List.fromList(arrows).buffer,
        ))))
      .load();
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

// Upload missing-data honesty: never invent archive dates or fake 0 metrics —
// show «—» + Arabic note. Status chips use short M3ChipSurface + description.
// Real Cairo font; made-up fixtures only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/ai_analysis_progress_card.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/anomaly_resolution_table.dart';

import 'support/real_fonts.dart';

class _EmptyArchiveApi extends ApiClient {
  _EmptyArchiveApi() : super(tenantId: 'tenant-adeco');

  @override
  Future<List<RetailChainModel>> getRetailChains({String? targetTenant}) async {
    return [
      RetailChainModel(
        chainId: 'fathalla',
        tenantId: 'adeco',
        displayName: 'أسواق فتح الله (Fathalla Market)',
        code: 'fathalla',
        storeCount: 42,
      ),
    ];
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
    return const UploadedFilesArchiveResponse(
      tenantId: 'tenant-adeco',
      totalCount: 0,
      chainCounts: {'fathalla': 0},
      files: [],
    );
  }
}

class _MissingMetricsArchiveApi extends ApiClient {
  _MissingMetricsArchiveApi() : super(tenantId: 'tenant-adeco');

  @override
  Future<List<RetailChainModel>> getRetailChains({String? targetTenant}) async {
    return [
      RetailChainModel(
        chainId: 'fathalla',
        tenantId: 'adeco',
        displayName: 'أسواق فتح الله (Fathalla Market)',
        code: 'fathalla',
        storeCount: 42,
      ),
    ];
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
      totalCount: 1,
      chainCounts: const {'fathalla': 1},
      files: [
        ArchivedExcelFileModel(
          id: 'missing-1',
          tenantId: 'tenant-adeco',
          fileName: 'pending-ingest.xlsx',
          contentType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          fileSizeBytes: 1024,
          retailChain: 'fathalla',
          chainNameAr: 'أسواق فتح الله',
          chainNameEn: 'Fathalla Market',
          targetYear: '2026',
          targetMonth: '10',
          rowsIngested: 0,
          branchesCount: 0,
          totalRevenue: 0,
          uploadedAt: '',
        ),
      ],
    );
  }
}

Future<void> _fonts() async {
  await loadRealCairoFont();
  final bytes = File('test/fonts/Cairo-Variable.ttf').readAsBytesSync();
  final data = ByteData.view(Uint8List.fromList(bytes).buffer);
  await (FontLoader('Cairo-Regular')..addFont(Future.value(data))).load();
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 3200);
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
      child: Scaffold(body: page),
    ),
  ));
  await tester.pumpAndSettle();
}

IngestionResultModel _stagedAiResult() => IngestionResultModel(
      batchId: 'b1',
      filename: 'f.xlsx',
      retailerDetected: 'fathalla',
      totalRows: 10,
      validRows: 10,
      anomalyRows: 0,
      totalRevenue: 0,
      totalQuantity: 5,
      confidenceScore: 0,
      anomalies: const [],
      isStaged: true,
      isCommitted: false,
      mappingSource: 'ai',
      mappingConfidence: 0.87,
      aiModelUsed: 'gemini-3.8-flash',
      requiresHumanApproval: true,
      guardrailSchemaValid: true,
      guardrailPiiMinimized: true,
      guardrailPerCallLogged: true,
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(_fonts);
  setUp(AppCache.clear);

  test('empty archive timestamp is «—», never a fake calendar date', () {
    expect(UploadPortalScreen.formatArchiveDateTime(''), '—');
    expect(UploadPortalScreen.formatArchiveDateTime('2026-11-02T10:15:00Z'),
        '2026-11-02 10:15');
    expect(UploadPortalScreen.formatArchiveDateTime(''), isNot(contains('2026-03-08')));
  });

  test('zero-metric archive files resolve to null labels (UI shows —)', () {
    const missing = ArchivedExcelFileModel(
      id: 'm',
      tenantId: 'tenant-adeco',
      fileName: 'x.xlsx',
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileSizeBytes: 1,
      retailChain: 'fathalla',
      chainNameAr: 'فتح الله',
      chainNameEn: 'Fathalla',
      targetYear: '2026',
      rowsIngested: 0,
      branchesCount: 0,
      totalRevenue: 0,
      uploadedAt: '',
    );
    expect(UploadPortalScreen.archiveMetricsMissing(missing), isTrue);
    expect(UploadPortalScreen.archiveBranchesLabel(missing), isNull);
    expect(UploadPortalScreen.archiveRowsLabel(missing), isNull);
    expect(UploadPortalScreen.archiveRevenueLabel(missing), isNull);

    const productMaster = ArchivedExcelFileModel(
      id: 'pm',
      tenantId: 'tenant-adeco',
      fileType: 'product_master',
      fileName: 'prices.xlsx',
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileSizeBytes: 1,
      retailChain: 'product-master',
      chainNameAr: 'كارتة الأصناف',
      chainNameEn: 'Product Master',
      targetYear: '2026',
      rowsIngested: 40,
      branchesCount: 0,
      totalRevenue: 0,
      uploadedAt: '2026-11-01T00:00:00Z',
    );
    expect(UploadPortalScreen.archiveBranchesLabel(productMaster), isNull);
    expect(UploadPortalScreen.archiveRevenueLabel(productMaster), isNull);
    expect(UploadPortalScreen.archiveRowsLabel(productMaster), isNotNull);
  });

  testWidgets(
      'empty archive: Records + Revenue KPIs are «—», not fake 0',
      (tester) async {
    await _pump(
        tester, UploadPortalScreen(apiClient: _EmptyArchiveApi()));
    expect(find.byType(M3SummaryKpiCard), findsNWidgets(4));
    final records =
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Records')));
    final revenue =
        tester.widget<Text>(find.byKey(const ValueKey('kpi_value_Revenue')));
    expect(records.data, '—');
    expect(revenue.data, '—');
    expect(find.text('لا توجد ملفات مطابقة للفلتر'), findsOneWidget);
    expect(find.text('لا توجد مبيعات للعرض'), findsOneWidget);
    expect(find.textContaining('0.0%'), findsNothing);
  });

  testWidgets(
      'missing-metric archive row shows — + Arabic note, not fake zeros',
      (tester) async {
    await _pump(
        tester, UploadPortalScreen(apiClient: _MissingMetricsArchiveApi()));
    expect(find.text('—'), findsWidgets);
    expect(find.text(UploadPortalScreen.archiveMissingMetricNote), findsWidgets);
    expect(find.text('2026-03-08'), findsNothing);
    final branches =
        find.byKey(const ValueKey('file_branches_missing-1'));
    expect(branches, findsOneWidget);
    expect(
        find.descendant(of: branches, matching: find.text('—')), findsOneWidget);
    expect(
        find.descendant(
            of: branches,
            matching: find.text(UploadPortalScreen.archiveMissingMetricNote)),
        findsOneWidget);
  });

  test('AI staged/confidence status parts are short word + description', () {
    expect(AiAnalysisProgressCard.stagedStatusParts(), ('معاينة', 'لم تُحفظ بعد'));
    final parts = AiAnalysisProgressCard.confidenceStatusParts(_stagedAiResult());
    expect(parts, isNotNull);
    expect(parts!.$1, 'ثقة');
    expect(parts.$2, '87.0%');
    expect(AiAnalysisProgressCard.revenueStatValue(_stagedAiResult()), '—');
  });

  testWidgets(
      'staged AI card uses M3ChipSurface short status + description',
      (tester) async {
    await _pump(
      tester,
      AiAnalysisProgressCard(
        isAnalyzing: false,
        result: _stagedAiResult(),
      ),
    );
    expect(find.byType(M3ChipSurface), findsWidgets);
    expect(find.byKey(const ValueKey('upload_status_staged_chip')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('upload_status_confidence_chip')),
        findsOneWidget);
    expect(find.text('معاينة'), findsOneWidget);
    expect(find.text('لم تُحفظ بعد'), findsOneWidget);
    expect(find.text('ثقة'), findsOneWidget);
    expect(find.text('87.0%'), findsOneWidget);
    expect(find.text('معاينة قيد المراجعة (لم تُحفظ بعد)'), findsNothing);
    expect(find.textContaining('درجة ثقة الذكاء الاصطناعي'), findsNothing);
  });

  test('anomaly issueParts are short chip + description', () {
    expect(AnomalyResolutionTable.issueParts('invalid_barcode', 12),
        ('باركود', 'صف 12 • باركود غير صالح'));
    expect(AnomalyResolutionTable.issueParts('unmapped_store', 3),
        ('فرع', 'صف 3 • فرع غير مربوط'));
  });

  testWidgets('anomaly table renders M3ChipSurface short labels', (tester) async {
    await _pump(
      tester,
      AnomalyResolutionTable(anomalies: const [
        {
          'row_number': 7,
          'issue_type': 'invalid_barcode',
          'description': 'الباركود أقصر من المعيار',
        },
      ]),
    );
    expect(find.byType(M3ChipSurface), findsOneWidget);
    expect(find.text('باركود'), findsOneWidget);
    expect(find.text('صف 7 • باركود غير صالح'), findsOneWidget);
    expect(find.textContaining('صف 7: invalid_barcode'), findsNothing);
  });
}

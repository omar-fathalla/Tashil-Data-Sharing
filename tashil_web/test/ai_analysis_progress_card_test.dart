import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/ai_analysis_progress_card.dart';

IngestionResultModel _result({
  String mappingSource = 'deterministic',
  String aiModelUsed = '',
  double mappingConfidence = 0,
  double confidenceScore = 0,
  bool isStaged = true,
  String validationStatus = '',
  String validationExplanationAr = '',
  List<String> validationDiffReasons = const [],
  bool requiresHumanApproval = false,
  List<String> guardrailReasonsAr = const [],
  String guardrailArabicSummary = '',
  String branchNormSummaryAr = '',
  int branchNormChanged = 0,
}) {
  return IngestionResultModel(
    batchId: 'b1',
    filename: 'f.xlsx',
    retailerDetected: 'fathalla',
    totalRows: 10,
    validRows: 10,
    anomalyRows: 0,
    totalRevenue: 100,
    totalQuantity: 5,
    confidenceScore: confidenceScore,
    anomalies: const [],
    isStaged: isStaged,
    isCommitted: !isStaged,
    mappingSource: mappingSource,
    mappingConfidence: mappingConfidence,
    aiModelUsed: aiModelUsed,
    validationStatus: validationStatus,
    validationExplanationAr: validationExplanationAr,
    validationDiffReasons: validationDiffReasons,
    requiresHumanApproval: requiresHumanApproval || isStaged,
    guardrailReasonsAr: guardrailReasonsAr,
    guardrailArabicSummary: guardrailArabicSummary,
    guardrailSchemaValid: mappingSource == 'ai' || mappingSource == 'cache',
    guardrailPiiMinimized: mappingSource == 'ai' || mappingSource == 'cache',
    guardrailPerCallLogged: mappingSource == 'ai',
    branchNormSummaryAr: branchNormSummaryAr,
    branchNormChanged: branchNormChanged,
  );
}

void main() {
  test('mappingSourceLabel is honest per source', () {
    expect(
      AiAnalysisProgressCard.mappingSourceLabel(_result(mappingSource: 'deterministic')),
      contains('بدون ذكاء اصطناعي'),
    );
    expect(
      AiAnalysisProgressCard.mappingSourceLabel(
        _result(mappingSource: 'ai', aiModelUsed: 'gemini-3.8-flash'),
      ),
      contains('gemini-3.8-flash'),
    );
    expect(
      AiAnalysisProgressCard.mappingSourceLabel(_result(mappingSource: 'cache')),
      contains('محفوظة'),
    );
    expect(
      AiAnalysisProgressCard.mappingSourceLabel(_result(mappingSource: 'mock')),
      contains('محاكاة'),
    );
  });

  test('aiConfidenceLabel hidden for non-AI sources', () {
    expect(AiAnalysisProgressCard.aiConfidenceLabel(_result()), isNull);
    expect(
      AiAnalysisProgressCard.aiConfidenceLabel(
        _result(mappingSource: 'ai', mappingConfidence: 0.95),
      ),
      contains('95.0%'),
    );
    expect(
      AiAnalysisProgressCard.aiConfidenceLabel(
        _result(mappingSource: 'deterministic', confidenceScore: 0.99),
      ),
      isNull,
    );
  });

  testWidgets('deterministic staged card never claims AI confidence', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: AiAnalysisProgressCard(
              isAnalyzing: false,
              result: _result(mappingSource: 'deterministic', confidenceScore: 0.99),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('بدون ذكاء اصطناعي'), findsOneWidget);
    expect(find.textContaining('درجة ثقة'), findsNothing);
    expect(find.textContaining('درجة الثقة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI staged card shows model and short confidence chip', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: AiAnalysisProgressCard(
              isAnalyzing: false,
              result: _result(
                mappingSource: 'ai',
                aiModelUsed: 'gemini-3.8-flash',
                mappingConfidence: 0.87,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('gemini-3.8-flash'), findsOneWidget);
    expect(find.byType(M3ChipSurface), findsWidgets);
    expect(find.text('ثقة'), findsOneWidget);
    expect(find.text('87.0%'), findsOneWidget);
    expect(find.text('معاينة'), findsOneWidget);
    expect(find.text('لم تُحفظ بعد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('IngestionResultModel reads mapping_source without inventing Gemini defaults', () {
    final m = IngestionResultModel.fromJson({
      'batch_id': 'b',
      'filename': 'f.xlsx',
      'mapping_source': 'deterministic',
      'mapping_confidence': 0,
      'ai_model_used': '',
      'confidence_score': 0,
    });
    expect(m.mappingSource, 'deterministic');
    expect(m.aiModelUsed, isEmpty);
    expect(m.usedAiMapping, isFalse);
    expect(m.tier2Escalated, isFalse);
  });

  test('IngestionResultModel reads payload.validation explanation_ar', () {
    final m = IngestionResultModel.fromJson({
      'batch_id': 'b',
      'filename': 'f.xlsx',
      'payload': {
        'validation': {
          'status': 'flagged',
          'explanation_ar':
              'الموضع: الورقة «يناير»، صفوف البيانات 2–101. فرق بسبب مرتجعات.',
          'diff_reasons': ['returns', 'sheet_column_gap'],
        },
      },
    });
    expect(m.validationStatus, 'flagged');
    expect(m.validationExplanationAr, contains('مرتجعات'));
    expect(m.validationDiffReasons, contains('returns'));
  });

  test('IngestionResultModel reads payload.branch_norm summary_ar', () {
    final m = IngestionResultModel.fromJson({
      'batch_id': 'b',
      'filename': 'f.xlsx',
      'payload': {
        'branch_norm': {
          'total': 4,
          'english': 1,
          'abbrev': 1,
          'changed': 2,
          'unknown': 0,
          'summary_ar':
              'توحيد الفروع: 4/4 معروف • 1 إنجليزي • 1 اختصار • 2 تغيّر عرضها',
        },
      },
    });
    expect(m.branchNormSummaryAr, contains('توحيد الفروع'));
    expect(m.branchNormChanged, 2);
    expect(m.branchNormEnglish, 1);
    expect(m.branchNormAbbrev, 1);
    expect(AiAnalysisProgressCard.branchNormLabel(m), contains('إنجليزي'));
    expect(AiAnalysisProgressCard.successMetricsLine(m), contains('توحيد أسماء الفروع'));
  });

  testWidgets('card shows Arabic totals explanation when flagged', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AiAnalysisProgressCard(
            isAnalyzing: false,
            result: _result(
              mappingSource: 'ai',
              aiModelUsed: 'gemini-3.8-flash',
              mappingConfidence: 0.9,
              validationStatus: 'flagged',
              validationExplanationAr:
                  'الموضع: الورقة «Sheet1»، عمود «الإجمالي» (عمود 15). فرق القيمة بسبب مرتجعات.',
              validationDiffReasons: const ['returns'],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('تنبيه على الإجماليات'), findsOneWidget);
    expect(find.textContaining('مرتجعات'), findsOneWidget);
  });

  testWidgets('card shows Arabic branch-norm summary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AiAnalysisProgressCard(
            isAnalyzing: false,
            result: _result(
              mappingSource: 'deterministic',
              branchNormSummaryAr:
                  'توحيد الفروع: 3/3 معروف • 1 إنجليزي • 1 اختصار • 2 تغيّر عرضها',
              branchNormChanged: 2,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('توحيد أسماء الفروع'), findsWidgets);
    expect(find.textContaining('إنجليزي'), findsOneWidget);
  });

  test('IngestionResultModel reads guardrail approval + Arabic metrics', () {
    final m = IngestionResultModel.fromJson({
      'batch_id': 'b',
      'filename': 'f.xlsx',
      'is_staged': true,
      'mapping_source': 'ai',
      'requires_human_approval': true,
      'guardrail_reasons_ar': ['راجع التخطيط قبل الاعتماد'],
      'guardrail_metrics': {
        'schema_valid': true,
        'human_approval_required': true,
        'pii_minimized': true,
        'per_call_logged': true,
        'arabic_summary': 'جاهز للمراجعة البشرية قبل الحفظ',
      },
    });
    expect(m.needsHumanApproval, isTrue);
    expect(m.guardrailReasonsAr, contains('راجع التخطيط قبل الاعتماد'));
    expect(m.guardrailArabicSummary, contains('مراجعة البشرية'));
    expect(AiAnalysisProgressCard.humanApprovalBanner(m), contains('مراجعة البشرية'));
    expect(AiAnalysisProgressCard.successMetricsLine(m), contains('المخطط سليم'));
  });

  testWidgets('staged card shows Arabic human-approval banner', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: AiAnalysisProgressCard(
              isAnalyzing: false,
              result: _result(
                mappingSource: 'ai',
                aiModelUsed: 'gemini-3.8-flash',
                mappingConfidence: 0.9,
                guardrailArabicSummary: 'جاهز للمراجعة البشرية قبل الحفظ',
                guardrailReasonsAr: const ['تم الاستخراج بالذكاء الاصطناعي — راجع التخطيط قبل الاعتماد'],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('مراجعة البشرية'), findsWidgets);
    expect(find.textContaining('المخطط سليم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

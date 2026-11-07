import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/ai_analysis_progress_card.dart';

IngestionResultModel _result({
  String mappingSource = 'deterministic',
  String aiModelUsed = '',
  double mappingConfidence = 0,
  double confidenceScore = 0,
  bool isStaged = true,
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiAnalysisProgressCard(
            isAnalyzing: false,
            result: _result(mappingSource: 'deterministic', confidenceScore: 0.99),
          ),
        ),
      ),
    );
    expect(find.textContaining('بدون ذكاء اصطناعي'), findsOneWidget);
    expect(find.textContaining('درجة ثقة'), findsNothing);
    expect(find.textContaining('درجة الثقة'), findsNothing);
  });

  testWidgets('AI staged card shows model and mapping confidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiAnalysisProgressCard(
            isAnalyzing: false,
            result: _result(
              mappingSource: 'ai',
              aiModelUsed: 'gemini-3.8-flash',
              mappingConfidence: 0.87,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('gemini-3.8-flash'), findsOneWidget);
    expect(find.textContaining('87.0%'), findsOneWidget);
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
}

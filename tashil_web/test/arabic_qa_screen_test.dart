import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/arabic_qa/data/arabic_qa_models.dart';
import 'package:tashil_web/features/arabic_qa/data/arabic_qa_repository.dart';
import 'package:tashil_web/features/arabic_qa/presentation/arabic_qa_screen.dart';

class _FakeQa implements ArabicQaDataSource {
  final calls = <String>[];

  @override
  Future<ArabicQaAnswer> ask(String question) async {
    calls.add(question);
    return ArabicQaAnswer(
      questionAr: question,
      answerAr: 'إجمالي الإيراد 99000.00 ج.م (قراءة فقط).',
      intent: 'executive_kpis',
      period: 'MTD',
      tenantId: 'tenant-adeco',
      confidence: 0.9,
      mappingSource: 'deterministic',
      readOnly: true,
      sources: const ['bigquery.executive_kpis'],
    );
  }

  @override
  Future<List<ArabicQaCapability>> capabilities() async => const [
        ArabicQaCapability(
          intent: 'executive_kpis',
          titleAr: 'ملخص الأداء والإيرادات',
          examplesAr: ['كام إجمالي المبيعات الشهر ده؟'],
        ),
      ];
}

void main() {
  test('ArabicQaAnswer.fromJson maps read-only payload', () {
    final a = ArabicQaAnswer.fromJson({
      'question_ar': 'كام؟',
      'answer_ar': '١٢٣',
      'intent': 'executive_kpis',
      'period': 'MTD',
      'tenant_id': 'tenant-adeco',
      'confidence': 0.9,
      'mapping_source': 'deterministic',
      'read_only': true,
      'sources': ['bigquery.executive_kpis'],
      'evidence': {'total_revenue': 1},
    });
    expect(a.readOnly, isTrue);
    expect(a.tenantId, 'tenant-adeco');
    expect(a.sources, contains('bigquery.executive_kpis'));
    expect(a.evidence['total_revenue'], 1);
  });

  testWidgets('Arabic Q&A screen asks and shows grounded answer', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = _FakeQa();
    await tester.pumpWidget(MaterialApp(
      home: ArabicQaScreen(dataSource: fake),
    ));
    await tester.pumpAndSettle();

    expect(find.text('أسئلة عربية على البيانات'), findsOneWidget);
    expect(find.textContaining('قراءة فقط'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'كام إجمالي المبيعات؟');
    await tester.tap(find.text('اسأل'));
    await tester.pumpAndSettle();

    expect(fake.calls, ['كام إجمالي المبيعات؟']);
    expect(find.textContaining('99000.00'), findsOneWidget);
    expect(find.textContaining('قراءة فقط: نعم'), findsOneWidget);
  });
}

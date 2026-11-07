import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/preupload_check.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/preupload_fix_list.dart';

void main() {
  test('PreuploadCheckReport.fromJson maps Arabic fix list', () {
    final report = PreuploadCheckReport.fromJson({
      'ok': false,
      'filename': 'bad.xlsx',
      'kind': 'sell_in',
      'wrote_nothing': true,
      'blocking_count': 2,
      'fixes': [
        {
          'code': 'missing_column',
          'severity': 'error',
          'message_ar': 'عمود مطلوب مش موجود: net V',
          'how_to_fix_ar': 'ضيف عنوان العمود',
          'column': 'net V',
        },
        {
          'code': 'unclear_month',
          'severity': 'error',
          'message_ar': 'الشهر مش مفهوم',
          'how_to_fix_ar': 'اكتب الشهر برقم',
          'samples': ['صف 2: "xyz"'],
          'count': 1,
        },
      ],
    });
    expect(report.ok, isFalse);
    expect(report.wroteNothing, isTrue);
    expect(report.hasBlockingFixes, isTrue);
    expect(report.fixes, hasLength(2));
    expect(report.fixes.first.codeLabelAr, 'عمود ناقص');
    expect(report.fixes[1].codeLabelAr, 'شهر مش واضح');
  });

  testWidgets('PreuploadFixListPanel shows Arabic fix list and no-save message', (tester) async {
    final report = PreuploadCheckReport(
      ok: false,
      filename: 'plan.csv',
      kind: 'sell_in',
      wroteNothing: true,
      blockingCount: 1,
      fixes: const [
        PreuploadFixItem(
          code: 'unreadable_cell',
          severity: 'error',
          messageAr: 'الملف فيه خلية معادلة من غير قيمة محفوظة',
          howToFixAr: 'افتح الملف في إكسل واحفظه مرة تانية',
          samples: ['sheet1!C1'],
          count: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreuploadFixListPanel(report: report),
        ),
      ),
    );

    expect(find.byKey(const Key('preupload_fix_list_panel')), findsOneWidget);
    expect(find.textContaining('مفيش حاجة اتحفظت'), findsWidgets);
    expect(find.textContaining('خلايا مش مقروءة'), findsOneWidget);
    expect(find.textContaining('الحل:'), findsOneWidget);
    expect(find.byKey(const Key('preupload_fix_unreadable_cell')), findsOneWidget);
  });
}

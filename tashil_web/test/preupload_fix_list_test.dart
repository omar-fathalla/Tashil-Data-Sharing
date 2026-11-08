import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('precheck soft-fail continues to dry-run on non-200/404/null', () {
    expect(precheckFailureShouldContinue(null), isTrue);
    expect(precheckFailureShouldContinue(404), isTrue);
    expect(precheckFailureShouldContinue(500), isTrue);
    expect(precheckFailureShouldContinue(503), isTrue);
    expect(precheckFailureShouldContinue(200), isFalse);
  });

  test('tryParseBlocked reads folded dry-run 422 body', () {
    final report = PreuploadCheckReport.tryParseBlocked('''
      {"error":"preupload_blocked","ok":false,"wrote_nothing":true,"blocking_count":1,
       "filename":"x.xlsx","fixes":[{"code":"empty_file","severity":"error",
       "message_ar":"الملف فاضي","how_to_fix_ar":"اختار ملف"}]}
    ''');
    expect(report, isNotNull);
    expect(report!.hasBlockingFixes, isTrue);
    expect(report.fixes.first.codeLabelAr, 'ملف فاضي');
    expect(PreuploadCheckReport.tryParseBlocked('{"error":"other"}'), isNull);
  });

  testWidgets('PreuploadFixListPanel shows Arabic fix list and no-save message', (tester) async {
    const report = PreuploadCheckReport(
      ok: false,
      filename: 'plan.csv',
      kind: 'sell_in',
      wroteNothing: true,
      blockingCount: 1,
      fixes: [
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
      const MaterialApp(
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

  testWidgets('soft-fail helper: non-200 precheck does not surface fix panel alone', (tester) async {
    // When standalone precheck returns null (404/5xx), UI continues without a report.
    PreuploadCheckReport? report;
    if (!precheckFailureShouldContinue(404)) {
      report = const PreuploadCheckReport(
        ok: false,
        filename: 'x',
        kind: '',
        wroteNothing: true,
        blockingCount: 1,
        fixes: [],
      );
    }
    expect(report, isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: report == null
              ? const Text('continued_to_dry_run', key: Key('continued_to_dry_run'))
              : PreuploadFixListPanel(report: report),
        ),
      ),
    );
    expect(find.byKey(const Key('continued_to_dry_run')), findsOneWidget);
    expect(find.byKey(const Key('preupload_fix_list_panel')), findsNothing);
  });
}

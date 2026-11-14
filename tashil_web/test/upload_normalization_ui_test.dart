import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/customer_registry/data/customer_registry_repository.dart';
import 'package:tashil_web/features/customer_registry/presentation/pending_customers_screen.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/upload_checks.dart';

// No AI or network is used here: the server answers are given as fixed JSON.

Widget _host(Widget child) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

class _FakeRegistry implements CustomerRegistryDataSource {
  final List<RegistryEntry> entries;
  final calls = <String>[];
  _FakeRegistry(this.entries);

  @override
  Future<List<RegistryEntry>> list({
    String status = '',
    bool includeSeed = false,
  }) async =>
      entries.where((e) => status.isEmpty || e.status == status).toList();

  @override
  Future<RegistryDecisionResult> decide(String action, String name,
      {String chain = '', String aliasOf = '', String reason = ''}) async {
    calls.add('$action|$name|$chain|$aliasOf');
    return const RegistryDecisionResult(reappliedFiles: ['in26.xlsx']);
  }
}

const _periodConflict409 = {
  'error': 'confirmation_required',
  'message': 'x',
  'confirmation': {
    'kind': 'period_conflict',
    'message_ar': 'الفترة اللي اخترتها في الفورم مختلفة عن شهور الصفوف في الملف',
    'param': 'period_choice',
    'options': [
      {'value': 'sheet', 'label_ar': 'استخدم شهور الملف (موصى بيه)', 'recommended': true},
      {'value': 'form', 'label_ar': 'استخدم فترة الفورم لكل الصفوف'},
    ],
    'breakdown': [
      {'period': '2026-02', 'rows': 10, 'value': 1000},
      {'period': '2026-03', 'rows': 5, 'value': 500},
    ],
    'form_period': '2026-01',
  },
};

void main() {
  group('year list is data driven', () {
    test('data years plus current year, newest first, default = latest data year', () {
      final o = YearOptions.fromJson(const {'years': [2024, 2025], 'default_year': 2025}, DateTime(2026, 11, 3));
      expect(o.years, [2026, 2025, 2024]);
      expect(o.defaultYear, 2025);
    });
    test('2027 data shows 2027 without code changes', () {
      final o = YearOptions.fromJson(const {'years': [2025, 2026, 2027], 'default_year': 2027}, DateTime(2026, 11, 3));
      expect(o.years.first, 2027);
      expect(o.defaultYear, 2027);
    });
    test('fallback is the current year only; selected year stays visible', () {
      final o = YearOptions.fallback(DateTime(2031, 1, 1));
      expect(o.years, [2031]);
      expect(o.including(2025), [2031, 2025]);
      expect(o.including(0), [2031]);
    });
    test('bad default falls back to newest year', () {
      final o = YearOptions.fromJson(const {'years': [2025], 'default_year': 1999}, DateTime(2026));
      expect(o.defaultYear, 2026);
    });
  });

  group('server refusals are never shown as success', () {
    test('409 becomes a question with options and breakdown', () {
      expect(
        () => throwIfUploadRefused(409, jsonEncode(_periodConflict409), 'fail'),
        throwsA(isA<UploadConfirmationRequiredException>()
            .having((e) => e.kind, 'kind', 'period_conflict')
            .having((e) => e.options.first.recommended, 'recommended', true)
            .having((e) => e.breakdown.length, 'breakdown', 2)),
      );
    });
    test('422 carries the Arabic reason', () {
      expect(
        () => throwIfUploadRefused(422, jsonEncode({'error': 'formula_uncached', 'message': 'افتح الملف في إكسل واحفظه مرة تانية'}), 'fail'),
        throwsA(isA<UploadRejectedException>().having((e) => e.message, 'm', contains('احفظه مرة تانية'))),
      );
    });
    test('2xx passes', () => throwIfUploadRefused(200, '{}', 'fail'));
  });

  test('result model reads quarantine, unknown barcodes and warnings', () {
    final m = IngestionResultModel.fromJson({
      'batch_id': 'b',
      'filename': 'f.xlsx',
      'upload_warnings': [
        {'code': 'customers_quarantined', 'severity': 'warning', 'message_ar': 'عملاء جداد', 'count': 1}
      ],
      'quarantined_customers': [
        {'name': 'QA عميل تجريبي', 'rows': 3, 'value': 70, 'months': ['2026-02'], 'suggested_name': 'فتح الله جملة'}
      ],
      'unknown_barcodes': [
        {'barcode': '999', 'item_name': 'صنف تجريبي', 'rows': 2}
      ],
      'period_breakdown': [
        {'period': 'fathalla|2026-02', 'rows': 3}
      ],
    });
    expect(m.quarantinedCustomers.single.name, 'QA عميل تجريبي');
    expect(m.unknownBarcodes.single['barcode'], '999');
    expect(m.uploadWarnings.single.code, 'customers_quarantined');
    expect(m.periodBreakdown.single.month, '2026-02');
    final c = m.copyWith(validRows: 1);
    expect(c.quarantinedCustomers.length, 1);
  });

  testWidgets('period conflict dialog: recommended sheet option is returned', (tester) async {
    final q = UploadConfirmationRequiredException.tryParse(jsonEncode(_periodConflict409))!;
    UploadConfirmAnswer? answer;
    await tester.pumpWidget(_host(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => answer = await askUploadConfirmation(ctx, q),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('فبراير 2026'), findsOneWidget);
    expect(find.text('مارس 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('upload_confirm_option_sheet')));
    await tester.pumpAndSettle();
    expect(answer?.periodChoice, 'sheet');
    expect(answer?.replaceConfirmed, false);
  });

  testWidgets('partial month dialog: cancel saves nothing, replace confirms', (tester) async {
    const q = UploadConfirmationRequiredException(
      kind: 'partial_month',
      messageAr: 'الملف فيه جزء بس من الشهر',
      param: 'replace_confirmed',
      breakdown: [UploadMonthSlice(period: '2026-03', rows: 4, value: 100, existingRows: 200, existingValue: 9000)],
    );
    final answers = <UploadConfirmAnswer?>[];
    await tester.pumpWidget(_host(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => answers.add(await askUploadConfirmation(ctx, q)),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_confirm_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_confirm_replace')));
    await tester.pumpAndSettle();
    expect(answers.first, isNull);
    expect(answers.last?.replaceConfirmed, true);
  });

  testWidgets('runUploadWithQuestions resends with the chosen answer', (tester) async {
    final sent = <String>[];
    String? out;
    await tester.pumpWidget(_host(Builder(
      builder: (ctx) => TextButton(
        onPressed: () async {
          out = await runUploadWithQuestions<String>(ctx, (replace, choice) async {
            sent.add('$replace|$choice');
            if (choice == null) throw UploadConfirmationRequiredException.tryParse(jsonEncode(_periodConflict409))!;
            return 'ok';
          });
        },
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_confirm_option_form')));
    await tester.pumpAndSettle();
    expect(sent, ['false|null', 'false|form']);
    expect(out, 'ok');
  });

  testWidgets('warnings panel lists held-out customers and unknown items', (tester) async {
    await tester.pumpWidget(_host(const SingleChildScrollView(
      child: UploadChecksPanel(
        quarantined: [QuarantinedCustomerInfo(name: 'QA عميل تجريبي', rows: 3, value: 70, suggestedName: 'فتح الله جملة')],
        unknownBarcodes: [
          {'barcode': '999', 'item_name': 'صنف تجريبي', 'rows': 2}
        ],
      ),
    )));
    expect(find.text('QA عميل تجريبي'), findsOneWidget);
    expect(find.textContaining('مش هيتطبق لوحده'), findsOneWidget);
    expect(find.text('صنف تجريبي'), findsOneWidget);
    expect(find.textContaining('الصفوف اتحفظت'), findsOneWidget);
  });

  testWidgets('warnings panel is empty when there is nothing to report', (tester) async {
    await tester.pumpWidget(_host(const UploadChecksPanel()));
    expect(find.byKey(const Key('upload_checks_panel')), findsNothing);
  });

  testWidgets('pending customers: approve with a chain, then nothing else is merged', (tester) async {
    final fake = _FakeRegistry([
      RegistryEntry.fromJson({
        'name': 'QA عميل تجريبي',
        'status': 'pending',
        'suggested_name': 'فتح الله جملة',
        'quarantine': [
          {'file': 'qa.xlsx', 'rows': 3, 'value': 70, 'months': ['2026-02']}
        ],
      }),
    ]);
    await tester.pumpWidget(MaterialApp(home: PendingCustomersScreen(dataSource: fake)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('محتاج تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('QA عميل تجريبي'), findsOneWidget);
    expect(find.textContaining('اقتراح بس'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve_QA عميل تجريبي')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('approve_chain_field')), 'qa_test');
    await tester.tap(find.byKey(const Key('approve_confirm')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['approve|QA عميل تجريبي|qa_test|']);
  });

  test('Arabic month label', () {
    expect(arabicMonthLabel('fathalla|2026-12'), 'ديسمبر 2026');
    expect(arabicMonthLabel('bad'), 'bad');
  });
}

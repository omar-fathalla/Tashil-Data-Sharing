import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/customer_registry/data/customer_registry_repository.dart';
import 'package:tashil_web/features/customer_registry/presentation/pending_customers_screen.dart';

class _FakeRegistry implements CustomerRegistryDataSource {
  _FakeRegistry(this.entries);
  List<RegistryEntry> entries;
  final calls = <Map<String, String>>[];

  @override
  Future<List<RegistryEntry>> list({
    String status = '',
    bool includeSeed = false,
  }) async {
    if (status == 'live') {
      return [
        for (final e in entries)
          if (e.status == 'live' || e.liveRows > 0) e,
      ];
    }
    return [
      for (final e in entries)
        if (status.isEmpty || e.status == status) e,
    ];
  }

  @override
  Future<RegistryDecisionResult> decide(
    String action,
    String name, {
    String chain = '',
    String aliasOf = '',
    String reason = '',
  }) async {
    calls.add({
      'action': action,
      'name': name,
      'chain': chain,
      'aliasOf': aliasOf,
    });
    return const RegistryDecisionResult(reappliedFiles: ['in26.xlsx']);
  }
}

const _pendingKafr = RegistryEntry(
  name: 'كفر الدوار 2 — فرع أ',
  status: 'pending',
  chain: 'كارفور',
  rows: 800,
  value: 500000,
);

const _approvedKafr = RegistryEntry(
  name: 'كفر الدوار 2',
  status: 'approved',
  chain: 'كارفور',
  liveRows: 767,
  liveValue: 573994.41,
);

const _otherChain = RegistryEntry(
  name: 'عميل سلسلة تانية',
  status: 'approved',
  chain: 'سبينس',
  liveRows: 10,
  liveValue: 1000,
);

const _rejected = RegistryEntry(
  name: 'عميل مرفوض',
  status: 'rejected',
  chain: 'كارفور',
  rows: 3,
  value: 100,
);

const _liveGrocery = RegistryEntry(
  name: 'عائله فتح الله ماركت - كفر الدوار 2',
  status: 'live',
  chain: 'fathalla',
  liveRows: 1492,
  liveValue: 1058327.30,
);

const _liveCare = RegistryEntry(
  name: 'عائله فتح الله ماركت مواد عناية - كفر الدوار2',
  status: 'live',
  chain: 'fathalla',
  liveRows: 75,
  liveValue: 15667.11,
);

const _qaApproved = RegistryEntry(
  name: 'فرع qa_test - QA عميل جديد خالص',
  status: 'approved',
  chain: 'qa_test',
);

Future<void> _open(WidgetTester tester, {_FakeRegistry? ds, List<RegistryEntry>? entries}) async {
  final source = ds ?? _FakeRegistry(List.of(entries ?? const []));
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: PendingCustomersScreen(dataSource: source)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final registrySeed = [_pendingKafr, _approvedKafr, _otherChain, _rejected];
  final liveSeed = [_liveGrocery, _liveCare, _qaApproved, _otherChain];

  testWidgets('كل العملاء lists exact-match Sell-In names and hides zero-row QA approval',
      (tester) async {
    final ds = _FakeRegistry(List.of(liveSeed));
    await _open(tester, ds: ds);
    expect(find.text('كل العملاء'), findsWidgets);
    expect(find.byKey(const Key('merge_عائله فتح الله ماركت - كفر الدوار 2')), findsOneWidget);
    expect(find.byKey(const Key('merge_عائله فتح الله ماركت مواد عناية - كفر الدوار2')), findsOneWidget);
    expect(find.text('فرع qa_test - QA عميل جديد خالص'), findsNothing);

    await tester.enterText(find.byKey(const Key('registry_live_search')), 'عناية');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merge_عائله فتح الله ماركت مواد عناية - كفر الدوار2')), findsOneWidget);
    expect(find.byKey(const Key('merge_عائله فتح الله ماركت - كفر الدوار 2')), findsNothing);
  });

  testWidgets('live merge confirm posts approve with alias_of for same-chain names',
      (tester) async {
    final ds = _FakeRegistry(List.of(liveSeed));
    await _open(tester, ds: ds);
    await tester.tap(find.byKey(const Key('merge_عائله فتح الله ماركت مواد عناية - كفر الدوار2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merge_picker_dialog')), findsOneWidget);
    expect(find.byKey(const Key('merge_pick_عائله فتح الله ماركت - كفر الدوار 2')), findsOneWidget);
    expect(find.byKey(const Key('merge_pick_عميل سلسلة تانية')), findsNothing);

    await tester.tap(find.byKey(const Key('merge_pick_عائله فتح الله ماركت - كفر الدوار 2')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('merge_confirm_dialog'));
    expect(confirm, findsOneWidget);
    expect(find.descendant(of: confirm, matching: find.textContaining('1492 صف')), findsOneWidget);
    expect(find.descendant(of: confirm, matching: find.textContaining('75 صف')), findsOneWidget);

    await tester.tap(find.byKey(const Key('merge_confirm')));
    await tester.pumpAndSettle();
    expect(ds.calls, hasLength(1));
    expect(ds.calls.single['action'], 'approve');
    expect(ds.calls.single['name'], 'عائله فتح الله ماركت مواد عناية - كفر الدوار2');
    expect(ds.calls.single['aliasOf'], 'عائله فتح الله ماركت - كفر الدوار 2');
    expect(ds.calls.single['chain'], 'fathalla');
  });

  testWidgets('pending and approved cards show merge; rejected does not', (tester) async {
    final ds = _FakeRegistry(List.of(registrySeed));
    await _open(tester, ds: ds);
    await tester.tap(find.text('محتاج تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('دمج مع عميل آخر'), findsOneWidget);
    expect(find.byKey(const Key('merge_كفر الدوار 2 — فرع أ')), findsOneWidget);

    await tester.tap(find.text('متأكد'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merge_كفر الدوار 2')), findsOneWidget);
    expect(find.byKey(const Key('merge_عميل سلسلة تانية')), findsOneWidget);
    expect(find.text('دمج مع عميل آخر'), findsNWidgets(2));
    expect(find.byKey(const Key('unmerge_كفر الدوار 2')), findsOneWidget);

    await tester.tap(find.text('مرفوض'));
    await tester.pumpAndSettle();
    expect(find.text('دمج مع عميل آخر'), findsNothing);
    expect(find.byKey(const Key('merge_عميل مرفوض')), findsNothing);
  });

  testWidgets('picker lists same-chain names only and search filters them', (tester) async {
    final ds = _FakeRegistry(List.of(registrySeed));
    await _open(tester, ds: ds);
    await tester.tap(find.text('محتاج تأكيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge_كفر الدوار 2 — فرع أ')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merge_picker_dialog')), findsOneWidget);
    expect(find.text('اختار العميل اللي هنضمّ عليه'), findsOneWidget);
    expect(find.byKey(const Key('merge_pick_كفر الدوار 2')), findsOneWidget);
    expect(find.byKey(const Key('merge_pick_عميل سلسلة تانية')), findsNothing);
    expect(find.byKey(const Key('merge_pick_كفر الدوار 2 — فرع أ')), findsNothing);

    await tester.enterText(find.byKey(const Key('merge_picker_search')), 'سبينس');
    await tester.pumpAndSettle();
    expect(find.text('مفيش نتيجة للبحث ده'), findsOneWidget);
    expect(find.byKey(const Key('merge_pick_كفر الدوار 2')), findsNothing);

    await tester.enterText(find.byKey(const Key('merge_picker_search')), 'كفر');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merge_pick_كفر الدوار 2')), findsOneWidget);
  });

  testWidgets('confirm shows both counts and posts approve with alias_of', (tester) async {
    final ds = _FakeRegistry(List.of(registrySeed));
    await _open(tester, ds: ds);
    await tester.tap(find.text('محتاج تأكيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge_كفر الدوار 2 — فرع أ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge_pick_كفر الدوار 2')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('merge_confirm_dialog'));
    expect(confirm, findsOneWidget);
    expect(find.text('تأكيد دمج العملاء'), findsOneWidget);
    expect(find.text('تأكيد الدمج'), findsOneWidget);
    expect(
        find.descendant(of: confirm, matching: find.textContaining('كفر الدوار 2 — فرع أ')),
        findsOneWidget);
    expect(find.descendant(of: confirm, matching: find.textContaining('800 صف')), findsOneWidget);
    expect(find.descendant(of: confirm, matching: find.textContaining('767 صف')), findsOneWidget);

    await tester.tap(find.byKey(const Key('merge_confirm')));
    await tester.pumpAndSettle();

    expect(ds.calls, hasLength(1));
    expect(ds.calls.single['action'], 'approve');
    expect(ds.calls.single['name'], 'كفر الدوار 2 — فرع أ');
    expect(ds.calls.single['aliasOf'], 'كفر الدوار 2');
    expect(ds.calls.single['chain'], 'كارفور');
  });

  testWidgets('cancel on confirm does not call decide', (tester) async {
    final ds = _FakeRegistry(List.of(registrySeed));
    await _open(tester, ds: ds);
    await tester.tap(find.text('محتاج تأكيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge_كفر الدوار 2 — فرع أ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge_pick_كفر الدوار 2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(ds.calls, isEmpty);
    expect(find.byKey(const Key('merge_confirm_dialog')), findsNothing);
  });
}

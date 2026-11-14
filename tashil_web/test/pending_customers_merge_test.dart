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

Future<void> _open(
  WidgetTester tester, {
  required _FakeRegistry ds,
  String? openStatus,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PendingCustomersScreen(dataSource: ds),
    ),
  );
  await tester.pumpAndSettle();
  if (openStatus != null) {
    final label = {
      'pending': 'محتاج تأكيد',
      'approved': 'متأكد',
      'rejected': 'مرفوض',
    }[openStatus]!;
    await tester.tap(find.widgetWithText(ButtonSegment<String>, label).first);
    // SegmentedButton child may be Text; tap the text.
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final seed = [_pendingKafr, _approvedKafr, _otherChain, _rejected];

  testWidgets('pending and approved cards show merge; rejected does not',
      (tester) async {
    final ds = _FakeRegistry(List.of(seed));
    await _open(tester, ds: ds);
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

  testWidgets('picker lists same-chain names only and search filters them',
      (tester) async {
    final ds = _FakeRegistry(List.of(seed));
    await _open(tester, ds: ds);
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

  testWidgets('confirm shows both counts and posts approve with alias_of',
      (tester) async {
    final ds = _FakeRegistry(List.of(seed));
    await _open(tester, ds: ds);
    await tester.tap(find.byKey(const Key('merge_كفر الدوار 2 — فرع أ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge_pick_كفر الدوار 2')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('merge_confirm_dialog'));
    expect(confirm, findsOneWidget);
    expect(find.text('تأكيد دمج العملاء'), findsOneWidget);
    expect(find.text('تأكيد الدمج'), findsOneWidget);
    expect(find.descendant(of: confirm, matching: find.textContaining('كفر الدوار 2 — فرع أ')), findsOneWidget);
    expect(find.descendant(of: confirm, matching: find.textContaining('كفر الدوار 2')), findsOneWidget);
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
    final ds = _FakeRegistry(List.of(seed));
    await _open(tester, ds: ds);
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

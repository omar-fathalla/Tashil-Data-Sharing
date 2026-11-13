import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/data_quality/data/data_quality_repository.dart';
import 'package:tashil_web/features/data_quality/presentation/screens/data_quality_screen.dart';

class _FakeSource implements DataQualityDataSource {
  DataQualitySummary sum;
  List<DataQualityIssue> list;
  final List<String> calls = [];
  _FakeSource(this.sum, this.list);

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
    return list.first;
  }
}

const _dup = DataQualityIssue(
  id: 'a1',
  source: 'product_master',
  type: 'duplicate_barcode',
  typeLabel: 'باركود مكرر',
  severity: kDqCritical,
  row: 299,
  itemCode: 'FGHC-0700-0214',
  barcode: '6223000233436',
  status: kDqOpen,
);

DataQualitySummary _s(int open, double pct, DateTime at) => DataQualitySummary(
      types: [
        DataQualityTypeSummary(
            source: 'product_master',
            type: 'duplicate_barcode',
            typeLabel: 'باركود مكرر',
            severity: kDqCritical,
            total: 45,
            open: open,
            impactEgp: 1000),
      ],
      totalRows: 389,
      criticalRows: 38,
      cleanlinessPct: pct,
      open: open,
      updatedAt: at,
    );

void main() {
  testWidgets(
      'summary gauge reflects real row counts (not 0/0 at 100% with open issues)',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Prod bug shape: open/cards populated but cleanliness falsely 100% with 0 of 0 rows.
    const broken = DataQualitySummary(
      types: [
        DataQualityTypeSummary(
          source: 'product_master',
          type: 'duplicate_barcode',
          typeLabel: 'باركود مكرر',
          severity: kDqCritical,
          total: 41,
          open: 41,
          impactEgp: 1000,
        ),
      ],
      totalRows: 0,
      criticalRows: 0,
      cleanlinessPct: 100,
      open: 79,
      resolved: 4,
    );
    final fixed = DataQualitySummary(
      types: broken.types,
      totalRows: 389,
      criticalRows: 38,
      cleanlinessPct: 90.2,
      open: 79,
      resolved: 4,
      updatedAt: DateTime.utc(2026, 11, 10, 17),
    );
    final src = _FakeSource(fixed, [_dup]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
          body: DataQualityScreen(
              dataSource: src, pollInterval: const Duration(hours: 1))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('90.2%'), findsOneWidget);
    expect(find.textContaining('من 389 صفًا'), findsOneWidget);
    expect(find.byKey(const ValueKey('dq_value_open')), findsOneWidget);
    expect(find.text('79'), findsOneWidget);
    expect(find.text('0 من 0 صف بدون أخطاء حرجة'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'shows summary + table, ignore needs a reason, auto-refreshes on new version',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final src =
        _FakeSource(_s(68, 90.23, DateTime.utc(2026, 10, 25, 9)), [_dup]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
          body: DataQualityScreen(
              dataSource: src, pollInterval: const Duration(seconds: 1))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('90.2%'), findsOneWidget);
    expect(find.byKey(const ValueKey('dq_item_code_FGHC-0700-0214')),
        findsOneWidget);
    expect(src.calls.first, 'issues:'); // default = open only

    final statusBtn = find.byKey(const ValueKey('dq_status_a1'));
    expect(statusBtn, findsOneWidget);
    await tester.ensureVisible(statusBtn);
    await tester.pumpAndSettle();
    await tester.tap(statusBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dq_status_save')));
    await tester.pumpAndSettle();
    expect(find.text('السبب مطلوب عند التجاهل'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('dq_status_reason')), 'عرض بنفس الباركود');
    await tester.tap(find.byKey(const ValueKey('dq_status_save')));
    await tester.pumpAndSettle();
    expect(src.calls, contains('patch:a1:$kDqIgnored:عرض بنفس الباركود'));

    // backend re-ran checks: issue auto-resolved, page refreshes without a manual reload
    src.sum = _s(66, 91.0, DateTime.utc(2026, 10, 25, 10));
    src.list = const [];
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('91.0%'), findsOneWidget);
    expect(find.byKey(const ValueKey('dq_empty')), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose timer
  });

  testWidgets('empty rows show em-dash gauge, not 100%', (tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final empty = DataQualitySummary(
      types: const [],
      totalRows: 0,
      criticalRows: 0,
      cleanlinessPct: 100,
      open: 79,
      updatedAt: DateTime.utc(2026, 11, 10),
    );
    final src = _FakeSource(empty, const []);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
          body: DataQualityScreen(
              dataSource: src, pollInterval: const Duration(hours: 1))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('مفيش صفوف اتفحصت'), findsOneWidget);
    expect(find.text('100.0%'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

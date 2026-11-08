import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/sellin_assist/data/sellin_assist_repository.dart';
import 'package:tashil_web/features/sellin_assist/presentation/sellin_assist_screen.dart';

class _FakeAssist implements SellInAssistDataSource {
  final List<AssistSuggestion> items;
  final calls = <String>[];
  _FakeAssist(this.items);

  @override
  Future<List<AssistSuggestion>> list({String status = 'pending'}) async =>
      items.where((e) => status.isEmpty || e.status == status).toList();

  @override
  Future<AssistMetrics> metrics() async => AssistMetrics(
        suggested: items.length,
        approved: items.where((e) => e.status == 'approved').length,
        rejected: items.where((e) => e.status == 'rejected').length,
        pending: items.where((e) => e.status == 'pending').length,
        approvalRate: 0.5,
        approvedFragments: const ['كيه اتش=gomla'],
      );

  @override
  Future<AssistSuggestion> decide(String action, String id) async {
    calls.add('$action|$id');
    final i = items.indexWhere((e) => e.id == id);
    if (i < 0) throw Exception('missing');
    items[i] = AssistSuggestion(
      id: items[i].id,
      kind: items[i].kind,
      status: action == 'approve' ? 'approved' : 'rejected',
      confidence: items[i].confidence,
      mappingSource: items[i].mappingSource,
      reasonAr: items[i].reasonAr,
      customerNeedle: items[i].customerNeedle,
      suggestedChain: items[i].suggestedChain,
      envFragment: items[i].envFragment,
    );
    return items[i];
  }

  @override
  Future<List<AssistSuggestion>> suggestChains({
    required List<String> customers,
    String uploadChain = 'fathalla',
  }) async {
    calls.add('suggest|${customers.length}');
    final s = AssistSuggestion(
      id: 'new-1',
      kind: 'customer_chain',
      status: 'pending',
      confidence: 0.8,
      mappingSource: 'deterministic',
      reasonAr: 'اقتراح تجريبي',
      customerNeedle: 'كيه اتش',
      suggestedChain: 'gomla',
      envFragment: 'كيه اتش=gomla',
      sampleCustomers: customers,
    );
    items.add(s);
    return [s];
  }

  @override
  Future<AssistSuggestion> suggestLayout({
    required String filename,
    required List<List<String>> sample,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('Arabic assist screen shows metrics and requires approve', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = _FakeAssist([
      const AssistSuggestion(
        id: 's1',
        kind: 'customer_chain',
        status: 'pending',
        confidence: 0.82,
        mappingSource: 'deterministic',
        reasonAr: 'اسم العميل فيه «كيه اتش» → سلسلة مقترحة «gomla»',
        customerNeedle: 'كيه اتش',
        suggestedChain: 'gomla',
        envFragment: 'كيه اتش=gomla',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: SellInAssistScreen(dataSource: fake),
    ));
    await tester.pumpAndSettle();

    expect(find.text('مساعدة Gemini لملفات التوريد'), findsOneWidget);
    expect(find.byKey(const Key('sellin_assist_metrics')), findsOneWidget);
    expect(find.byKey(const Key('sellin_assist_approval_rate')), findsOneWidget);
    expect(find.textContaining('نسبة الاعتماد'), findsOneWidget);
    expect(find.textContaining('SELLIN_CUSTOMER_CHAIN_MAP'), findsWidgets);
    expect(find.byKey(const Key('sellin_assist_approve_s1')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('sellin_assist_approve_s1')));
    await tester.tap(find.byKey(const Key('sellin_assist_approve_s1')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('approve|s1'));
  });

  testWidgets('suggest chains dialog creates pending suggestions only', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = _FakeAssist([]);
    await tester.pumpWidget(MaterialApp(home: SellInAssistScreen(dataSource: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sellin_assist_suggest_chains')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellin_assist_suggest_chains_dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sellin_assist_customers_field')),
      'فرع فتح الله - كيه اتش جمله ماركت',
    );
    await tester.tap(find.byKey(const Key('sellin_assist_suggest_confirm')));
    await tester.pumpAndSettle();

    expect(fake.calls, contains('suggest|1'));
    expect(find.textContaining('كيه اتش'), findsWidgets);
    // Still pending until human approves.
    expect(find.byKey(const Key('sellin_assist_approve_new-1')), findsOneWidget);
  });
}

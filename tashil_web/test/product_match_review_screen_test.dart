import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/product_match/data/product_match_repository.dart';
import 'package:tashil_web/features/product_match/presentation/screens/product_match_review_screen.dart';

class _FakeMatchSource implements ProductMatchDataSource {
  List<ProductMatchReviewItem> items;
  ProductMatchMetrics currentMetrics;
  final List<String> calls = [];

  _FakeMatchSource(this.items, this.currentMetrics);

  @override
  Future<List<ProductMatchReviewItem>> list({String status = 'pending'}) async {
    calls.add('list:$status');
    final filtered = items.where((e) => status.isEmpty || e.status == status).toList();
    return sortProductMatchByPriority(filtered);
  }

  @override
  Future<ProductMatchMetrics> metrics() async => currentMetrics;

  @override
  Future<ProductMatchMetrics> decide({
    required String id,
    required String status,
    String reasonAr = '',
    String chosenItemCode = '',
    String chosenBarcode = '',
  }) async {
    calls.add('decide:$id:$status:$chosenBarcode');
    items = [
      for (final e in items)
        if (e.id == id)
          ProductMatchReviewItem(
            id: e.id,
            status: status,
            skuName: e.skuName,
            barcode: e.barcode,
            decision: e.decision,
            confidence: e.confidence,
            reasonAr: e.reasonAr,
            matchedItemCode: chosenItemCode.isEmpty ? e.matchedItemCode : chosenItemCode,
            suggestedBarcode: e.suggestedBarcode,
            chosenBarcode: chosenBarcode,
            candidates: e.candidates,
            rows: e.rows,
            value: e.value,
          )
        else
          e,
    ];
    currentMetrics = ProductMatchMetrics(
      totalMatched: currentMetrics.totalMatched,
      pending: items.where((e) => e.status == 'pending').length,
      approved: items.where((e) => e.status == 'approved').length,
      rejected: items.where((e) => e.status == 'rejected').length,
      inventedBarcodes: 0,
      autoResolveRate: 0.5,
      labelsAr: const {'pending': 'بانتظار المراجعة'},
    );
    return currentMetrics;
  }

  @override
  Future<ProductMatchBulkDecideResult> bulkDecide({
    required List<String> ids,
    required String status,
    String reasonAr = '',
  }) async {
    calls.add('bulk:$status:${ids.join(",")}');
    var approved = 0;
    var skipped = 0;
    for (final id in ids) {
      ProductMatchReviewItem? item;
      for (final e in items) {
        if (e.id == id) {
          item = e;
          break;
        }
      }
      if (item == null || !item.bulkApproveEligible) {
        skipped++;
        continue;
      }
      await decide(
        id: id,
        status: status,
        reasonAr: reasonAr,
        chosenItemCode: item.matchedItemCode,
        chosenBarcode: item.suggestedBarcode,
      );
      approved++;
    }
    return ProductMatchBulkDecideResult(
      approved: approved,
      skipped: skipped,
      failed: 0,
      metrics: currentMetrics,
    );
  }
}

void main() {
  test('sortProductMatchByPriority puts high value first', () {
    final sorted = sortProductMatchByPriority(const [
      ProductMatchReviewItem(id: 'low', status: 'pending', value: 50, rows: 1, decision: 'none'),
      ProductMatchReviewItem(
        id: 'high',
        status: 'pending',
        value: 25000,
        rows: 60,
        decision: 'uncertain',
        matchedItemCode: 'X',
        suggestedBarcode: '6223000231227',
      ),
      ProductMatchReviewItem(
        id: 'mid',
        status: 'pending',
        value: 1500,
        rows: 12,
        decision: 'uncertain',
        matchedItemCode: 'Y',
        suggestedBarcode: '6223000231227',
      ),
    ]);
    expect(sorted.map((e) => e.id), ['high', 'mid', 'low']);
    expect(sorted.first.priority, ProductMatchPriority.high);
    expect(sorted.first.bulkApproveEligible, isTrue);
    expect(sorted.last.bulkApproveEligible, isFalse);
  });

  testWidgets('Arabic review queue shows metrics, reason, and approve flow without inventing barcodes', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final src = _FakeMatchSource(
      [
        const ProductMatchReviewItem(
          id: 'r1',
          status: 'pending',
          skuName: 'كلوريل مبيض تقريبي',
          barcode: '',
          decision: 'uncertain',
          confidence: 0.62,
          reasonAr: 'تشابه متوسط — يحتاج مراجعة بشرية',
          matchedItemCode: 'FGCL-0550-0001',
          matchedName: 'كلوريل 500 جم مبيض',
          suggestedBarcode: '6223000231227',
          barcodePolicy: 'from_master_pending_review',
          candidates: [
            ProductMatchCandidate(
              itemCode: 'FGCL-0550-0001',
              barcode: '6223000231227',
              officialName: 'كلوريل 500 جم مبيض',
              confidence: 0.62,
              reasonAr: 'تشابه متوسط',
            ),
          ],
          rows: 3,
          value: 1200,
        ),
      ],
      const ProductMatchMetrics(
        totalMatched: 10,
        pending: 1,
        autoResolveRate: 0.7,
        reviewRate: 0.3,
        inventedBarcodes: 0,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ProductMatchReviewScreen(dataSource: src),
    ));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة مطابقة الأصناف'), findsOneWidget);
    expect(find.textContaining('لا يتم اختراع باركودات'), findsOneWidget);
    expect(find.byKey(const Key('product_match_metrics')), findsOneWidget);
    expect(find.textContaining('تشابه متوسط — يحتاج مراجعة بشرية'), findsOneWidget);
    expect(find.text('باركودات مخترعة'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.byKey(const ValueKey('pm_priority_r1')), findsOneWidget);
    expect(find.text('أولوية متوسطة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pm_approve_r1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve_product_match_dialog')), findsOneWidget);
    expect(find.textContaining('لن يتم اختراع باركود'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve_match_confirm')));
    await tester.pumpAndSettle();
    expect(src.calls, contains('decide:r1:approved:6223000231227'));
  });

  testWidgets('prioritized list + bulk approve eligible items', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final src = _FakeMatchSource(
      [
        const ProductMatchReviewItem(
          id: 'low',
          status: 'pending',
          skuName: 'صنف ضعيف التأثير',
          decision: 'none',
          confidence: 0,
          reasonAr: 'بدون مرشح',
          rows: 1,
          value: 20,
        ),
        const ProductMatchReviewItem(
          id: 'high',
          status: 'pending',
          skuName: 'كلوريل عالي القيمة',
          decision: 'uncertain',
          confidence: 0.7,
          reasonAr: 'تشابه جيد للمراجعة',
          matchedItemCode: 'FGCL-0550-0001',
          matchedName: 'كلوريل 500 جم مبيض',
          suggestedBarcode: '6223000231227',
          rows: 55,
          value: 22000,
        ),
      ],
      const ProductMatchMetrics(pending: 2, inventedBarcodes: 0),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ProductMatchReviewScreen(dataSource: src),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product_match_bulk_toolbar')), findsOneWidget);
    expect(find.byKey(const Key('pm_top_priority_hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('pm_bulk_eligible_high')), findsOneWidget);
    expect(find.byKey(const ValueKey('pm_bulk_eligible_low')), findsNothing);

    // Card order: high before low
    final highY = tester.getTopLeft(find.byKey(const ValueKey('pm_review_high'))).dy;
    final lowY = tester.getTopLeft(find.byKey(const ValueKey('pm_review_low'))).dy;
    expect(highY < lowY, isTrue);

    await tester.tap(find.byKey(const Key('pm_select_all_eligible')));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('pm_select_high'))).value, isTrue);

    await tester.tap(find.byKey(const Key('pm_bulk_approve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bulk_approve_product_match_dialog')), findsOneWidget);
    expect(find.textContaining('لن يتم اختراع باركود'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bulk_approve_match_confirm')));
    await tester.pumpAndSettle();

    expect(src.calls.any((c) => c.startsWith('bulk:approved:high')), isTrue);
    expect(src.items.where((e) => e.id == 'high').single.status, 'approved');
    expect(src.items.where((e) => e.id == 'low').single.status, 'pending');
  });

  testWidgets('empty pending state', (tester) async {
    final src = _FakeMatchSource(const [], const ProductMatchMetrics(inventedBarcodes: 0));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ProductMatchReviewScreen(dataSource: src),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product_match_empty')), findsOneWidget);
  });
}

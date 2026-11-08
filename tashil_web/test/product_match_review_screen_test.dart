import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/product_match/data/product_match_repository.dart';
import 'package:tashil_web/features/product_match/presentation/screens/product_match_review_screen.dart';

class _FakeMatchSource implements ProductMatchDataSource {
  List<ProductMatchReviewItem> items;
  ProductMatchMetrics latestMetrics;
  final List<String> calls = [];

  _FakeMatchSource(this.items, this.latestMetrics);

  @override
  Future<List<ProductMatchReviewItem>> list({String status = 'pending'}) async {
    calls.add('list:$status');
    return items.where((e) => status.isEmpty || e.status == status).toList();
  }

  @override
  Future<ProductMatchMetrics> metrics() async => latestMetrics;

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
          )
        else
          e,
    ];
    latestMetrics = ProductMatchMetrics(
      totalMatched: latestMetrics.totalMatched,
      pending: 0,
      approved: status == 'approved' ? 1 : latestMetrics.approved,
      rejected: status == 'rejected' ? 1 : latestMetrics.rejected,
      inventedBarcodes: 0,
      autoResolveRate: 0.5,
      labelsAr: const {'pending': 'بانتظار المراجعة'},
    );
    return latestMetrics;
  }
}

void main() {
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
    expect(find.text('تشابه متوسط — يحتاج مراجعة بشرية'), findsOneWidget);
    expect(find.text('باركودات مخترعة'), findsOneWidget);
    expect(find.text('0'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('pm_approve_r1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve_product_match_dialog')), findsOneWidget);
    expect(find.textContaining('لن يتم اختراع باركود'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve_match_confirm')));
    await tester.pumpAndSettle();
    expect(src.calls, contains('decide:r1:approved:6223000231227'));
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

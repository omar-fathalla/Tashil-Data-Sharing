import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart';

/// Risk (d): the virtualized table must keep its cells lightweight.
void main() {
  List<SellOutRecordModel> records(int n) => [
        for (var i = 0; i < n; i++)
          SellOutRecordModel(
            recordId: 'r$i',
            retailerChain: i.isEven ? 'carrefour' : 'fathalla',
            storeId: 'S$i',
            storeName: 'فرع $i',
            barcode: '62210011${i.toString().padLeft(5, '0')}',
            skuName: 'صنف $i',
            category: 'زيوت',
            quantitySold: 10 + i,
            unitPrice: 50.0,
            netRevenue: 500.0 + i,
            transactionDate: '2026-10-12',
          ),
      ];

  testWidgets('a page renders only its own rows, with no heavy per-cell widgets',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: VirtualizedSkuTable(records: records(500))),
      ),
    ));
    await tester.pumpAndSettle();

    // Default page size is 10: only 10 of 500 rows should be in the tree.
    expect(find.text('صنف 0'), findsOneWidget);
    expect(find.text('صنف 10'), findsNothing);
    expect(find.text('صنف 499'), findsNothing);

    final table = find.byType(VirtualizedSkuTable);
    // Plain values (no pricing / margin detail) build no metric-cell tooltips:
    // at most one per row (the truncated SKU name) plus a few toolbar ones.
    expect(find.descendant(of: table, matching: find.byType(Tooltip)).evaluate().length,
        lessThanOrEqualTo(10 + 4));
    // No Cards or Material surfaces per row.
    expect(find.descendant(of: table, matching: find.byType(Card)).evaluate().length,
        lessThanOrEqualTo(2));
    // Each row is isolated in its own repaint boundary.
    expect(find.descendant(of: table, matching: find.byType(RepaintBoundary)).evaluate().length,
        greaterThanOrEqualTo(10));
  });
}

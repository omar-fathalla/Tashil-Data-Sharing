import 'package:flutter/material.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/virtualized_sku_table.dart';

void main() {
  final sampleRecords = [
    SellOutRecordModel(
      recordId: 'rec_001',
      retailerChain: 'carrefour',
      storeId: 'CRF_01',
      storeName: 'كارفور المعادي',
      barcode: '6221001122334',
      skuName: 'زيت أديكو ممتاز 1 لتر',
      category: 'زيوت وسمن',
      quantitySold: 450,
      unitPrice: 65.0,
      netRevenue: 29250.0,
      transactionDate: '2026-10-12',
    ),
    SellOutRecordModel(
      recordId: 'rec_002',
      retailerChain: 'fathalla',
      storeId: 'FAT_05',
      storeName: 'فتح الله سموحة',
      barcode: '6221001998877',
      skuName: 'سمن أديكو نقي 750 جم',
      category: 'زيوت وسمن',
      quantitySold: 320,
      unitPrice: 95.0,
      netRevenue: 30400.0,
      transactionDate: '2026-10-12',
    ),
  ];

  group('VirtualizedSkuTable Widget Tests', () {
    testWidgets('renders pinned columns (GTIN barcode & SKU name) and metrics pane', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VirtualizedSkuTable(records: sampleRecords),
            ),
          ),
        ),
      );

      // Verify Table Title & Pinned Column indicator
      expect(find.text('بيانات Sell-Out'), findsOneWidget);
      expect(find.text('2 صف'), findsOneWidget);

      // Verify Pinned Column Headers
      expect(find.text('الباركود'), findsOneWidget);
      expect(find.text('الصنف'), findsOneWidget);

      // Verify Pinned Column Data
      expect(find.text('6221001122334'), findsOneWidget);
      expect(find.text('زيت أديكو ممتاز 1 لتر'), findsOneWidget);
      expect(find.text('6221001998877'), findsOneWidget);
      expect(find.text('سمن أديكو نقي 750 جم'), findsOneWidget);

      // Verify Scrollable Metrics Headers
      expect(find.text('السلسلة'), findsOneWidget);
      expect(find.text('الفرع'), findsOneWidget);
      expect(find.text('الوحدات المباعة'), findsOneWidget);
      expect(find.text('سعر الوحدة'), findsOneWidget);
      expect(find.text('صافي المبيعات (ج.م)'), findsOneWidget);
      expect(find.text('تاريخ البيع'), findsOneWidget);

      // Verify Scrollable Metrics Data
      expect(find.text('كارفور المعادي'), findsOneWidget);
      expect(find.text('فتح الله سموحة'), findsOneWidget);
      expect(find.text('450 وحدة'), findsOneWidget);
      expect(find.text('320 وحدة'), findsOneWidget);
    });

    testWidgets('renders loading state when isLoading is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: VirtualizedSkuTable(records: [], isLoading: true),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders empty state message when records list is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: VirtualizedSkuTable(records: [], isLoading: false),
          ),
        ),
      );

      expect(find.text('لا توجد نتائج. جرّب تغيير الفلاتر.'), findsOneWidget);
      expect(find.byIcon(AppIcons.empty), findsOneWidget);
    });

    testWidgets('supports interactive column sorting ascending and descending', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sortableRecords = [
        SellOutRecordModel(
          recordId: 'rec_b',
          retailerChain: 'fathalla',
          storeId: 'FAT_01',
          storeName: 'فتح الله سموحة',
          barcode: '6221001999999',
          skuName: 'Beta SKU',
          category: 'زيوت',
          quantitySold: 100,
          unitPrice: 50.0,
          netRevenue: 5000.0,
          transactionDate: '2026-03-05',
        ),
        SellOutRecordModel(
          recordId: 'rec_a',
          retailerChain: 'carrefour',
          storeId: 'CRF_01',
          storeName: 'كارفور المعادي',
          barcode: '6221001000001',
          skuName: 'Alpha SKU',
          category: 'زيوت',
          quantitySold: 500,
          unitPrice: 80.0,
          netRevenue: 40000.0,
          transactionDate: '2026-03-07',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VirtualizedSkuTable(records: sortableRecords),
            ),
          ),
        ),
      );

      // Tap 'الكمية المباعة' to sort ascending (100 first, then 500)
      await tester.tap(find.byKey(const ValueKey('sort_header_quantitySold')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      var alphaPos = tester.getTopLeft(find.text('Alpha SKU'));
      var betaPos = tester.getTopLeft(find.text('Beta SKU'));
      expect(betaPos.dy, lessThan(alphaPos.dy));

      // Tap 'الكمية المباعة' again to sort descending (500 first, then 100)
      await tester.tap(find.byKey(const ValueKey('sort_header_quantitySold')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      alphaPos = tester.getTopLeft(find.text('Alpha SKU'));
      betaPos = tester.getTopLeft(find.text('Beta SKU'));
      expect(alphaPos.dy, lessThan(betaPos.dy));
    });

    testWidgets('supports pagination footer and page navigation', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manyRecords = List.generate(
        15,
        (i) => SellOutRecordModel(
          recordId: 'rec_${i + 1}',
          retailerChain: i.isEven ? 'carrefour' : 'fathalla',
          storeId: 'STR_${i + 1}',
          storeName: 'فرع رقم ${i + 1}',
          barcode: '622115500${(1000 + i)}',
          skuName: 'صنف اختبار رقم ${i + 1}',
          category: 'زيوت طعام',
          quantitySold: 100 + i,
          unitPrice: 50.0,
          netRevenue: (100 + i) * 50.0,
          transactionDate: '2026-03-07',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VirtualizedSkuTable(records: manyRecords),
            ),
          ),
        ),
      );

      // Default page size is 10 -> shows 1 - 10 of 15
      expect(find.text('1–10 من 15'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 1'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 10'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 11'), findsNothing);

      // Navigate to next page
      await tester.tap(find.byKey(const ValueKey('pagination_next_btn')));
      await tester.pumpAndSettle();

      expect(find.text('11–15 من 15'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 11'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 15'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 1'), findsNothing);

      // Navigate back to previous page
      await tester.tap(find.byKey(const ValueKey('pagination_prev_btn')));
      await tester.pumpAndSettle();

      expect(find.text('1–10 من 15'), findsOneWidget);

      // Change rows per page from 10 to 25
      await tester.tap(find.byKey(const ValueKey('rows_per_page_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25').last);
      await tester.pumpAndSettle();

      expect(find.text('1–15 من 15'), findsOneWidget);
      expect(find.text('صنف اختبار رقم 15'), findsOneWidget);
    });

    testWidgets('renders cleanly on compact 360px mobile viewport without RenderFlex overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: VirtualizedSkuTable(records: sampleRecords),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1–2 من 2'), findsOneWidget);
    });
  });
}


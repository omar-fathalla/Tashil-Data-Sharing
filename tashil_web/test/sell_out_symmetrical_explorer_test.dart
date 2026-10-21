import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

void main() {
  group('SellOutExplorerScreen Symmetrical Redesign Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets('renders 4 symmetrical English tabs and 4 Executive KPI cards on Tab 0',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellOutExplorerScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify 4 Symmetrical Tabs (English Only) in SegmentedButton
      expect(find.text('Sell-Out Data & Operations'), findsOneWidget);
      expect(find.text('Performance & Branch Analytics'), findsOneWidget);
      expect(find.text('Target Management (Sell-Out)'), findsOneWidget);
      expect(find.textContaining('Uploaded Sheets'), findsOneWidget);

      // 2. Verify 4 Executive KPI Cards on Tab 0
      expect(find.text('إجمالي صافي المبيعات'), findsOneWidget);
      expect(find.text('Total Net Revenue (EGP)'), findsOneWidget);

      expect(find.text('إجمالي الكمية المباعة'), findsOneWidget);
      expect(find.text('Total Units Sold'), findsOneWidget);

      expect(find.text('متوسط سعر الوحدة'), findsOneWidget);
      expect(find.text('Average Unit Price (EGP)'), findsOneWidget);

      expect(find.text('إجمالي الفروع النشطة'), findsOneWidget);
      expect(find.text('Active Stores & Outlets'), findsOneWidget);

      // 3. Verify Action Buttons: Upload Sell-Out, Export Excel, Print PDF
      expect(find.byKey(const ValueKey('upload_sellout_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_excel_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_pdf_button')), findsOneWidget);
    });

    testWidgets('switches to Tab 1 (Performance & Branch Analytics) and displays Pareto & Branch Velocity',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellOutExplorerScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 1
      await tester.tap(find.text('Performance & Branch Analytics'));
      await tester.pumpAndSettle();

      // Verify Tab 1 KPI Cards
      expect(find.text('أعلى صنف مبيعاً'), findsOneWidget);
      expect(find.text('Top Performing SKU'), findsOneWidget);
      expect(find.text('مؤشر باريتو (Pareto 80/20)'), findsOneWidget);
      expect(find.text('Top 20% SKU Revenue Share'), findsOneWidget);
      expect(find.text('أعلى فرع مبيعاً'), findsOneWidget);
      expect(find.text('Top Revenue Branch'), findsOneWidget);
      expect(find.text('متوسط مبيعات الفرع'), findsOneWidget);
      expect(find.text('Average Store Velocity'), findsOneWidget);

      // Verify Tables
      expect(find.textContaining('Branch Sales Velocity'), findsOneWidget);
      expect(find.textContaining('SKU Pareto Breakdown'), findsOneWidget);
    });

    testWidgets('switches to Tab 2 (Target Management) and renders TargetManagementPanel',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellOutExplorerScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 2
      await tester.tap(find.text('Target Management (Sell-Out)'));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('sell_out_targets_${apiClient.tenantId}')), findsOneWidget);
    });

    testWidgets('switches to Tab 3 (Uploaded Sheets) and displays upload banner and archived files table',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellOutExplorerScreen(apiClient: apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 3
      final tab3Finder = find.textContaining('Uploaded Sheets');
      await tester.ensureVisible(tab3Finder);
      await tester.tap(tab3Finder);
      await tester.pumpAndSettle();

      // Verify Upload Banner & Controls
      expect(find.textContaining('إدارة شيتات الإكسيل المرفوعة للـ Sell-Out'), findsOneWidget);
      expect(find.text('Upload Sell Out'), findsOneWidget);
      expect(find.text('تحديث القائمة'), findsOneWidget);
      expect(find.text('Target Chain'), findsOneWidget);
    });
  });
}

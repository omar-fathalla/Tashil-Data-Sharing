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

      expect(find.text('الأصناف النشطة ومتوسط الفرع'), findsOneWidget);
      expect(find.text('Active SKUs & Branch Velocity'), findsOneWidget);

      expect(find.text('إجمالي الفروع النشطة'), findsOneWidget);
      expect(find.text('Active Stores & Outlets'), findsOneWidget);

      // 3. Verify Full-Width Branch Sales Ranking Chart with Year 2026 Default & Two-Row Layout
      expect(find.byKey(const ValueKey('full_width_branch_sales_chart')), findsOneWidget);
      expect(find.text('شارت ترتيب مبيعات فروع السلسلة من الأعلى للأقل'), findsOneWidget);
      expect(find.text('Branch Sales Ranking Chart'), findsOneWidget);
      expect(find.textContaining('الصف الأول: الفروع الأعلى مبيعاً'), findsOneWidget);
      expect(find.textContaining('الصف الثاني: باقي فروع السلسلة'), findsOneWidget);
      expect(find.byKey(const ValueKey('branch_chart_year_2026')), findsOneWidget);
      expect(find.byKey(const ValueKey('branch_chart_year_2025')), findsOneWidget);

      // 4. Verify Action Buttons: Upload Sell-Out, Export Excel, Print PDF
      expect(find.byKey(const ValueKey('upload_sellout_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_excel_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_pdf_button')), findsOneWidget);
    });

    testWidgets('switches Year between 2026 (Default) and 2025 in Full-Width Branch Sales Chart',
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

      // Default year is 2026
      expect(find.textContaining('سنة 2026'), findsWidgets);
      expect(find.textContaining('34 فرع'), findsWidgets);

      // Switch to Year 2025 using the chart year button
      final year2025Btn = find.byKey(const ValueKey('branch_chart_year_2025'));
      await tester.ensureVisible(year2025Btn);
      await tester.tap(year2025Btn);
      await tester.pumpAndSettle();

      expect(find.textContaining('سنة 2025'), findsWidgets);
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

      // Verify Tab 1 Year (2026 Default) and Month Filter Dropdowns
      expect(find.byKey(const ValueKey('perf_year_dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf_month_dropdown')), findsOneWidget);
      expect(find.text('2026 (Default)'), findsOneWidget);
      expect(find.text('كل الشهور'), findsOneWidget);

      // Verify Tables (SKU Pareto Breakdown table was removed and replaced with Branch YoY & MoM Growth Matrix)
      expect(find.textContaining('Branch Sales Velocity'), findsOneWidget);
      expect(find.textContaining('SKU Pareto Breakdown'), findsNothing);
      expect(find.byKey(const ValueKey('branch_growth_matrix_section')), findsOneWidget);
      expect(find.textContaining('مقارنة نمو وتراجع الفروع سنوياً وشهرياً'), findsOneWidget);
      expect(find.textContaining('Branch YoY & MoM Growth Matrix'), findsOneWidget);
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

      // Open Add Target Manually dialog and verify dynamic future years formula (2026, 2027, 2028)
      await tester.tap(find.text('Add Target Manually'));
      await tester.pumpAndSettle();

      final yearDropdown = find.byKey(const ValueKey('target_dialog_year_dropdown'));
      expect(yearDropdown, findsOneWidget);
      await tester.tap(yearDropdown);
      await tester.pumpAndSettle();

      expect(find.text('2026'), findsWidgets);
      expect(find.text('2027'), findsWidgets);
      expect(find.text('2028'), findsWidgets);
      expect(find.text('2024'), findsNothing);
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

    test('parses enriched SellOutRecordModel, SellOutSkuSummaryModel, and SellOutRecordsSummaryModel accurately', () {
      final summaryJson = {
        'total_net_revenue': 125000.0,
        'total_units_sold': 1200,
        'total_cartons_sold': 100.0,
        'total_factory_cost': 108000.0,
        'total_retailer_gross_profit': 17000.0,
        'avg_retailer_margin_pct': 13.6,
        'matched_skus_count': 214,
        'active_skus_count': 214,
        'active_stores_count': 34,
        'sku_summaries': [
          {
            'item_code': 'FGCL-1050-0001',
            'barcode': '6223000230015',
            'sku_name': 'كلوريل أبيض 1050 جم',
            'retailer_raw_sku_name': 'كلوريل ابيض 1050ج',
            'brand': 'كلوريل (Clorel)',
            'category': 'منظفات ومطهرات',
            'item_type': 'عادي',
            'packaging_type': 'زجاجة',
            'units_per_carton': 12,
            'total_units_sold': 120,
            'total_cartons_sold': 10.0,
            'total_net_revenue': 3000.0,
            'avg_selling_price': 25.0,
            'official_consumer_rsp': 25.0,
            'carton_price_incl_vat': 300.0,
            'factory_unit_cost': 22.5,
            'net_carton_invoice_cost': 270.0,
            'total_factory_cost': 2700.0,
            'retailer_gross_profit': 300.0,
            'retailer_margin_pct': 10.0,
            'price_delta_pct': 0.0,
            'active_stores_count': 12,
          }
        ],
      };

      final summary = SellOutRecordsSummaryModel.fromJson(summaryJson);
      expect(summary.totalCartonsSold, 100.0);
      expect(summary.totalFactoryCost, 108000.0);
      expect(summary.totalRetailerGrossProfit, 17000.0);
      expect(summary.avgRetailerMarginPct, 13.6);
      expect(summary.matchedSkusCount, 214);
      expect(summary.skuSummaries, hasLength(1));

      final sku = summary.skuSummaries.first;
      expect(sku.itemCode, 'FGCL-1050-0001');
      expect(sku.retailerRawSkuName, 'كلوريل ابيض 1050ج');
      expect(sku.unitsPerCarton, 12);
      expect(sku.totalCartonsSold, 10.0);
      expect(sku.factoryUnitCost, 22.5);
      expect(sku.netCartonInvoiceCost, 270.0);
      expect(sku.retailerMarginPct, 10.0);
    });
  });
}


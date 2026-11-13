import 'package:tashil_web/core/widgets/app_icons.dart';
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

      // 1. Verify 4 Symmetrical Tabs (Arabic content labels)
      expect(find.text('بيانات المبيعات'), findsOneWidget);
      expect(find.text('أداء الفروع'), findsOneWidget);
      expect(find.text('المستهدفات'), findsOneWidget);
      expect(find.textContaining('الملفات المرفوعة'), findsOneWidget);

      // 2. Verify 4 Executive KPI Cards on Tab 0
      expect(find.text('صافي المبيعات'), findsOneWidget);
      expect(find.text('Net Sales (EGP)'), findsNothing);

      expect(find.text('إجمالي الكمية المباعة'), findsOneWidget);
      expect(find.text('Total Units Sold'), findsNothing);

      expect(find.text('الأصناف النشطة'), findsOneWidget);
      expect(find.text('Active SKUs'), findsNothing);

      expect(find.text('الفروع النشطة'), findsOneWidget);
      expect(find.text('Active Stores'), findsNothing);

      // 2b. All 4 KPI cards share identical width, height and top/bottom edges
      final kpiRects = [
        'Net Sales (EGP)',
        'Total Units Sold',
        'Active SKUs',
        'Active Stores',
      ].map((t) => tester.getRect(find.byKey(ValueKey('kpi_card_$t')))).toList();
      for (final r in kpiRects.skip(1)) {
        expect(r.height, closeTo(kpiRects.first.height, 0.5));
        expect(r.width, closeTo(kpiRects.first.width, 0.5));
        expect(r.top, closeTo(kpiRects.first.top, 0.5));
        expect(r.bottom, closeTo(kpiRects.first.bottom, 0.5));
      }

      // 3. Verify Full-Width Branch Sales Ranking Chart with Year 2026 Default & Two-Row Layout
      expect(find.byKey(const ValueKey('full_width_branch_sales_chart')), findsOneWidget);
      expect(find.text('ترتيب الفروع حسب المبيعات'), findsOneWidget);
      expect(find.text('Store Ranking by Sales'), findsNothing);
      // Vertical columns mode is removed entirely; chart starts collapsed.
      expect(find.textContaining('الصف الأول: الفروع الأعلى مبيعاً'), findsNothing);
      expect(find.byKey(const ValueKey('branch_chart_layout_toggle')), findsNothing);
      expect(find.byKey(const ValueKey('branch_chart_header')), findsOneWidget);
      expect(find.byIcon(AppIcons.expandMore), findsOneWidget);
      expect(find.byKey(const ValueKey('branch_growth_slot_1')), findsNothing);

      // Expand: horizontal bar list appears with identical fixed-width growth slots.
      await tester.ensureVisible(find.byKey(const ValueKey('branch_chart_header')));
      await tester.tap(find.byKey(const ValueKey('branch_chart_header')));
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.expandLess), findsOneWidget);
      final slots = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('branch_growth_slot_'));
      expect(slots, findsWidgets);
      for (final e in slots.evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).width, closeTo(64.0, 0.1));
      }

      // Collapse again.
      await tester.tap(find.byKey(const ValueKey('branch_chart_header')));
      await tester.pumpAndSettle();
      expect(slots, findsNothing);
      expect(find.byIcon(AppIcons.expandMore), findsOneWidget);
      final yearBtn = find.byKey(const ValueKey('branch_chart_year_dropdown'));
      expect(yearBtn, findsOneWidget);
      expect(find.text('سنة البيانات: 2026'), findsOneWidget);
      // One line, 40dp (was a 3-segment control that wrapped and clipped).
      expect(tester.getSize(yearBtn).height, greaterThanOrEqualTo(40.0));
      expect(tester.getSize(find.text('سنة البيانات: 2026')).height, lessThanOrEqualTo(20.5));
      expect(tester.getSize(find.byKey(const ValueKey('branch_chart_sort_toggle'))).height,
          greaterThanOrEqualTo(40.0));

      // 4. Verify Action Buttons: Upload Sell-Out, Export Excel, Print PDF
      expect(find.byKey(const ValueKey('upload_sellout_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_excel_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('export_pdf_button')), findsOneWidget);

      // 4b. Action buttons sit flush at the row's end, adjacent to each other
      final excel = tester.getRect(find.byKey(const ValueKey('export_excel_button')));
      final pdf = tester.getRect(find.byKey(const ValueKey('export_pdf_button')));
      final up = tester.getRect(find.byKey(const ValueKey('upload_sellout_button')));
      expect((excel.center.dy - pdf.center.dy).abs(), lessThan(1.0));
      expect((pdf.center.dy - up.center.dy).abs(), lessThan(1.0));
      final gaps = [ (pdf.left - excel.right).abs(), (excel.left - pdf.right).abs() ]..sort();
      expect(gaps.first, lessThan(16.0));
    });

    testWidgets('switches Year between 2026 and 2025 in Full-Width Branch Sales Chart',
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

      // Switch to Year 2025 via the year menu filter
      final yearBtn = find.byKey(const ValueKey('branch_chart_year_dropdown'));
      await tester.ensureVisible(yearBtn);
      await tester.tap(yearBtn);
      await tester.pumpAndSettle();
      // Other menus on the page also list years: scope to this filter's anchor.
      final yearMenu = find.ancestor(of: yearBtn, matching: find.byType(MenuAnchor)).first;
      await tester.tap(find.descendant(of: yearMenu, matching: find.text('2025')));
      await tester.pumpAndSettle();

      expect(find.text('سنة البيانات: 2025'), findsOneWidget);
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
      await tester.tap(find.text('أداء الفروع').first);
      await tester.pumpAndSettle();

      // Verify Tab 1 KPI Cards
      expect(find.text('الصنف الأعلى مبيعًا'), findsOneWidget);
      expect(find.text('Top SKU'), findsNothing);
      expect(find.text('حصة أعلى 20% من الأصناف'), findsOneWidget);
      expect(find.text("Top 20% SKUs' Share"), findsNothing);
      expect(find.text('الفرع الأعلى مبيعًا'), findsOneWidget);
      expect(find.text('Top Store'), findsNothing);
      expect(find.text('متوسط مبيعات الفرع'), findsOneWidget);
      expect(find.text('Avg. Sales per Store'), findsNothing);

      // Verify Tab 1 Year (2026 Default) and Month Filter Dropdowns
      expect(find.byKey(const ValueKey('perf_year_dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf_month_dropdown')), findsOneWidget);
      expect(find.text('2026'), findsWidgets);
      expect(find.textContaining('Default'), findsNothing);
      expect(find.text('كل الشهور'), findsWidgets);

      // Verify Tables (SKU Pareto Breakdown table was removed and replaced with Branch YoY & MoM Growth Matrix)
      expect(find.text('أداء الفروع'), findsWidgets);
      expect(find.textContaining('SKU Pareto Breakdown'), findsNothing);
      expect(find.byKey(const ValueKey('branch_growth_matrix_section')), findsOneWidget);
      expect(find.textContaining('نمو الفروع: '), findsOneWidget);
      expect(find.textContaining('نمو الفروع (سنوي وشهري)'), findsOneWidget);
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
      await tester.tap(find.text('المستهدفات'));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('sell_out_targets_${apiClient.tenantId}')), findsOneWidget);

      // Open Add Target Manually dialog and verify dynamic future years formula (2026, 2027, 2028)
      await tester.tap(find.text('إضافة مستهدف').first);
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
      final tab3Finder = find.textContaining('الملفات المرفوعة');
      await tester.ensureVisible(tab3Finder);
      await tester.tap(tab3Finder);
      await tester.pumpAndSettle();

      // Verify Upload Banner & Controls
      expect(find.textContaining('ملفات Sell-Out المرفوعة'), findsOneWidget);
      expect(find.text('رفع ملف Sell-Out'), findsOneWidget);
      expect(find.text('تحديث'), findsOneWidget);
      expect(find.text('السلسلة'), findsWidgets);
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


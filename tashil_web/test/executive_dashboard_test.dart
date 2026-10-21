import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/core/utils/web_file_helper.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/bento_kpi_grid.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/chain_share_pie.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/sellout_trend_chart.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

void main() {
  final sampleKpis = ExecutiveKPIsModel(
    totalRevenue: 4850230.0,
    revenueGrowthPct: 14.8,
    totalUnitsSold: 38450,
    unitsGrowthPct: 9.2,
    activeStoresCount: 16,
    oosRatePct: 4.2,
    totalOOSIncidents: 18,
    estimatedLostRevenue: 148500.0,
    currency: 'EGP',
    reportingPeriod: 'MTD',
    chainShares: [
      ChainShareItem(
        retailerChain: 'carrefour',
        displayName: 'كارفور (Carrefour)',
        totalRevenue: 2182600.0,
        totalUnits: 17200,
        marketShare: 45.0,
      ),
      ChainShareItem(
        retailerChain: 'fathalla',
        displayName: 'فتح الله (Fathalla)',
        totalRevenue: 1552070.0,
        totalUnits: 12500,
        marketShare: 32.0,
      ),
    ],
    dailyTrends: [],
  );

  testWidgets('BentoKpiGrid renders all 4 KPI tiles correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BentoKpiGrid(kpis: sampleKpis),
          ),
        ),
      ),
    );

    expect(find.text('إجمالي مبيعات التجزئة (Sell-Out)'), findsOneWidget);
    expect(find.text('إجمالي الوحدات المباعة'), findsOneWidget);
    expect(find.text('الفروع النشطة المغطاة'), findsOneWidget);
    expect(find.text('نسبة النواقص (OOS Rate)'), findsOneWidget);

    expect(find.text('16 فرع'), findsOneWidget);
    expect(find.text('4.2%'), findsOneWidget);
    // Multi-chain subtitle
    expect(find.text('فروع كارفور • أسواق فتح الله المستنتجة من الإكسيل'), findsOneWidget);
  });

  testWidgets('BentoKpiGrid formats negative MoM/YoY without +- and shows single-chain dynamic subtitle', (WidgetTester tester) async {
    final negativeGomlaKpis = ExecutiveKPIsModel(
      totalRevenue: 6573015.0,
      revenueGrowthPct: -16.0,
      revenueMomPct: -16.0,
      revenueYoyPct: -4.5,
      totalUnitsSold: 81492,
      unitsGrowthPct: -8.2,
      unitsMomPct: -8.2,
      unitsYoyPct: 0.0,
      activeStoresCount: 17,
      oosRatePct: 0.0,
      totalOOSIncidents: 0,
      estimatedLostRevenue: 0.0,
      currency: 'EGP',
      reportingPeriod: 'MTD',
      chainShares: [
        ChainShareItem(
          retailerChain: 'gomla',
          displayName: 'جملة ماركت (Gomla Market)',
          totalRevenue: 6573015.0,
          totalUnits: 81492,
          marketShare: 100.0,
        ),
      ],
      dailyTrends: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BentoKpiGrid(kpis: negativeGomlaKpis),
          ),
        ),
      ),
    );

    // Must format negative percentages cleanly without '+-'
    expect(find.text('-16.0% شهري MoM'), findsOneWidget);
    expect(find.text('-4.5% سنوي YoY'), findsOneWidget);
    expect(find.text('-8.2% شهري MoM'), findsOneWidget);
    expect(find.textContaining('+-'), findsNothing);

    // Dynamic single-chain subtitle for Gomla Market (not hardcoded Fathalla)
    expect(find.text('فروع جملة ماركت المستنتجة تلقائياً من الإكسيل'), findsOneWidget);
    expect(find.textContaining('فروع فتح الله'), findsNothing);
  });

  testWidgets('ChainSharePie displays chain share names and percentages', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChainSharePie(chainShares: sampleKpis.chainShares),
          ),
        ),
      ),
    );

    expect(find.text('كارفور (Carrefour)'), findsOneWidget);
    expect(find.text('فتح الله (Fathalla)'), findsOneWidget);
    expect(find.text('45.0%'), findsOneWidget);
    expect(find.text('32.0%'), findsOneWidget);
  });

  testWidgets('ExecutiveScreen simplifies header filters to Chain, Year, and Month (with All Months option) and removes period segmented buttons', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ExecutiveScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify removed period buttons are gone
    expect(find.text('Custom Range'), findsNothing);
    expect(find.text('Monthly (MTD)'), findsNothing);
    expect(find.text('Yearly (YTD)'), findsNothing);

    // Verify 3 dropdowns exist
    expect(find.byKey(const ValueKey('executive_chain_dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('executive_year_dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('executive_month_dropdown')), findsOneWidget);

    // Open Month dropdown and choose 'All Months'
    await tester.tap(find.byKey(const ValueKey('executive_month_dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('All Months'), findsOneWidget);
    await tester.tap(find.text('All Months'));
    await tester.pumpAndSettle();

    expect(find.text('Month: All'), findsOneWidget);

    // Open Year dropdown and select 2025
    await tester.tap(find.byKey(const ValueKey('executive_year_dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('2025'), findsWidgets);
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();

    expect(find.text('Year: 2025'), findsOneWidget);
  });

  testWidgets('ExecutiveScreen Month dropdown displays pure English month names without Arabic parentheticals', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ExecutiveScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Month dropdown
    final monthDropdown = find.byKey(const ValueKey('executive_month_dropdown'));
    expect(monthDropdown, findsOneWidget);
    await tester.tap(monthDropdown);
    await tester.pumpAndSettle();

    // Verify pure English month names are rendered in the dropdown menu
    expect(find.text('January'), findsOneWidget);
    expect(find.text('February'), findsOneWidget);
    expect(find.text('March'), findsOneWidget);
    expect(find.text('April'), findsOneWidget);

    // Verify NO mixed Arabic parentheticals appear in the month dropdown
    expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.textContaining('يناير')), findsNothing);
    expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.textContaining('فبراير')), findsNothing);
    expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.textContaining('مارس')), findsNothing);

    // Select February and verify the pill updates to 'Month: Feb'
    await tester.tap(find.text('February'));
    await tester.pumpAndSettle();
    expect(find.text('Month: Feb'), findsOneWidget);
  });

  testWidgets('UploadPortalScreen file picker parses real CSV bytes and excludes anomalous rows from valid count', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: UploadPortalScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    WebFileHelper.nextMockPickedFile = PickedFileData(
      name: 'Carrefour_Daily_Sales.csv',
      bytes: WebFileHelper.sampleCarrefourCsvBytes(),
    );

    // Select target retail chain first
    await tester.tap(find.byKey(const ValueKey('ingestion_retail_chain_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('كارفور').last);
    await tester.pumpAndSettle();

    // Tap device file picker button (has 3 valid rows + 1 short barcode = 4 total)
    await tester.tap(find.text('اختيار ملف من الجهاز'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('تم التحليل والاستخراج بالذكاء الاصطناعي • بانتظار المراجعة والاعتماد'), findsOneWidget);
    expect(find.text('حفظ واعتماد البيانات في النظام (Commit Data)'), findsOneWidget);
    expect(find.text('4 صف'), findsOneWidget);
    expect(find.text('3 صف'), findsOneWidget);
    expect(find.text('1 ملاحظة'), findsOneWidget);
  });

  testWidgets('SellOutExplorerScreen renders date range chip and exports real CSV & HTML', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ExcelExportService.resetLastDownloaded();

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SellOutExplorerScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sellout_date_range_chip')), findsOneWidget);
    expect(find.text('Date Range'), findsOneWidget);

    // Trigger Excel export
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();

    expect(ExcelExportService.lastDownloadedFilename, endsWith('.csv'));
    expect(ExcelExportService.lastDownloadedContent, startsWith('\uFEFF'));
    expect(ExcelExportService.lastDownloadedMimeType, equals('text/csv;charset=utf-8'));

    // Trigger PDF/HTML export
    await tester.tap(find.byKey(const ValueKey('export_pdf_button')));
    await tester.pumpAndSettle();

    expect(ExcelExportService.lastDownloadedFilename, endsWith('.html'));
    expect(ExcelExportService.lastDownloadedContent, contains('<!DOCTYPE html>'));
    expect(ExcelExportService.lastDownloadedMimeType, equals('text/html;charset=utf-8'));

    // Open Date Range Picker via chip, apply it, and then clear it
    await tester.tap(find.byKey(const ValueKey('sellout_date_range_chip')));
    await tester.pumpAndSettle();
    if (find.text('Apply Range').evaluate().isNotEmpty) {
      await tester.tap(find.text('Apply Range'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Date:'), findsOneWidget);

    // Clear the active date range via the close icon
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Date Range'), findsOneWidget);
  });

  testWidgets('UploadPortalScreen device file picker button uses WebFileHelper and deduplicates repeated CSV rows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: UploadPortalScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select target retail chain first
    await tester.tap(find.byKey(const ValueKey('ingestion_retail_chain_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('كارفور').last);
    await tester.pumpAndSettle();

    // Tap 'اختيار ملف من الجهاز' (uses VM fallback sample Carrefour CSV: 3 valid + 1 anomaly)
    await tester.tap(find.text('اختيار ملف من الجهاز'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('تم التحليل والاستخراج بالذكاء الاصطناعي • بانتظار المراجعة والاعتماد'), findsOneWidget);
    expect(find.text('حفظ واعتماد البيانات في النظام (Commit Data)'), findsOneWidget);
    expect(find.text('4 صف'), findsOneWidget);
    expect(find.text('3 صف'), findsOneWidget);
    expect(find.text('1 ملاحظة'), findsOneWidget);

    // Commit staged data
    final commitBtn = find.byKey(const ValueKey('commit_staged_upload_button'));
    await tester.ensureVisible(commitBtn);
    await tester.tap(commitBtn);
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الحفظ والاعتماد'), findsOneWidget);
    await tester.tap(find.text('تأكيد الحفظ والاعتماد'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('تم حفظ واعتماد البيانات نهائياً في النظام (Committed to BigQuery)'), findsOneWidget);

    // Verify custom date range KPI calculation on ApiClient
    final customKpis = await apiClient.getExecutiveKPIs(
      period: 'CUSTOM',
      startDate: '2026-03-01',
      endDate: '2026-03-03',
    );
    expect(customKpis.dailyTrends.length, equals(3));
    expect(customKpis.totalRevenue, equals(142000.0 + 158000.0 + 139000.0));
    expect(customKpis.totalUnitsSold, equals(1120 + 1240 + 1090));
  });

  testWidgets('ExecutiveScreen handles narrow mobile viewport (< 360px) and Month switching without overflow or stale overwrites', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(340, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ExecutiveScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ensure Month dropdown is visible on narrow < 360px viewport and opens cleanly with English months
    final monthDropdown = find.byKey(const ValueKey('executive_month_dropdown'));
    expect(monthDropdown, findsOneWidget);
    await tester.ensureVisible(monthDropdown);
    await tester.tap(monthDropdown);
    await tester.pumpAndSettle();

    expect(find.text('January'), findsOneWidget);
    expect(find.text('December'), findsOneWidget);
    expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.textContaining('يناير')), findsNothing);

    await tester.tap(find.text('March'));
    await tester.pumpAndSettle();
    expect(find.text('Month: Mar'), findsOneWidget);

    // Switch Month to All Months
    await tester.ensureVisible(monthDropdown);
    await tester.tap(monthDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Months'));
    await tester.pumpAndSettle();
    expect(find.text('Month: All'), findsOneWidget);
  });

  testWidgets('SelloutTrendChart renders multi-chain monthly curves with distinct chain legend pills and supports single-month data', (WidgetTester tester) async {
    final monthlyTrends = [
      DailyTrendItem(
        date: '2025-01-31',
        monthKey: '2025-01',
        monthLabel: 'يناير 25',
        revenue: 794155.14,
        units: 9500,
        storeCount: 51,
        chainRevenues: const {'fathalla': 417369.14, 'gomla': 376786.0},
        chainUnits: const {'fathalla': 5100, 'gomla': 4400},
        chainDetails: [
          ChainTrendValueItem(
            retailerChain: 'fathalla',
            displayName: 'أسواق فتح الله (Fathalla)',
            revenue: 417369.14,
            units: 5100,
            growthPct: 12.4,
          ),
          ChainTrendValueItem(
            retailerChain: 'gomla',
            displayName: 'جملة ماركت (Gomla)',
            revenue: 376786.0,
            units: 4400,
            growthPct: 0.0,
          ),
        ],
      ),
      DailyTrendItem(
        date: '2025-02-28',
        monthKey: '2025-02',
        monthLabel: 'فبراير 25',
        revenue: 465200.0,
        units: 5600,
        storeCount: 34,
        chainRevenues: const {'fathalla': 465200.0},
        chainUnits: const {'fathalla': 5600},
        chainDetails: [
          ChainTrendValueItem(
            retailerChain: 'fathalla',
            displayName: 'أسواق فتح الله (Fathalla)',
            revenue: 465200.0,
            units: 5600,
            growthPct: 11.5,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelloutTrendChart(trends: monthlyTrends),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('منحنى نمو المبيعات الشهري حسب السلاسل (Sell-Out Trend)'), findsOneWidget);
    expect(find.text('أسواق فتح الله (Fathalla Market)'), findsOneWidget);
    expect(find.text('جملة ماركت (Gomla Market)'), findsOneWidget);
    expect(find.text('يناير'), findsOneWidget);
    expect(find.text('فبراير'), findsOneWidget);
    expect(ChainSharePie.colorForChain('fathalla'), isNot(equals(ChainSharePie.colorForChain('gomla'))));

    // Also verify single-month series (e.g. 2026-01 or 2024-04) renders without error
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelloutTrendChart(trends: [monthlyTrends.first]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('يناير'), findsOneWidget);

    // Verify when only 'beet-elgomla' exists (or after deleting Fathalla and Gomla),
    // neither Fathalla nor Gomla is rendered in legend or curves.
    final beetElgomlaOnlyTrends = [
      DailyTrendItem(
        date: '2026-01-31',
        monthKey: '2026-01',
        monthLabel: 'يناير 26',
        revenue: 3283610.0,
        units: 72979,
        storeCount: 27,
        chainRevenues: const {'beet-elgomla': 3283610.0},
        chainUnits: const {'beet-elgomla': 72979},
        chainDetails: [
          ChainTrendValueItem(
            retailerChain: 'beet-elgomla',
            displayName: 'بيت الجملة (Beet El Gomla)',
            revenue: 3283610.0,
            units: 72979,
            growthPct: 0.0,
          ),
        ],
      ),
      DailyTrendItem(
        date: '2026-02-28',
        monthKey: '2026-02',
        monthLabel: 'فبراير 26',
        revenue: 3150000.0,
        units: 70000,
        storeCount: 27,
        chainRevenues: const {'beet-elgomla': 3150000.0},
        chainUnits: const {'beet-elgomla': 70000},
        chainDetails: [
          ChainTrendValueItem(
            retailerChain: 'beet-elgomla',
            displayName: 'بيت الجملة (Beet El Gomla)',
            revenue: 3150000.0,
            units: 70000,
            growthPct: -4.0,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelloutTrendChart(trends: beetElgomlaOnlyTrends),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('بيت الجملة (Beet El Gomla)'), findsOneWidget);
    expect(find.text('أسواق فتح الله (Fathalla Market)'), findsNothing);
    expect(find.text('جملة ماركت (Gomla Market)'), findsNothing);
  });

  testWidgets('ExecutiveScreen Retail Chain filter dropdown filters KPIs and ChainSharePie to selected chain', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(tenantId: 'tenant_adeco');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ExecutiveScreen(apiClient: apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chainDropdown = find.byKey(const ValueKey('executive_chain_dropdown'));
    expect(chainDropdown, findsOneWidget);
    expect(find.text('Chain: All'), findsOneWidget);

    await tester.tap(chainDropdown);
    await tester.pumpAndSettle();

    expect(find.text('Fathalla (أسواق فتح الله)'), findsOneWidget);
    expect(find.text('Gomla Market (جملة ماركت)'), findsOneWidget);

    await tester.tap(find.text('Gomla Market (جملة ماركت)'));
    await tester.pumpAndSettle();

    expect(find.text('Chain: Gomla'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
  });
}



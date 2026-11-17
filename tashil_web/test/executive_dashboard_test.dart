import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';

import 'helpers/m3_dropdown_tester.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/core/utils/web_file_helper.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/bento_kpi_grid.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/chain_share_pie.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';
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

  testWidgets('BentoKpiGrid renders all 4 KPI tiles correctly',
      (WidgetTester tester) async {
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

    expect(find.text('إجمالي Sell-Out'), findsOneWidget);
    expect(find.text('Total Sell-Out (EGP)'),
        findsNothing); // Arabic-only M3 KPI card
    expect(find.text('إجمالي الوحدات المباعة'), findsOneWidget);
    expect(
        find.text('Total Units Sold'), findsNothing); // Arabic-only M3 KPI card
    expect(find.text('الفروع النشطة'), findsOneWidget);
    expect(find.text('Active Stores'), findsNothing); // Arabic-only M3 KPI card
    expect(find.text('نسبة النفاد'), findsOneWidget);
    expect(find.text('OOS Rate'), findsNothing); // Arabic-only M3 KPI card

    expect(find.text('16 فرعًا'), findsOneWidget);
    expect(find.text('4.2%'), findsOneWidget);
    // Multi-chain subtitle
    expect(find.text('كارفور • أسواق فتح الله'), findsOneWidget);
  });

  testWidgets(
      'BentoKpiGrid formats negative MoM/YoY without +- and shows single-chain dynamic subtitle',
      (WidgetTester tester) async {
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

    // Must format negative percentages with LRI + U+2212 (never '+-' or a trailing minus)
    expect(find.textContaining(CurrencyFormatter.formatSignedPct(-16.0)), findsWidgets);
    expect(find.text('MoM'), findsNothing);
    expect(find.textContaining(CurrencyFormatter.formatSignedPct(-4.5)), findsOneWidget);
    expect(find.textContaining('مقارنة بالعام السابق'), findsWidgets);
    expect(find.text('YoY'), findsNothing);
    expect(find.textContaining(CurrencyFormatter.formatSignedPct(-8.2)), findsWidgets);
    expect(find.textContaining('+-'), findsNothing);
    expect(find.textContaining('-16.0%'), findsNothing);

    // Dynamic single-chain subtitle for Gomla Market (not hardcoded Fathalla)
    expect(find.text('جملة ماركت'), findsOneWidget);
    expect(find.textContaining('فروع فتح الله'), findsNothing);
  });

  testWidgets(
      'ChainSharePie displays chain share names (Arabic Line 1, English Line 2) and percentages',
      (WidgetTester tester) async {
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

    expect(find.text('حصة كل سلسلة من المبيعات'), findsOneWidget);
    expect(find.text('Sales by Chain'), findsNothing);
    expect(find.text('كارفور'), findsOneWidget);
    expect(find.text('Carrefour'), findsOneWidget);
    expect(find.text('فتح الله'), findsOneWidget);
    expect(find.text('Fathalla'), findsOneWidget);
    expect(find.text('45.0%'), findsOneWidget);
    expect(find.text('32.0%'), findsOneWidget);
  });

  testWidgets(
      'ExecutiveScreen simplifies header filters to Chain, Year, and Month (with All Months option) and removes period segmented buttons',
      (WidgetTester tester) async {
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
    expect(
        find.byKey(const ValueKey('executive_chain_dropdown')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('executive_year_dropdown')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('executive_month_dropdown')), findsOneWidget);

    // Open Month dropdown and choose 'كل الشهور'
    await tester.tap(find.byKey(const ValueKey('executive_month_dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('كل الشهور'), findsOneWidget);
    await tester.tap(find.text('كل الشهور'));
    await tester.pumpAndSettle();

    expect(find.text('الشهر: الكل'), findsOneWidget);

    // Select 2025 in the year menu filter
    await tester.tap(find.byKey(const ValueKey('executive_year_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();
    expect(find.text('السنة: 2025'), findsOneWidget);
  });

  testWidgets('ExecutiveScreen Month dropdown displays Arabic month names',
      (WidgetTester tester) async {
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
    final monthDropdown =
        find.byKey(const ValueKey('executive_month_dropdown'));
    expect(monthDropdown, findsOneWidget);
    await tester.tap(monthDropdown);
    await tester.pumpAndSettle();

    // Arabic month names in the menu (no English / mixed parentheticals)
    expect(find.text('يناير'), findsOneWidget);
    expect(find.text('فبراير'), findsOneWidget);
    expect(find.text('مارس'), findsOneWidget);
    expect(find.text('أبريل'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(MenuItemButton),
            matching: find.textContaining('January')),
        findsNothing);
    expect(
        find.descendant(
            of: find.byType(MenuItemButton),
            matching: find.textContaining('(')),
        findsNothing);

    // Select February and verify the trigger updates to 'الشهر: فبراير'
    await tester.tap(find.text('فبراير'));
    await tester.pumpAndSettle();
    expect(find.text('الشهر: فبراير'), findsOneWidget);
  });

  testWidgets(
      'UploadPortalScreen file picker parses real CSV bytes and excludes anomalous rows from valid count',
      (WidgetTester tester) async {
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
      name: 'Fathalla_Daily_Sales.csv',
      bytes: WebFileHelper.sampleCarrefourCsvBytes(),
    );

    // Select target retail chain first (chains are now per-company; Adeco's list
    // no longer includes Carrefour, so target Fathalla).
    await tester
        .tap(find.byKey(const ValueKey('ingestion_retail_chain_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(m3MenuEntry('فتح الله').last);
    await tester.pumpAndSettle();

    // Tap device file picker button (has 3 valid rows + 1 short barcode = 4 total)
    await tester.ensureVisible(find.text('اختيار ملف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اختيار ملف'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text(
          'تم الاستخراج بقواعد القراءة المحددة (بدون ذكاء اصطناعي) • بانتظار المراجعة والاعتماد'),
      findsOneWidget,
    );
    expect(find.text('اعتماد البيانات'), findsOneWidget);
    expect(find.text('4 صف'), findsOneWidget);
    expect(find.text('3 صف'), findsOneWidget);
    expect(find.text('1 ملاحظة'), findsOneWidget);
  });

  testWidgets(
      'SellOutExplorerScreen renders date range chip and exports real CSV & HTML',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ExcelExportService.resetLastDownloaded();

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    expect(
        find.byKey(const ValueKey('sellout_date_range_chip')), findsOneWidget);
    expect(find.text('الفترة'), findsOneWidget);

    // Trigger Excel export (the toolbar sits below the fold after the redesign).
    await tester.ensureVisible(find.text('تصدير').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تصدير').first);
    await tester.pumpAndSettle();

    expect(ExcelExportService.lastDownloadedFilename, endsWith('.csv'));
    expect(ExcelExportService.lastDownloadedContent, startsWith('\uFEFF'));
    expect(ExcelExportService.lastDownloadedMimeType,
        equals('text/csv;charset=utf-8'));

    // Trigger PDF/HTML export
    await tester.ensureVisible(find.byKey(const ValueKey('export_pdf_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export_pdf_button')));
    await tester.pumpAndSettle();

    expect(ExcelExportService.lastDownloadedFilename, endsWith('.html'));
    expect(
        ExcelExportService.lastDownloadedContent, contains('<!DOCTYPE html>'));
    expect(ExcelExportService.lastDownloadedMimeType,
        equals('text/html;charset=utf-8'));

    // Open Date Range Picker via chip, apply it, and then clear it
    await tester.tap(find.byKey(const ValueKey('sellout_date_range_chip')));
    await tester.pumpAndSettle();
    if (find.text('تطبيق').evaluate().isNotEmpty) {
      await tester.tap(find.text('تطبيق'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining(' – '), findsWidgets);

    // Clear the active date range via the close icon
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('الفترة'), findsOneWidget);
  });

  testWidgets(
      'UploadPortalScreen device file picker button uses WebFileHelper and deduplicates repeated CSV rows',
      (WidgetTester tester) async {
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

    // Select target retail chain first (chains are now per-company; Adeco's list
    // no longer includes Carrefour, so target Fathalla).
    await tester
        .tap(find.byKey(const ValueKey('ingestion_retail_chain_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(m3MenuEntry('فتح الله').last);
    await tester.pumpAndSettle();

    // The VM stub picker no longer fabricates a sample file, so provide the
    // sample CSV explicitly (3 valid rows + 1 short-barcode anomaly).
    WebFileHelper.nextMockPickedFile = PickedFileData(
      name: 'Fathalla_Daily_Sales.csv',
      bytes: WebFileHelper.sampleCarrefourCsvBytes(),
    );
    // Tap 'اختيار ملف'
    await tester.ensureVisible(find.text('اختيار ملف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اختيار ملف'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text(
          'تم الاستخراج بقواعد القراءة المحددة (بدون ذكاء اصطناعي) • بانتظار المراجعة والاعتماد'),
      findsOneWidget,
    );
    expect(find.text('اعتماد البيانات'), findsOneWidget);
    expect(find.text('4 صف'), findsOneWidget);
    expect(find.text('3 صف'), findsOneWidget);
    expect(find.text('1 ملاحظة'), findsOneWidget);

    // Commit staged data
    final commitBtn = find.descendant(
      of: find.byKey(const ValueKey('commit_action_toolbar')),
      matching: find.text('اعتماد البيانات'),
    );
    await tester.ensureVisible(commitBtn);
    await tester.tap(commitBtn);
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الحفظ والاعتماد'), findsOneWidget);
    await tester.tap(find.text('تأكيد الحفظ والاعتماد'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
        find.text(
            'تم حفظ واعتماد البيانات نهائياً في النظام (Committed to BigQuery)'),
        findsOneWidget);

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

  testWidgets(
      'ExecutiveScreen handles narrow mobile viewport (< 360px) and Month switching without overflow or stale overwrites',
      (WidgetTester tester) async {
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

    // Ensure Month dropdown is visible on narrow < 360px viewport and opens cleanly with Arabic months
    final monthDropdown =
        find.byKey(const ValueKey('executive_month_dropdown'));
    expect(monthDropdown, findsOneWidget);
    await tester.ensureVisible(monthDropdown);
    await tester.tap(monthDropdown);
    await tester.pumpAndSettle();

    expect(find.text('يناير'), findsOneWidget);
    expect(find.text('ديسمبر'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(MenuItemButton),
            matching: find.textContaining('January')),
        findsNothing);

    await tester.tap(find.text('مارس'));
    await tester.pumpAndSettle();
    expect(find.text('الشهر: مارس'), findsOneWidget);

    // Switch Month to All Months
    await tester.ensureVisible(monthDropdown);
    await tester.tap(monthDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل الشهور'));
    await tester.pumpAndSettle();
    expect(find.text('الشهر: الكل'), findsOneWidget);
  });

  testWidgets(
      'SelloutTrendChart renders multi-chain monthly curves with distinct chain legend pills and supports single-month data',
      (WidgetTester tester) async {
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

    expect(find.text('الاتجاه الشهري (\u2068Sell-Out\u2069)'), findsOneWidget);
    expect(find.text('Monthly Sell-Out Trend'), findsNothing);
    expect(find.text('أسواق فتح الله'), findsOneWidget);
    expect(find.text('Fathalla Market'), findsOneWidget);
    expect(find.text('جملة ماركت'), findsOneWidget);
    expect(find.text('Gomla Market'), findsOneWidget);
    expect(find.text('يناير'), findsOneWidget);
    expect(find.text('Jan'), findsNothing);
    expect(find.text('فبراير'), findsOneWidget);
    expect(find.text('Feb'), findsNothing);
    expect(ChainSharePie.colorForChain('fathalla'),
        isNot(equals(ChainSharePie.colorForChain('gomla'))));

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
    expect(find.text('Jan'), findsNothing);

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

    expect(find.text('بيت الجملة'), findsOneWidget);
    expect(find.text('Beet El Gomla'), findsOneWidget);
    expect(find.text('أسواق فتح الله'), findsNothing);
    expect(find.text('جملة ماركت'), findsNothing);
  });

  testWidgets(
      'ExecutiveScreen Retail Chain filter dropdown filters KPIs and ChainSharePie to selected chain and places SelloutTrendChart at 100% width above ChainSharePie',
      (WidgetTester tester) async {
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

    // Verify SelloutTrendChart spans 100% of the content width and is stacked above ChainSharePie
    final trendRect = tester.getRect(find.byType(SelloutTrendChart));
    final pieRect = tester.getRect(find.byType(ChainSharePie));
    final gridRect = tester.getRect(find.byType(BentoKpiGrid));
    expect(trendRect.width, closeTo(gridRect.width, 1.0));
    expect(pieRect.width, closeTo(gridRect.width, 1.0));
    expect(pieRect.top, greaterThanOrEqualTo(trendRect.bottom));

    final chainDropdown =
        find.byKey(const ValueKey('executive_chain_dropdown'));
    expect(chainDropdown, findsOneWidget);
    expect(find.text('السلسلة: الكل'), findsOneWidget);

    await tester.tap(chainDropdown);
    await tester.pumpAndSettle();

    expect(find.text('فتح الله'), findsWidgets);
    expect(find.text('Fathalla'), findsWidgets);
    expect(find.text('جملة ماركت'), findsWidgets);
    expect(find.text('Gomla'), findsWidgets);

    await tester.tap(find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text('جملة ماركت'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('السلسلة: جملة ماركت'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);

    // ParetoCategorySection cards are Arabic-only (mockup); brand names
    // such as "Fathalla Market" are data and stay as they are.
    expect(find.text('الحصة السوقية مقارنة بالمنافسين'), findsOneWidget);
    expect(find.text('مساهمة الفئات'), findsOneWidget);
    expect(find.text('أصناف المبيعات'), findsOneWidget);
    expect(find.textContaining('80/20'), findsNothing);
    expect(find.textContaining('تحقق 80'), findsNothing);
    expect(
        find.textContaining(RegExp(
            r'Market Share vs|Market leader|Rank #|Category Contribution|Top SKUs')),
        findsNothing);
    // Ranks are bare numbers in Arabic ("المركز 1", chip "1", "+9"): no '#'.
    final pareto = find.byType(ParetoCategorySection);
    expect(pareto, findsOneWidget);
    expect(find.descendant(of: pareto, matching: find.textContaining('#')),
        findsNothing);
    // Short chip + description: rank sits in the description under the chip.
    expect(
        find.descendant(
            of: pareto,
            matching: find.textContaining(RegExp(r'المركز \d+'))),
        findsWidgets);
    expect(
        find.descendant(
            of: pareto,
            matching: find.textContaining(RegExp(r'\(المركز \d+\)'))),
        findsNothing);
  });

  testWidgets(
      'ChainSharePie.splitBilingualLabel handles edge cases and SelloutTrendChart renders all 12 months at full width',
      (WidgetTester tester) async {
    expect(ChainSharePie.splitBilingualLabel(''), equals((ar: '', en: null)));
    expect(
      ChainSharePie.splitBilingualLabel('أسواق فتح الله (Fathalla Market)'),
      equals((ar: 'أسواق فتح الله', en: 'Fathalla Market')),
    );
    expect(
      ChainSharePie.splitBilingualLabel('All Chains (كل السلاسل)'),
      equals((ar: 'كل السلاسل', en: 'All Chains')),
    );
    expect(
      ChainSharePie.splitBilingualLabel('شركة أديكو'),
      equals((ar: 'شركة أديكو', en: null)),
    );
    expect(
      ChainSharePie.splitBilingualLabel('بروكتر آند جامبل (حساب 2) (P&G)'),
      equals((ar: 'بروكتر آند جامبل (حساب 2)', en: 'P&G')),
    );

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fullYearTrends = List.generate(12, (i) {
      final m = (i + 1).toString().padLeft(2, '0');
      return DailyTrendItem(
        date: '2025-$m-28',
        monthKey: '2025-$m',
        revenue: 500000.0 + (i * 25000.0),
        units: 6000 + (i * 300),
        storeCount: 34,
        chainRevenues: {'fathalla': 500000.0 + (i * 25000.0)},
        chainUnits: {'fathalla': 6000 + (i * 300)},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelloutTrendChart(trends: fullYearTrends),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // All 12 months should have both Arabic (Line 1) and English (Line 2) labels rendered
    expect(find.text('يناير'), findsOneWidget);
    expect(find.text('Jan'), findsNothing);
    expect(find.text('يونيو'), findsOneWidget);
    expect(find.text('Jun'), findsNothing);
    expect(find.text('ديسمبر'), findsOneWidget);
    expect(find.text('Dec'), findsNothing);
  });
}

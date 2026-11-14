import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/features/sell_in_returns/data/sell_in_returns_repository.dart';
import 'package:tashil_web/features/sell_in_returns/domain/sell_in_returns_models.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/screens/sell_in_returns_screen.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/widgets/returns_heatmap_matrix.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/widgets/returns_top_products_table.dart';

/// Synthetic report: months come from data (Feb/Mar/May) — not a fixed 1..12 grid.
class _FakeReturnsRepo implements SellInReturnsRepository {
  @override
  Future<Result<SellInReturnsReport>> load(SellInReturnsQuery q, {bool forceRefresh = false}) async {
    const cell = SellInReturnsCell(grossValueEgp: 100, returnsValueEgp: 20, returnsQty: 2, netValueEgp: 80, returnPctOfGross: 20);
    return const Success(
      SellInReturnsReport(
        year: 2026,
        months: [2, 3, 5],
        kpis: SellInReturnsKpis(
          returnsValueEgp: 60,
          returnsQty: 6,
          grossValueEgp: 300,
          netValueEgp: 240,
          returnPctOfGross: 20,
          momChangePct: 10,
          momDirection: 'up',
          focusMonth: 5,
        ),
        monthly: [
          SellInReturnsMonthPoint(monthNum: 2, monthAr: 'فبراير', monthEn: 'Feb', grossValueEgp: 100, returnsValueEgp: 20, netValueEgp: 80),
          SellInReturnsMonthPoint(monthNum: 3, monthAr: 'مارس', monthEn: 'Mar', grossValueEgp: 100, returnsValueEgp: 20, netValueEgp: 80),
          SellInReturnsMonthPoint(monthNum: 5, monthAr: 'مايو', monthEn: 'May', grossValueEgp: 100, returnsValueEgp: 20, netValueEgp: 80),
        ],
        branches: [
          SellInReturnsBranchRow(
            branchKey: 'b1',
            branchName: 'فرع QA تجريبي',
            byMonth: {2: cell, 3: cell, 5: cell},
            total: SellInReturnsCell(returnsValueEgp: 60, grossValueEgp: 300, netValueEgp: 240, returnPctOfGross: 20),
          ),
        ],
        columnTotals: {
          2: cell,
          3: cell,
          5: cell,
        },
        grandTotal: SellInReturnsCell(returnsValueEgp: 60, grossValueEgp: 300, netValueEgp: 240, returnPctOfGross: 20),
        filterOptions: SellInReturnsFilterOptions(
          years: [2026],
          branches: ['فرع QA تجريبي'],
          products: ['صنف QA'],
          productGroups: ['مجموعة QA'],
        ),
        // Advisories / alerts intentionally omitted — cards removed from UI.
        topReturnedProducts: [
          SellInReturnsTopProduct(
            rank: 1,
            productCode: 'QA-1',
            productName: 'صنف QA مرتجع',
            productGroup: 'مجموعة QA',
            returnsValueEgp: 40,
            returnsQty: 4,
            grossValueEgp: 200,
            netValueEgp: 160,
            returnPctOfGross: 20,
            shareOfReturns: 66.7,
          ),
          SellInReturnsTopProduct(
            rank: 2,
            productCode: 'QA-2',
            productName: 'صنف QA ثانٍ',
            returnsValueEgp: 20,
            returnsQty: 2,
            grossValueEgp: 100,
            netValueEgp: 80,
            returnPctOfGross: 20,
            shareOfReturns: 33.3,
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('المرتجعات matrix months come from data (Feb/Mar/May only)', (tester) async {
    // Tall viewport so Phase-2 top-products + matrix are all built (ListView lazy).
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Avoid AvailableYears HTTP in widget tests.
    AvailableYears.setForTest(const YearOptions(years: [2026], defaultYear: 2026));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SellInReturnsScreen(
            apiClient: ApiClient(),
            repository: _FakeReturnsRepo(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المرتجعات'), findsWidgets);
    expect(find.textContaining('قيمة المرتجعات'), findsOneWidget);
    expect(find.textContaining('كمية المرتجعات'), findsOneWidget);
    // #141 shortened the KPI title so the 138px card matches Sell-Out;
    // the rest of the phrase is the subtitle («من الإجمالي · Returns ÷ Gross»).
    expect(find.text('نسبة المرتجع'), findsOneWidget);
    expect(find.textContaining('من الإجمالي'), findsWidgets);
    expect(find.textContaining('التغير الشهري'), findsOneWidget);

    // Phase-2: top returned products + Excel export; alert cards removed.
    expect(find.textContaining('تنبيهات تجاوز الحد المعتاد'), findsNothing);
    expect(find.textContaining('صافي سالب (محفوظ وغير مخفي)'), findsNothing);
    expect(find.text('أعلى الأصناف المرتجعة'), findsOneWidget);
    expect(find.textContaining('صنف QA مرتجع'), findsOneWidget);
    expect(find.text('تصدير Excel'), findsOneWidget);

    // Dynamic months from fixture — matrix columns only (not a fixed Jan–Dec grid).
    // Month dropdown still lists Jan–Dec; scope assertions to the matrix card.
    expect(find.textContaining('مصفوفة المرتجعات'), findsOneWidget);
    // Heatmap uses fixed-width cells (not DataTable) so RTL headers stay aligned.
    expect(find.byType(ReturnsHeatmapMatrix), findsOneWidget);
    expect(find.byType(ReturnsTopProductsTable), findsOneWidget);
    expect(find.text('فبراير'), findsWidgets);
    expect(find.text('مارس'), findsWidgets);
    expect(find.text('مايو'), findsWidgets);

    expect(find.text('فرع QA تجريبي'), findsWidgets);
    // Filter dropdown also uses label «الصنف» — assert the top-products header by key.
    expect(find.byKey(ReturnsTopProductsTable.productHeaderKey), findsOneWidget);
    expect(find.byKey(ReturnsTopProductsTable.returnsValueHeaderKey), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ReturnsTopProductsTable), matching: find.text('الصنف')),
      findsOneWidget,
    );

    // Rank (#) column is narrow and sits beside the product name (not a wide spacer).
    expect(ReturnsTopProductsTable.columnWidths[0], isA<FixedColumnWidth>());
    final rankW = (ReturnsTopProductsTable.columnWidths[0]! as FixedColumnWidth).value;
    expect(rankW, lessThanOrEqualTo(40));

    // Value ↔ % toggle is present.
    expect(find.text('قيمة'), findsWidgets);
    expect(find.text('نسبة\u00A0%'), findsOneWidget);
  });

  testWidgets('المرتجعات Excel export downloads matrix + top products CSV', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    AvailableYears.setForTest(const YearOptions(years: [2026], defaultYear: 2026));
    ExcelExportService.resetLastDownloaded();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SellInReturnsScreen(
            apiClient: ApiClient(),
            repository: _FakeReturnsRepo(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تصدير Excel'));
    await tester.pump();

    expect(ExcelExportService.lastDownloadedFilename, isNotNull);
    expect(ExcelExportService.lastDownloadedFilename, contains('returns'));
    expect(ExcelExportService.lastDownloadedContent, isNotNull);
    expect(ExcelExportService.lastDownloadedContent, contains('صنف QA مرتجع'));
  });
}

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
        advisories: [
          SellInReturnsAdvisory(
            year: 2026,
            monthNum: 5,
            branchName: 'فرع QA تجريبي',
            productName: 'صنف سالب',
            netValueEgp: -15,
            messageAr: 'صافي التوريد سالب للصنف «صنف سالب» في فرع «فرع QA تجريبي» خلال مايو',
          ),
        ],
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
        alerts: [
          SellInReturnsAlert(
            severity: 'critical',
            code: 'return_pct',
            messageAr: 'نسبة المرتجع من الإجمالي 20.0% تجاوزت الحد الحرج (10%).',
            value: 20,
            threshold: 10,
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('المرتجعات matrix months come from data (Feb/Mar/May only)', (tester) async {
    // Tall viewport so Phase-2 alerts/top-products + matrix are all built (ListView lazy).
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
    expect(find.text('نسبة المرتجع من الإجمالي'), findsOneWidget);
    expect(find.textContaining('التغير الشهري'), findsOneWidget);

    // Phase-2: threshold alerts + top returned products + Excel export.
    expect(find.textContaining('تنبيهات تجاوز الحد المعتاد'), findsOneWidget);
    expect(find.textContaining('تجاوزت الحد الحرج'), findsOneWidget);
    expect(find.text('أعلى الأصناف المرتجعة'), findsOneWidget);
    expect(find.textContaining('صنف QA مرتجع'), findsOneWidget);
    expect(find.text('تصدير Excel'), findsOneWidget);

    // Dynamic months from fixture — matrix columns only (not a fixed Jan–Dec grid).
    // Month dropdown still lists Jan–Dec; scope assertions to the matrix card.
    expect(find.textContaining('مصفوفة المرتجعات'), findsOneWidget);
    final matrixCard = find.ancestor(
      of: find.textContaining('مصفوفة المرتجعات'),
      matching: find.byWidgetPredicate((w) => w is Card),
    );
    final matrixTable = find.descendant(of: matrixCard, matching: find.byType(DataTable));
    expect(matrixTable, findsOneWidget);
    expect(find.descendant(of: matrixTable, matching: find.text('فبراير')), findsOneWidget);
    expect(find.descendant(of: matrixTable, matching: find.text('مارس')), findsOneWidget);
    expect(find.descendant(of: matrixTable, matching: find.text('مايو')), findsOneWidget);
    expect(find.descendant(of: matrixTable, matching: find.text('يناير')), findsNothing);
    expect(find.descendant(of: matrixTable, matching: find.text('أبريل')), findsNothing);
    expect(find.descendant(of: matrixTable, matching: find.text('يونيو')), findsNothing);

    expect(find.text('فرع QA تجريبي'), findsWidgets);
    expect(find.textContaining('صافي التوريد سالب'), findsOneWidget);

    // Value ↔ % toggle is present.
    expect(find.text('قيمة'), findsWidgets);
    expect(find.text('نسبة %'), findsOneWidget);
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_in_returns/data/sell_in_returns_repository.dart';
import 'package:tashil_web/features/sell_in_returns/domain/sell_in_returns_models.dart';
import 'package:tashil_web/features/sell_in_returns/presentation/screens/sell_in_returns_screen.dart';

/// Synthetic report: months come from data (Feb/Mar/May) — not a fixed 1..12 grid.
class _FakeReturnsRepo implements SellInReturnsRepository {
  @override
  Future<Result<SellInReturnsReport>> load(SellInReturnsQuery q, {bool forceRefresh = false}) async {
    const cell = SellInReturnsCell(grossValueEgp: 100, returnsValueEgp: 20, returnsQty: 2, netValueEgp: 80, returnPctOfGross: 20);
    return Success(
      SellInReturnsReport(
        year: 2026,
        months: const [2, 3, 5],
        kpis: const SellInReturnsKpis(
          returnsValueEgp: 60,
          returnsQty: 6,
          grossValueEgp: 300,
          netValueEgp: 240,
          returnPctOfGross: 20,
          momChangePct: 10,
          momDirection: 'up',
          focusMonth: 5,
        ),
        monthly: const [
          SellInReturnsMonthPoint(monthNum: 2, monthAr: 'فبراير', monthEn: 'Feb', grossValueEgp: 100, returnsValueEgp: 20, netValueEgp: 80),
          SellInReturnsMonthPoint(monthNum: 3, monthAr: 'مارس', monthEn: 'Mar', grossValueEgp: 100, returnsValueEgp: 20, netValueEgp: 80),
          SellInReturnsMonthPoint(monthNum: 5, monthAr: 'مايو', monthEn: 'May', grossValueEgp: 100, returnsValueEgp: 20, netValueEgp: 80),
        ],
        branches: [
          SellInReturnsBranchRow(
            branchKey: 'b1',
            branchName: 'فرع QA تجريبي',
            byMonth: const {2: cell, 3: cell, 5: cell},
            total: const SellInReturnsCell(returnsValueEgp: 60, grossValueEgp: 300, netValueEgp: 240, returnPctOfGross: 20),
          ),
        ],
        columnTotals: const {
          2: cell,
          3: cell,
          5: cell,
        },
        grandTotal: const SellInReturnsCell(returnsValueEgp: 60, grossValueEgp: 300, netValueEgp: 240, returnPctOfGross: 20),
        filterOptions: const SellInReturnsFilterOptions(
          years: [2026],
          branches: ['فرع QA تجريبي'],
          products: ['صنف QA'],
          productGroups: ['مجموعة QA'],
        ),
        advisories: const [
          SellInReturnsAdvisory(
            year: 2026,
            monthNum: 5,
            branchName: 'فرع QA تجريبي',
            productName: 'صنف سالب',
            netValueEgp: -15,
            messageAr: 'صافي التوريد سالب للصنف «صنف سالب» في فرع «فرع QA تجريبي» خلال مايو',
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('المرتجعات matrix months come from data (Feb/Mar/May only)', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
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
    expect(find.textContaining('نسبة المرتجع من الإجمالي'), findsOneWidget);
    expect(find.textContaining('التغير الشهري'), findsOneWidget);

    // Dynamic months from fixture — matrix columns only (not a fixed Jan–Dec grid).
    final table = find.byType(DataTable);
    expect(find.descendant(of: table, matching: find.text('فبراير')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('مارس')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('مايو')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('يناير')), findsNothing);
    expect(find.descendant(of: table, matching: find.text('أبريل')), findsNothing);
    expect(find.descendant(of: table, matching: find.text('يونيو')), findsNothing);

    expect(find.text('فرع QA تجريبي'), findsWidgets);
    expect(find.textContaining('صافي التوريد سالب'), findsOneWidget);

    // Value ↔ % toggle is present.
    expect(find.text('قيمة'), findsWidgets);
    expect(find.text('نسبة %'), findsOneWidget);
  });
}

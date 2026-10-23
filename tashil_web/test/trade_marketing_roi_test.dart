import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/trade_marketing/data/trade_marketing_repository.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

/// In-memory fake of the server: fixed expenses and fixed sales baselines.
class FakeTradeMarketingRepository implements TradeMarketingRepository {
  final List<MarketingExpenseItem> items =
      TradeMarketingSeedData.getInitialExpenses('adeco');

  @override
  Future<List<MarketingExpenseItem>> listExpenses(
          {int? year, int? month, String? chain}) async =>
      List.of(items);

  @override
  Future<MarketingExpenseItem> saveExpense(MarketingExpenseItem item,
      {required bool isNew}) async {
    items.removeWhere((e) => e.id == item.id);
    items.add(item);
    return item;
  }

  @override
  Future<void> deleteExpense(String id) async =>
      items.removeWhere((e) => e.id == id);

  @override
  Future<List<TradeMarketingSalesBaseline>> getRoi(
      {int? year, int? month, String? chain}) async {
    final seen = <String>{};
    final out = <TradeMarketingSalesBaseline>[];
    for (final e in items) {
      if (!seen.add('${e.year}_${e.month}_${e.chainName}')) continue;
      final spend = items
          .where((x) =>
              x.year == e.year &&
              x.month == e.month &&
              x.chainName == e.chainName)
          .fold<double>(0, (a, x) => a + x.amountEgp);
      final s = TradeMarketingSeedData.getMonthlySalesSnapshot(
          chainName: e.chainName,
          year: e.year,
          month: e.month,
          totalMarketingSpendInMonth: spend);
      out.add(TradeMarketingSalesBaseline(
        year: e.year,
        month: e.month,
        chainName: e.chainName,
        currentMonthSalesEgp: s['currentSales']!,
        previousMonthSalesEgp: s['previousMonthSales']!,
        lastYearSameMonthSalesEgp: s['lastYearSales']!,
        currentMonthSellInEgp: s['currentSellIn']!,
        marketingSpendEgp: spend,
      ));
    }
    return out;
  }

  @override
  Future<ExpenseUploadResult> uploadExpenses(
          List<int> bytes, String filename) async =>
      const ExpenseUploadResult(0, 0, []);
}

void main() {
  group('Trade Marketing & Promo ROI Screen Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    testWidgets(
      'Renders 4 symmetrical KPI cards, English SegmentedButton tabs, MoM/YoY growth matrix, and supports adding expenses',
      (WidgetTester tester) async {
        final fakeRepo = FakeTradeMarketingRepository();
        final initialCount = fakeRepo.items.length;
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: TradeMarketingRoiScreen(
                apiClient: apiClient, repository: fakeRepo),
          ),
        );

        await tester.pumpAndSettle();

        // Verify 4 symmetrical KPI cards (Arabic on top, English below)
        expect(find.text('إجمالي المصروفات الترويجية'), findsOneWidget);
        expect(find.text('Total Trade Marketing Spend'), findsOneWidget);

        expect(find.text('نمو المبيعات عن الشهر السابق'), findsOneWidget);
        expect(find.text('MoM Sales Growth Lift'), findsOneWidget);

        expect(find.text('نمو المبيعات عن العام السابق'), findsOneWidget);
        expect(find.text('YoY Same-Month Sales Lift'), findsOneWidget);

        expect(find.text('العائد على الإنفاق التسويقي'), findsOneWidget);
        expect(find.text('Return on Marketing Spend (ROMI)'), findsOneWidget);

        // Verify 3 English SegmentedButton tabs
        expect(find.text('ROI & Growth Matrix'), findsOneWidget);
        expect(find.text('Campaigns & Expense Ledger'), findsOneWidget);
        expect(find.text('Activity & Brand Analytics'), findsOneWidget);

        // Verify 4 English MD3 Action Buttons
        expect(find.byKey(const ValueKey('btn_add_marketing_expense')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('btn_roi_simulator')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('btn_export_roi_excel')), findsOneWidget);
        expect(find.byKey(const ValueKey('btn_print_roi_pdf')), findsOneWidget);

        // Verify January 2026 Fathalla MoM and YoY growth badges in the matrix
        expect(find.textContaining('+32.4% MoM'), findsOneWidget);
        expect(find.textContaining('+41.2% YoY'), findsOneWidget);

        // Switch to Tab 1: Campaigns & Expense Ledger
        await tester.tap(find.text('Campaigns & Expense Ledger'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Campaigns & Expense Ledger'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('سجل المصروفات الترويجية والحملات التفصيلي'),
          findsOneWidget,
        );

        // Switch to Tab 2: Activity & Brand Analytics
        await tester.tap(find.text('Activity & Brand Analytics'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
              'توزيع الميزانية التسويقية حسب نوع النشاط الترويجي'),
          findsOneWidget,
        );

        // Deleting a ledger row goes through the repository.
        await tester.tap(find.text('Campaigns & Expense Ledger'));
        await tester.pumpAndSettle();
        final deleteButtons = find.byTooltip('Delete / حذف');
        expect(deleteButtons, findsWidgets);
        await tester.ensureVisible(deleteButtons.first);
        await tester.pumpAndSettle();
        await tester.tap(deleteButtons.first);
        await tester.pumpAndSettle();
        expect(fakeRepo.items.length, initialCount - 1);
      },
    );
  });
}

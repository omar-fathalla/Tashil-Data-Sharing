import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/web_file_helper.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:tashil_web/features/trade_marketing/domain/roi_lift.dart';
import 'package:tashil_web/features/trade_marketing/data/trade_marketing_repository.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';
import 'package:tashil_web/features/trade_marketing/presentation/screens/trade_marketing_roi_screen.dart';

/// In-memory fake of the server: fixed expenses and fixed sales baselines.
class FakeTradeMarketingRepository implements TradeMarketingRepository {
  final List<MarketingExpenseItem> items =
      TradeMarketingSeedData.getInitialExpenses('adeco');

  @override
  Future<List<MarketingExpenseItem>> listExpenses(
      {int? year, int? month, String? chain}) async {
    listCalls++;
    return List.of(items);
  }

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
    roiCalls++;
    final seen = <String>{};
    final keys = <({int year, int month, String chain})>[];
    final spendBy = <String, double>{};
    for (final e in items) {
      final k = '${e.year}_${e.month}_${e.chainName}';
      spendBy[k] = (spendBy[k] ?? 0) + e.amountEgp;
      if (seen.add(k)) {
        keys.add((year: e.year, month: e.month, chain: e.chainName));
      }
    }
    final salesByChain = <String, Map<RoiMonthKey, double>>{};
    final campaignsByChain = <String, Set<RoiMonthKey>>{};
    final snapshots = <String, Map<String, double>>{};
    for (final k in keys) {
      final spend = spendBy['${k.year}_${k.month}_${k.chain}'] ?? 0;
      final s = TradeMarketingSeedData.getMonthlySalesSnapshot(
          chainName: k.chain,
          year: k.year,
          month: k.month,
          totalMarketingSpendInMonth: spend);
      snapshots['${k.year}_${k.month}_${k.chain}'] = s;
      final chainSales =
          salesByChain.putIfAbsent(k.chain, () => <RoiMonthKey, double>{});
      final target = RoiMonthKey(k.year, k.month);
      chainSales[target] = s['currentSales']!;
      chainSales[target.previous] = s['previousMonthSales']!;
      chainSales[target.lastYear] = s['lastYearSales']!;
      if (spend > 0) {
        campaignsByChain
            .putIfAbsent(k.chain, () => <RoiMonthKey>{})
            .add(target);
      }
    }
    final out = <TradeMarketingSalesBaseline>[];
    for (final k in keys) {
      final spend = spendBy['${k.year}_${k.month}_${k.chain}'] ?? 0;
      final s = snapshots['${k.year}_${k.month}_${k.chain}']!;
      final target = RoiMonthKey(k.year, k.month);
      final lift = computeRoiLift(
        currentSalesEgp: s['currentSales']!,
        lastYearSameMonthSalesEgp: s['lastYearSales']!,
        marketingSpendEgp: spend,
        target: target,
        salesByMonth: salesByChain[k.chain] ?? const {},
        campaignMonths: campaignsByChain[k.chain] ?? const {},
      );
      out.add(TradeMarketingSalesBaseline(
        year: k.year,
        month: k.month,
        chainName: k.chain,
        currentMonthSalesEgp: s['currentSales']!,
        previousMonthSalesEgp: s['previousMonthSales']!,
        lastYearSameMonthSalesEgp: s['lastYearSales']!,
        currentMonthSellInEgp: s['currentSellIn']!,
        marketingSpendEgp: spend,
        lift: lift,
      ));
    }
    return out;
  }

  ExpenseUploadResult nextUploadResult = const ExpenseUploadResult(0, 0, []);
  String? lastUploadedFilename;
  int listCalls = 0;
  int roiCalls = 0;

  @override
  Future<ExpenseUploadResult> uploadExpenses(
      List<int> bytes, String filename) async {
    lastUploadedFilename = filename;
    return nextUploadResult;
  }
}

void main() {
  setUp(AppCache.clear);

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

        // 4 shared Sell-Out KPI cards (Arabic titles; detail on the detail line)
        expect(find.text('المصروفات الترويجية'), findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('tm_kpi_mom')),
                matching: find.text('النمو عن الشهر السابق')),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('tm_kpi_yoy')),
                matching: find.text('النمو عن العام السابق')),
            findsOneWidget);
        expect(find.text('العائد على الإنفاق'), findsOneWidget);

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
        expect(
            find.textContaining(CurrencyFormatter.formatSignedPct(32.4)),
            findsWidgets);
        expect(
            find.textContaining(CurrencyFormatter.formatSignedPct(41.2)),
            findsWidgets);

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

    Future<void> pumpScreen(
        WidgetTester tester, FakeTradeMarketingRepository repo) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: TradeMarketingRoiScreen(apiClient: apiClient, repository: repo),
      ));
      await tester.pumpAndSettle();
    }

    tearDown(WebFileHelper.resetTestOverrides);

    testWidgets(
        'Upload Excel/CSV: success shows saved count and refreshes data',
        (tester) async {
      final repo = FakeTradeMarketingRepository()
        ..nextUploadResult = const ExpenseUploadResult(5, 0, []);
      await pumpScreen(tester, repo);
      final listBefore = repo.listCalls, roiBefore = repo.roiCalls;
      WebFileHelper.nextMockPickedFile = PickedFileData(
          name: 'expenses.csv',
          bytes: Uint8List.fromList(utf8.encode('year\n')));
      await tester
          .tap(find.byKey(const ValueKey('btn_upload_marketing_expenses')));
      await tester.pumpAndSettle();
      expect(repo.lastUploadedFilename, 'expenses.csv');
      expect(find.byKey(const ValueKey('dlg_expense_upload_result')),
          findsOneWidget);
      expect(find.text('تم الحفظ: 5'), findsOneWidget);
      expect(find.text('مرفوض: 0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('btn_close_upload_result')));
      await tester.pumpAndSettle();
      expect(repo.listCalls, greaterThan(listBefore));
      expect(repo.roiCalls, greaterThan(roiBefore));
    });

    testWidgets('Upload Excel/CSV: rejected rows are listed with reasons',
        (tester) async {
      final repo = FakeTradeMarketingRepository()
        ..nextUploadResult = const ExpenseUploadResult(
            2, 2, ['Row 3: invalid month', 'Row 7: unknown category']);
      await pumpScreen(tester, repo);
      WebFileHelper.nextMockPickedFile = PickedFileData(
          name: 'expenses.xlsx', bytes: Uint8List.fromList([1, 2, 3]));
      await tester
          .tap(find.byKey(const ValueKey('btn_upload_marketing_expenses')));
      await tester.pumpAndSettle();
      expect(find.text('تم الحفظ: 2'), findsOneWidget);
      expect(find.text('مرفوض: 2'), findsOneWidget);
      expect(find.text('Row 3: invalid month'), findsOneWidget);
      expect(find.text('Row 7: unknown category'), findsOneWidget);
    });

    testWidgets('Upload Excel/CSV: unsupported file type is not uploaded',
        (tester) async {
      final repo = FakeTradeMarketingRepository();
      await pumpScreen(tester, repo);
      WebFileHelper.nextMockPickedFile =
          PickedFileData(name: 'old.xls', bytes: Uint8List.fromList([1]));
      await tester
          .tap(find.byKey(const ValueKey('btn_upload_marketing_expenses')));
      await tester.pumpAndSettle();
      expect(repo.lastUploadedFilename, isNull);
      expect(find.byKey(const ValueKey('dlg_expense_upload_result')),
          findsNothing);
    });
  });
}

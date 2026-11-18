import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

class _BrandAwareRepo extends SellOutExplorerRepository {
  _BrandAwareRepo({this.gate})
      : super(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));

  /// When non-null, brand-scoped matrix loads wait on this completer so the
  /// loading skeletons are observable (SKU KPIs still update immediately).
  Completer<void>? gate;
  final List<String?> brandLoads = [];

  static final _records = [
    SellOutRecordModel(
      recordId: 'd1',
      retailerChain: 'fathalla',
      storeId: 's1',
      storeName: 'فرع أ',
      barcode: '1',
      skuName: 'شامبو ديفا 400 مل',
      category: 'عناية',
      quantitySold: 10,
      netRevenue: 1000,
      unitPrice: 100,
      transactionDate: '2026-03-15',
    ),
    SellOutRecordModel(
      recordId: 'v1',
      retailerChain: 'fathalla',
      storeId: 's1',
      storeName: 'فرع أ',
      barcode: '2',
      skuName: 'فلفيتا جيل 750 مل',
      category: 'مساحيق',
      quantitySold: 8,
      netRevenue: 800,
      unitPrice: 100,
      transactionDate: '2026-03-15',
    ),
    SellOutRecordModel(
      recordId: 'c1',
      retailerChain: 'fathalla',
      storeId: 's2',
      storeName: 'فرع ب',
      barcode: '3',
      skuName: 'كلوريل أبيض 1050 جم',
      category: 'مطهرات',
      quantitySold: 20,
      netRevenue: 2000,
      unitPrice: 100,
      transactionDate: '2026-03-15',
    ),
  ];

  List<StoreBenchmarkItem> _matrixFor(String? brand) {
    StoreBenchmarkItem row({
      required String id,
      required String name,
      required double rev,
      required int units,
      required int rank,
    }) =>
        StoreBenchmarkItem(
          storeId: id,
          storeName: name,
          retailerChain: 'fathalla',
          region: 'إسكندرية',
          tier: 'Tier A',
          totalRevenue: rev,
          totalUnits: units,
          velocityUnitsPerDay: units / 30.0,
          rank: rank,
        );
    final b = (brand ?? '').trim();
    if (b.isEmpty || b == 'all') {
      return [
        row(id: 's1', name: 'فرع أ', rev: 1800, units: 18, rank: 1),
        row(id: 's2', name: 'فرع ب', rev: 2000, units: 20, rank: 2),
      ];
    }
    if (b.contains('Diva') || b.contains('ديفا')) {
      return [row(id: 's1', name: 'فرع أ', rev: 1000, units: 10, rank: 1)];
    }
    if (b.contains('Velveta') || b.contains('فل')) {
      return [row(id: 's1', name: 'فرع أ', rev: 800, units: 8, rank: 1)];
    }
    return const [];
  }

  @override
  Future<Result<SellOutExplorerData>> load(SellOutExplorerQuery q, {bool forceRefresh = false}) async {
    brandLoads.add(q.matrixBrand);
    final matrix = _matrixFor(q.matrixBrand);
    // Only gate brand-scoped refetches — initial all-brand load settles normally.
    if (gate != null && q.matrixBrand != null && q.matrixBrand!.trim().isNotEmpty) {
      await gate!.future;
    }
    return Success(SellOutExplorerData(
      records: _records,
      summary: SellOutRecordsSummaryModel(
        totalCount: _records.length,
        totalNetRevenue: 3800,
        totalUnitsSold: 38,
        activeStoresCount: 2,
        activeSkusCount: 3,
      ),
      stores: const [],
      currentBranchMatrix: matrix,
      prevBranchMatrix: const [],
      yoyCurrentBranchMatrix: matrix,
    ));
  }
}

Future<void> _pumpPerfTab(WidgetTester tester, _BrandAwareRepo repo) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SellOutExplorerScreen(
            apiClient: ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
            repository: repo,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('أداء الفروع').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('أداء الفروع brand filter updates KPIs and branch table', (tester) async {
    final repo = _BrandAwareRepo();
    await _pumpPerfTab(tester, repo);

    expect(find.byKey(const ValueKey('perf_brand_dropdown')), findsOneWidget);
    // Unfiltered: top store is فرع ب (2000).
    expect(find.textContaining('فرع ب'), findsWidgets);
    expect(
      find.textContaining(CurrencyFormatter.formatCompactEGP(2000)),
      findsWidgets,
    );

    // Open brand dropdown and pick Diva.
    await tester.tap(find.byKey(const ValueKey('perf_brand_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ديفا (Diva)').last);
    await tester.pumpAndSettle();

    expect(repo.brandLoads.where((b) => b != null && b.contains('ديفا')).isNotEmpty, isTrue);
    // Top SKU KPI becomes Diva; branch matrix is Diva-only (فرع ب gone from table).
    expect(find.textContaining('شامبو ديفا'), findsWidgets);
    final branchSection = find.byKey(const ValueKey('branch_velocity_section'));
    expect(branchSection, findsOneWidget);
    expect(
      find.descendant(of: branchSection, matching: find.textContaining('فرع ب')),
      findsNothing,
      reason: 'Clorel-only branch must drop out when Diva is selected',
    );
    expect(
      find.descendant(of: branchSection, matching: find.textContaining('فرع أ')),
      findsWidgets,
    );
    expect(
      find.textContaining(CurrencyFormatter.formatCompactEGP(1000)),
      findsWidgets,
    );
  });

  testWidgets('hard refresh: all-brands dropdown stays all, not first catalog brand', (tester) async {
    final repo = _BrandAwareRepo();
    await _pumpPerfTab(tester, repo);

    // Regression: brandLabelMatches(brand, 'all') is true for every brand, so
    // firstWhere used to paint ديفا in the field while KPIs stayed all-brands.
    final dropdown = find.byKey(const ValueKey('perf_brand_dropdown'));
    expect(dropdown, findsOneWidget);
    // Assert the field value (EditableText), not menu entry labels which stay
    // in the tree even when the menu is closed.
    final field = tester.widget<EditableText>(
      find.descendant(of: dropdown, matching: find.byType(EditableText)),
    );
    expect(
      field.controller.text,
      'كل العلامات التجارية',
      reason: 'all filter must not restore ديفا (first sorted brand) after load',
    );
    // All-brand top store remains فرع ب — filter was not silently applied as Diva.
    expect(
      find.textContaining(CurrencyFormatter.formatCompactEGP(2000)),
      findsWidgets,
    );
  });

  testWidgets('brand change shows branch KPI/table loading while SKU KPIs update', (tester) async {
    final gate = Completer<void>();
    final repo = _BrandAwareRepo(gate: gate);
    await _pumpPerfTab(tester, repo);

    await tester.tap(find.byKey(const ValueKey('perf_brand_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ديفا (Diva)').last);
    // Process selection + loading setState without settling (matrix still gated).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // SKU KPIs update immediately via client filter.
    expect(find.textContaining('شامبو ديفا'), findsWidgets);

    // Branch KPIs + table show loading instead of stale all-brand totals.
    expect(find.byKey(const ValueKey('perf_branch_kpi_skeleton_top_store')), findsOneWidget);
    expect(find.byKey(const ValueKey('perf_branch_kpi_skeleton_avg_store')), findsOneWidget);
    expect(find.byKey(const ValueKey('perf_branch_table_loading')), findsOneWidget);
    expect(
      find.textContaining(CurrencyFormatter.formatCompactEGP(2000)),
      findsNothing,
      reason: 'stale all-brand top-store revenue must not linger during refetch',
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('perf_branch_kpi_skeleton_top_store')), findsNothing);
    expect(find.byKey(const ValueKey('perf_branch_table_loading')), findsNothing);
    final branchSection = find.byKey(const ValueKey('branch_velocity_section'));
    expect(
      find.descendant(of: branchSection, matching: find.textContaining('فرع ب')),
      findsNothing,
    );
    expect(
      find.textContaining(CurrencyFormatter.formatCompactEGP(1000)),
      findsWidgets,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

class _BrandAwareRepo extends SellOutExplorerRepository {
  _BrandAwareRepo()
      : super(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));

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

void main() {
  testWidgets('أداء الفروع brand filter updates KPIs and branch table', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repo = _BrandAwareRepo();
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
}

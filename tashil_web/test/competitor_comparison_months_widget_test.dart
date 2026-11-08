import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_months.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/data/competitor_comparison_repository.dart';
import 'package:tashil_web/features/competitor_comparison/domain/competitor_month_options.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';

class _FakeRepo implements CompetitorComparisonSource {
  _FakeRepo(this.groups);

  final List<OwnSkuCompetitiveGroupModel> groups;

  @override
  Future<Result<List<OwnSkuCompetitiveGroupModel>>> loadGroups({
    String? chain,
    required int year,
    required int month,
    bool forceRefresh = false,
  }) async =>
      Success(groups);

  @override
  Future<Result<List<OwnSkuCompetitiveGroupModel>>> rebuildLocal({
    String? chain,
    required int year,
    required int month,
  }) async =>
      Success(groups);

  @override
  bool isCustomSku(String barcode) => false;

  @override
  Future<Result<void>> addCustomSku({
    required String ownBarcode,
    required String ownSkuName,
    required double ownUnitPrice,
    required double ownVolumeUnits,
    required String ownVolumeUnitLabel,
    required String competitorSkuName,
    required String competitorBrand,
    required String competitorSupplier,
    required String category,
    required String packSizeLabel,
    required double packVolumeUnits,
    required double competitorPrice,
    required String retailerChain,
    bool isPromoActive = false,
  }) async =>
      const Success(null);

  @override
  Future<Result<void>> deleteCustomSku(String barcode) async => const Success(null);
}

List<SkuMonthlyPricePointModel> _series(int year, int throughMonth) {
  return [
    for (var m = 1; m <= throughMonth; m++)
      SkuMonthlyPricePointModel(
        monthKey: '$year-${m.toString().padLeft(2, '0')}',
        year: year,
        monthNum: m,
        monthNameAr: ApiClient.formatArabicMonthOnly(m),
        monthLabelAr: '${ApiClient.formatArabicMonthOnly(m)} $year',
        unitPrice: 150.0 + m,
        unitsSold: 100 + m,
        netRevenue: (150.0 + m) * (100 + m),
        priceChangeEgp: m == 1 ? 0 : 1,
        priceChangePct: m == 1 ? 0 : 0.5,
        trendDirection: m == 1 ? 'baseline' : 'up',
      ),
  ];
}

OwnSkuCompetitiveGroupModel _groupWithMonths(int throughMonth) {
  final monthly = _series(2026, throughMonth);
  return OwnSkuCompetitiveGroupModel(
    ownBarcode: '6223000239438',
    ownSkuName: 'فيبا 3 كجم',
    ownBrand: 'فيبا (Feba)',
    category: 'صابون سائل اطباق',
    packSizeLabel: '3 كجم',
    packVolumeUnits: 3,
    volumeUnitLabel: 'كجم',
    ownUnitPrice: 160,
    ownRecommendedPrice: 160,
    ownPricePerUnitVolume: 53.3,
    ownUnitsSold: 300,
    ownNetRevenue: 48000,
    ownCategorySharePct: 30,
    avgCompetitorPrice: 150,
    minCompetitorPrice: 150,
    maxCompetitorPrice: 150,
    priceIndex: 106.7,
    ownChainPrices: const {'fathalla': 160},
    competitors: const [],
    monthlyPrices: monthly,
    allMonthlyPrices: monthly,
    selectedYear: 2026,
    selectedMonth: 0,
  );
}

void main() {
  setUp(AvailableMonths.clearForTest);

  testWidgets('10 months → ChoiceChips show كل الشهور (يناير - أكتوبر) and Oct', (tester) async {
    final months = List<int>.generate(10, (i) => i + 1);
    final opts = CompetitorMonthOptions.build(months, year: 2026);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final m in opts)
                ChoiceChip(
                  label: Text(m.labelAr),
                  selected: m.month == 0,
                  onSelected: (_) {},
                ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('كل الشهور (يناير - أكتوبر) — 2026'), findsOneWidget);
    expect(find.text('يناير (01)'), findsOneWidget);
    expect(find.text('أكتوبر (10)'), findsOneWidget);
    expect(find.text('كل الشهور (يناير - أبريل)'), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(11));
  });

  testWidgets('screen with 10-month series surfaces Jan–Oct all-months chip', (tester) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Ignore incidental layout overflows elsewhere on the dense compare screen;
    // this test only asserts the dynamic month picker labels.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    AvailableMonths.setForTest(const MonthOptions(year: 2026, months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
    final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
    final repo = _FakeRepo([_groupWithMonths(10)]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetitorComparisonScreen(apiClient: api, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('كل الشهور (يناير - أكتوبر) — 2026'), findsWidgets);
    expect(find.text('أكتوبر (10)'), findsOneWidget);
    expect(find.text('كل الشهور (يناير - أبريل)'), findsNothing);
  });

  testWidgets('API Jan–Oct wins when series is only Jan–Apr seeds', (tester) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    AvailableMonths.setForTest(const MonthOptions(year: 2026, months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
    final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
    // Seed-like series: only through April — previously this truncated the picker label.
    final repo = _FakeRepo([_groupWithMonths(4)]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetitorComparisonScreen(apiClient: api, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('كل الشهور (يناير - أكتوبر) — 2026'), findsWidgets);
    expect(find.text('أكتوبر (10)'), findsOneWidget);
    expect(find.text('كل الشهور (يناير - أبريل) — 2026'), findsNothing);
  });
}

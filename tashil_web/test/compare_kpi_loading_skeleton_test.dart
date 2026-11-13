import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_months.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/competitor_comparison/data/competitor_comparison_repository.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';

/// Delays [loadGroups] until [gate] completes so the loading KPI state is observable.
class _GatedRepo implements CompetitorComparisonSource {
  _GatedRepo(this.groups, this.gate);

  final List<OwnSkuCompetitiveGroupModel> groups;
  final Completer<void> gate;

  @override
  Future<Result<List<OwnSkuCompetitiveGroupModel>>> loadGroups({
    String? chain,
    required int year,
    required int month,
    bool forceRefresh = false,
  }) async {
    await gate.future;
    return Success(groups);
  }

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

OwnSkuCompetitiveGroupModel _sampleGroup() {
  return const OwnSkuCompetitiveGroupModel(
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
    ownChainPrices: {'fathalla': 160},
    competitors: [],
    monthlyPrices: [],
    allMonthlyPrices: [],
    selectedYear: 2026,
    selectedMonth: 0,
  );
}

void main() {
  setUp(() {
    AvailableMonths.clearForTest();
    AvailableYears.setForTest(const YearOptions(years: [2026], defaultYear: 2026));
    AvailableMonths.setForTest(const MonthOptions(year: 2026, months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
  });

  tearDown(AvailableMonths.clearForTest);

  testWidgets(
    'Compare KPI cards show skeletons while loading; never flash zeros; real zeros after empty load',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      final gate = Completer<void>();
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final repo = _GatedRepo(const [], gate);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CompetitorComparisonScreen(apiClient: api, repository: repo),
          ),
        ),
      );
      await tester.pump();

      // Loading: skeletons in each KPI card; computed zero placeholders must not flash.
      expect(find.byKey(const ValueKey('compare_kpi_skeleton')), findsNWidgets(4));
      expect(find.textContaining('0 أصناف'), findsNothing);
      expect(find.textContaining('0 من 0'), findsNothing);
      expect(find.textContaining('100.0%'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      // After an empty competitive-monthly response, real zeros are allowed.
      expect(find.byKey(const ValueKey('compare_kpi_skeleton')), findsNothing);
      // KPI value «0 أصناف» (+ detail «… في 0 أصناف»).
      expect(find.text('0 أصناف'), findsOneWidget);
      expect(find.textContaining('0 من 0'), findsOneWidget);
      expect(find.textContaining('100.0%'), findsOneWidget);
    },
  );

  testWidgets(
    'Compare KPI cards show real counts after competitive-monthly data loads',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      final gate = Completer<void>();
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final repo = _GatedRepo([_sampleGroup()], gate);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CompetitorComparisonScreen(apiClient: api, repository: repo),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('compare_kpi_skeleton')), findsNWidgets(4));
      expect(find.text('صنف واحد'), findsNothing);
      expect(find.text('106.7%'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('compare_kpi_skeleton')), findsNothing);
      // KPI value + filtered-groups count chip both read "صنف واحد".
      expect(find.text('صنف واحد'), findsNWidgets(2));
      expect(find.text('106.7%'), findsOneWidget);
    },
  );
}

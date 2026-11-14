import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/available_months.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:tashil_web/features/competitor_comparison/data/competitor_comparison_repository.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';

import 'helpers/m3_dropdown_tester.dart';

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
  Future<Result<void>> deleteCustomSku(String barcode) async =>
      const Success(null);
}

OwnSkuCompetitiveGroupModel _group({
  required int index,
  String category = 'صابون سائل اطباق',
}) {
  final barcode = '6223000${(100000 + index).toString()}';
  return OwnSkuCompetitiveGroupModel(
    ownBarcode: barcode,
    ownSkuName: 'صنف اختبار رقم $index',
    ownBrand: 'فيبا (Feba)',
    category: category,
    packSizeLabel: '3 كجم',
    packVolumeUnits: 3,
    volumeUnitLabel: 'كجم',
    ownUnitPrice: 100 + index.toDouble(),
    ownRecommendedPrice: 100 + index.toDouble(),
    ownPricePerUnitVolume: 33.3,
    ownUnitsSold: 100,
    ownNetRevenue: 10000,
    ownCategorySharePct: 10,
    avgCompetitorPrice: 95,
    minCompetitorPrice: 90,
    maxCompetitorPrice: 110,
    priceIndex: 105,
    ownChainPrices: const {'fathalla': 100},
    competitors: const [],
    monthlyPrices: const [],
    allMonthlyPrices: const [],
    selectedYear: 2026,
    selectedMonth: 0,
  );
}

/// Suppress dense-layout overflow noise from the compare screen chrome.
void _ignoreCompareOverflows() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _pumpCompare(
  WidgetTester tester, {
  required List<OwnSkuCompetitiveGroupModel> groups,
  TextDirection textDirection = TextDirection.rtl,
}) async {
  tester.view.physicalSize = const Size(1600, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _ignoreCompareOverflows();

  AvailableMonths.setForTest(
    const MonthOptions(year: 2026, months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
  );
  final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
  final repo = _FakeRepo(groups);

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: CompetitorComparisonScreen(apiClient: api, repository: repo),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AvailableMonths.clearForTest();
    AvailableYears.setForTest(
      const YearOptions(years: [2026], defaultYear: 2026),
    );
    AvailableMonths.setForTest(
      const MonthOptions(year: 2026, months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    );
  });
  tearDown(AvailableMonths.clearForTest);

  testWidgets('own-SKU list shows 10 per page with Arabic indicators', (tester) async {
    final groups = [for (var i = 1; i <= 25; i++) _group(index: i)];
    await _pumpCompare(tester, groups: groups);

    expect(find.byKey(const ValueKey('own_sku_pagination_bar')), findsOneWidget);
    expect(find.text('صفحة 1 من 3'), findsOneWidget);
    expect(find.text('1–10 من 25'), findsOneWidget);
    // Selected SKU also appears in the detail spotlight → findsWidgets.
    expect(find.text('صنف اختبار رقم 1'), findsWidgets);
    expect(find.text('صنف اختبار رقم 10'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 11'), findsNothing);

    // Prev disabled on first page.
    final prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('own_sku_pagination_prev_btn')),
    );
    expect(prev.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_next_btn')));
    await tester.pumpAndSettle();

    expect(find.text('صفحة 2 من 3'), findsOneWidget);
    expect(find.text('11–20 من 25'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 11'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 20'), findsOneWidget);
    // Default selection (item 1) remains selected off-page → still in spotlight.
    expect(find.text('صنف اختبار رقم 1'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_next_btn')));
    await tester.pumpAndSettle();

    expect(find.text('صفحة 3 من 3'), findsOneWidget);
    expect(find.text('21–25 من 25'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 25'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 11'), findsNothing);

    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('own_sku_pagination_next_btn')),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_prev_btn')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة 2 من 3'), findsOneWidget);
  });

  testWidgets('category filter resets to page 1 and paginates filtered set',
      (tester) async {
    final groups = [
      for (var i = 1; i <= 15; i++)
        _group(index: i, category: i <= 12 ? 'صابون سائل اطباق' : 'منظف ارضيات'),
    ];
    await _pumpCompare(tester, groups: groups);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_next_btn')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة 2 من 2'), findsOneWidget);

    // Category filter (M3Dropdown) → page 1 of the filtered subset (3 floor cleaners).
    await selectM3Option(
      tester,
      find.byKey(const ValueKey('compare_category_dropdown')),
      'منظف ارضيات',
    );

    expect(find.text('صفحة 1 من 1'), findsOneWidget);
    expect(find.text('1–3 من 3'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 13'), findsWidgets);
    expect(find.text('صنف اختبار رقم 1'), findsNothing);
  });

  testWidgets('search query resets page and paginates filtered results', (tester) async {
    final groups = [for (var i = 1; i <= 22; i++) _group(index: i)];
    await _pumpCompare(tester, groups: groups);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_next_btn')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة 2 من 3'), findsOneWidget);

    // Unique match for a single item that lived on page 2 of the unfiltered list.
    await tester.enterText(find.byType(TextField).first, 'صنف اختبار رقم 12');
    await tester.pumpAndSettle();

    expect(find.text('صفحة 1 من 1'), findsOneWidget);
    expect(find.text('1–1 من 1'), findsOneWidget);
    expect(find.text('صنف اختبار رقم 12'), findsWidgets);
    expect(find.text('صنف اختبار رقم 11'), findsNothing);
  });

  testWidgets('selected SKU stays selected across page changes', (tester) async {
    final groups = [for (var i = 1; i <= 15; i++) _group(index: i)];
    await _pumpCompare(tester, groups: groups);

    // Select item 2 on page 1.
    await tester.tap(find.text('صنف اختبار رقم 2'));
    await tester.pumpAndSettle();

    // Spotlight / detail should reflect selection; master card stays selected
    // even after leaving its page.
    expect(find.text('صنف اختبار رقم 2'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_next_btn')));
    await tester.pumpAndSettle();

    // Page 2 no longer lists item 2 in the master list, but detail still shows it.
    expect(find.text('صنف اختبار رقم 11'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('own_sku_pagination_bar')),
        matching: find.text('صنف اختبار رقم 2'),
      ),
      findsNothing,
    );
    // Detail / spotlight still references the selected own SKU.
    expect(find.text('صنف اختبار رقم 2'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('own_sku_pagination_prev_btn')));
    await tester.pumpAndSettle();
    expect(find.text('صنف اختبار رقم 2'), findsWidgets);
  });

  testWidgets('pagination arrows use RTL-mirrored AppIcons chevrons', (tester) async {
    final groups = [for (var i = 1; i <= 12; i++) _group(index: i)];
    await _pumpCompare(tester, groups: groups, textDirection: TextDirection.rtl);

    final prevIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('own_sku_pagination_prev_btn')),
        matching: find.byType(Icon),
      ),
    );
    final nextIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('own_sku_pagination_next_btn')),
        matching: find.byType(Icon),
      ),
    );
    expect(prevIcon.icon, AppIcons.chevronStart);
    expect(nextIcon.icon, AppIcons.chevronEnd);
    expect(AppIcons.chevronStart.matchTextDirection, isTrue);
    expect(AppIcons.chevronEnd.matchTextDirection, isTrue);

    // In RTL, previous sits at the reading start (right side of the bar).
    final prevCenter = tester.getCenter(
      find.byKey(const ValueKey('own_sku_pagination_prev_btn')),
    );
    final nextCenter = tester.getCenter(
      find.byKey(const ValueKey('own_sku_pagination_next_btn')),
    );
    expect(prevCenter.dx, greaterThan(nextCenter.dx));
  });
}

// Test-only Compare fixture: made-up own SKUs, competitors and monthly prices
// (no customer data). Shared by Compare widget tests.
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/data/competitor_comparison_repository.dart';

class CompareFakeRepo implements CompetitorComparisonSource {
  CompareFakeRepo([List<OwnSkuCompetitiveGroupModel>? groups])
      : groups = groups ?? compareFixtureGroups();

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

List<SkuMonthlyPricePointModel> compareFixtureSeries(double base,
    {int year = 2026, int throughMonth = 10}) => [
      for (var m = 1; m <= throughMonth; m++)
        SkuMonthlyPricePointModel(
          monthKey: '$year-${m.toString().padLeft(2, '0')}',
          year: year,
          monthNum: m,
          monthNameAr: ApiClient.formatArabicMonthOnly(m),
          monthLabelAr: '${ApiClient.formatArabicMonthOnly(m)} $year',
          unitPrice: base + m,
          unitsSold: 100 + m,
          netRevenue: (base + m) * (100 + m),
          priceChangeEgp: m == 1 ? 0 : 1,
          priceChangePct: m == 1 ? 0 : 0.6,
          trendDirection: m == 1 ? 'baseline' : 'up',
        ),
    ];

const compareLongOwnName =
    'منظف أرضيات تجريبي برائحة اللافندر والياسمين عبوة اقتصادية كبيرة الحجم 3 كجم';
const compareLongCompetitorName =
    'منظف أرضيات منافس تجريبي برائحة الليمون الأخضر المنعش عبوة عائلية 3 كجم';

String _pricePosition(double price, {double own = 160}) {
  final pct = own > 0 ? (price - own) / own * 100 : 0.0;
  if (pct > 1.5) return 'higher';
  if (pct < -1.5) return 'lower';
  return 'equal';
}

CompetitorSkuComparisonModel _competitor(int i, String name, double price) =>
    CompetitorSkuComparisonModel(
      skuName: name,
      barcode: '99900000000$i',
      supplierName: 'مورد منافس تجريبي $i',
      brand: 'منافس تجريبي $i',
      category: 'منظفات أرضيات',
      packSizeLabel: '3 كجم',
      packVolumeUnits: 3,
      volumeUnitLabel: 'كجم',
      unitPrice: price,
      pricePerUnitVolume: price / 3,
      priceDiffEgp: price - 160,
      priceDiffPct: (price - 160) / 160 * 100,
      pricePosition: _pricePosition(price),
      unitsSold: 200 + i,
      netRevenue: price * (200 + i),
      categorySharePct: 10.0 + i,
      monthlyPrices: compareFixtureSeries(price - 10),
      allMonthlyPrices: compareFixtureSeries(price - 10),
    );

List<OwnSkuCompetitiveGroupModel> compareFixtureGroups() {
  OwnSkuCompetitiveGroupModel g(
    int i,
    String name,
    List<CompetitorSkuComparisonModel> comps, {
    List<SkuMonthlyPricePointModel>? monthlyPrices,
  }) {
    final monthly = monthlyPrices ?? compareFixtureSeries(150.0 + i);
    final hasComps = comps.isNotEmpty;
    return OwnSkuCompetitiveGroupModel(
      ownBarcode: '62200000000$i',
      ownSkuName: name,
      ownBrand: 'علامة تجريبية',
      category: 'منظفات أرضيات',
      packSizeLabel: '3 كجم',
      packVolumeUnits: 3,
      volumeUnitLabel: 'كجم',
      ownUnitPrice: 160,
      ownRecommendedPrice: 160,
      ownPricePerUnitVolume: 53.3,
      ownUnitsSold: 300 + i,
      ownNetRevenue: 48000,
      ownCategorySharePct: 30,
      avgCompetitorPrice: hasComps ? 150 : 0,
      minCompetitorPrice: hasComps ? 140 : 0,
      maxCompetitorPrice: hasComps ? 170 : 0,
      priceIndex: hasComps ? 106.7 : 100.0,
      ownChainPrices: const {'fathalla': 160},
      competitors: comps,
      monthlyPrices: monthly,
      allMonthlyPrices: monthly,
      selectedYear: 2026,
      selectedMonth: 0,
    );
  }

  return [
    g(0, compareLongOwnName, [
      _competitor(0, compareLongCompetitorName, 145),
      _competitor(1, 'منافس قصير', 170),
    ]),
    g(1, 'صنف تجريبي قصير', [_competitor(2, 'منافس تجريبي آخر', 150)]),
    g(2, 'مبيض ملابس تجريبي شديد الفعالية للألوان البيضاء عبوة عائلية', const []),
  ];
}

/// Own SKU with no competitors and a single month of prices (period change N/A).
List<OwnSkuCompetitiveGroupModel> compareUnmappedShortSeriesGroups() => [
      OwnSkuCompetitiveGroupModel(
        ownBarcode: '62200000999',
        ownSkuName: 'صنف بلا منافسين',
        ownBrand: 'علامة تجريبية',
        category: 'منظفات أرضيات',
        packSizeLabel: '3 كجم',
        packVolumeUnits: 3,
        volumeUnitLabel: 'كجم',
        ownUnitPrice: 160,
        ownRecommendedPrice: 160,
        ownPricePerUnitVolume: 53.3,
        ownUnitsSold: 100,
        ownNetRevenue: 16000,
        ownCategorySharePct: 10,
        avgCompetitorPrice: 0,
        minCompetitorPrice: 0,
        maxCompetitorPrice: 0,
        priceIndex: 100.0,
        ownChainPrices: const {'fathalla': 160},
        competitors: const [],
        monthlyPrices: compareFixtureSeries(160, throughMonth: 1),
        allMonthlyPrices: compareFixtureSeries(160, throughMonth: 1),
        selectedYear: 2026,
        selectedMonth: 0,
      ),
    ];

OwnSkuCompetitiveGroupModel _scaleGroup(int i,
        {required List<SkuMonthlyPricePointModel> monthly,
        List<CompetitorSkuComparisonModel> competitors = const []}) =>
    OwnSkuCompetitiveGroupModel(
      ownBarcode: '6221${i.toString().padLeft(9, '0')}',
      ownSkuName: 'صنف تجريبي رقم $i',
      ownBrand: 'علامة تجريبية',
      category: 'منظفات أرضيات',
      packSizeLabel: '3 كجم',
      packVolumeUnits: 3,
      volumeUnitLabel: 'كجم',
      ownUnitPrice: 160,
      ownRecommendedPrice: 160,
      ownPricePerUnitVolume: 53.3,
      ownUnitsSold: 300 + i,
      ownNetRevenue: 48000,
      ownCategorySharePct: 30,
      avgCompetitorPrice: 150,
      minCompetitorPrice: 140,
      maxCompetitorPrice: 170,
      priceIndex: 106.7,
      ownChainPrices: const {'fathalla': 160},
      competitors: competitors,
      monthlyPrices: monthly,
      allMonthlyPrices: monthly,
      selectedYear: 2026,
      selectedMonth: 0,
    );

List<SkuMonthlyPricePointModel> _series(double Function(int m) price,
        {int fromMonth = 1, int throughMonth = 10}) =>
    [
      for (var m = fromMonth; m <= throughMonth; m++)
        SkuMonthlyPricePointModel(
          monthKey: '2026-${m.toString().padLeft(2, '0')}',
          year: 2026,
          monthNum: m,
          monthNameAr: ApiClient.formatArabicMonthOnly(m),
          monthLabelAr: '${ApiClient.formatArabicMonthOnly(m)} 2026',
          unitPrice: price(m),
          unitsSold: 100 + m,
          netRevenue: price(m) * (100 + m),
          priceChangeEgp: m == fromMonth ? 0 : price(m) - price(m - 1),
          priceChangePct: m == fromMonth
              ? 0
              : (price(m) - price(m - 1)) / price(m - 1) * 100,
          trendDirection: m == fromMonth
              ? 'baseline'
              : price(m) > price(m - 1)
                  ? 'up'
                  : price(m) < price(m - 1)
                      ? 'down'
                      : 'flat',
        ),
    ];

/// Live-scale KPI fixture (made-up numbers, live-like magnitudes):
/// 302 own SKUs — 243 price rises, 46 drops, 12 mapped with 105 competitors.
List<OwnSkuCompetitiveGroupModel> compareLiveScaleGroups() => [
      for (var i = 0; i < 302; i++)
        _scaleGroup(
          i,
          monthly: i < 243
              ? _series((m) => 100.0 + 5 * m)
              : i < 289
                  ? _series((m) => 200.0 - 5 * m)
                  : _series((m) => 150.0),
          competitors: i < 12
              ? [
                  for (var k = 0; k < (i < 9 ? 9 : 8); k++)
                    _competitor(i * 10 + k, 'منافس تجريبي $i-$k', 140.0 + k),
                ]
              : const [],
        ),
    ];

/// One own SKU whose only competitor has prices for May–Oct only
/// (Jan–Apr missing), with prices that cross ours.
List<OwnSkuCompetitiveGroupModel> compareGappyCompetitorGroups() {
  final comp = _competitor(7, 'منافس بشهور ناقصة', 180);
  final gappy = _series((m) => 260.0 - 10 * m, fromMonth: 5);
  return [
    _scaleGroup(0,
        monthly: _series((m) => 150.0 + 10 * m),
        competitors: [
          CompetitorSkuComparisonModel(
            skuName: comp.skuName,
            barcode: comp.barcode,
            supplierName: comp.supplierName,
            brand: 'منافس ناقص',
            category: comp.category,
            packSizeLabel: comp.packSizeLabel,
            packVolumeUnits: comp.packVolumeUnits,
            volumeUnitLabel: comp.volumeUnitLabel,
            unitPrice: comp.unitPrice,
            pricePerUnitVolume: comp.pricePerUnitVolume,
            priceDiffEgp: comp.priceDiffEgp,
            priceDiffPct: comp.priceDiffPct,
            pricePosition: 'higher',
            unitsSold: comp.unitsSold,
            netRevenue: comp.netRevenue,
            categorySharePct: comp.categorySharePct,
            monthlyPrices: gappy,
            allMonthlyPrices: gappy,
          ),
        ]),
  ];
}

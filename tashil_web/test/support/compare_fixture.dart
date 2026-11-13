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
      pricePosition: price < 160 ? 'cheaper' : 'more_expensive',
      unitsSold: 200 + i,
      netRevenue: price * (200 + i),
      categorySharePct: 10.0 + i,
      monthlyPrices: compareFixtureSeries(price - 10),
      allMonthlyPrices: compareFixtureSeries(price - 10),
    );

List<OwnSkuCompetitiveGroupModel> compareFixtureGroups() {
  OwnSkuCompetitiveGroupModel g(int i, String name, List<CompetitorSkuComparisonModel> comps) {
    final monthly = compareFixtureSeries(150.0 + i);
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
      avgCompetitorPrice: 150,
      minCompetitorPrice: 140,
      maxCompetitorPrice: 170,
      priceIndex: 106.7,
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

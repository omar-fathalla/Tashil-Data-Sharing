import '../../../core/data/app_cache.dart';
import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';

/// One load of the Sell-Out explorer: records + server summary + stores + branch matrices.
class SellOutExplorerData {
  final List<SellOutRecordModel> records;

  /// Server summary captured right after the records call (null if the server sent none).
  final SellOutRecordsSummaryModel? summary;
  final List<Map<String, dynamic>> stores;

  /// Full selected-period branch matrix (drives displayed totals / charts).
  final List<StoreBenchmarkItem> currentBranchMatrix;

  /// Previous-year matrix trimmed to months present in the selected year
  /// (and/or the shifted custom date range).
  final List<StoreBenchmarkItem> prevBranchMatrix;

  /// Selected-year matrix trimmed to months present last year — used ONLY for
  /// like-for-like YoY growth. Displayed current-year totals stay on
  /// [currentBranchMatrix] / the records summary.
  final List<StoreBenchmarkItem> yoyCurrentBranchMatrix;

  /// Calendar months present in both the selected and the previous year. Empty
  /// when a month/date range pins the period, or when the lookup failed.
  final List<int> matchedMonths;

  const SellOutExplorerData({
    required this.records,
    required this.summary,
    required this.stores,
    required this.currentBranchMatrix,
    required this.prevBranchMatrix,
    required this.yoyCurrentBranchMatrix,
    this.matchedMonths = const [],
    this.sideError,
  });

  /// Set when a side request (stores / branch matrix) failed. The records table is
  /// still shown; only the widgets fed by the failed request render empty.
  final Object? sideError;
}

/// Shifts a 'YYYY-MM-DD' date by [years] (29 Feb becomes 28 Feb). Null or
/// unparsable input returns null.
String? shiftDateByYears(String? date, int years) {
  if (date == null || date.length < 10) return null;
  final y = int.tryParse(date.substring(0, 4));
  final m = int.tryParse(date.substring(5, 7));
  final d = int.tryParse(date.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  final ny = y + years;
  final lastDay = DateTime(ny, m + 1, 0).day;
  final nd = d > lastDay ? lastDay : d;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${ny.toString().padLeft(4, '0')}-${two(m)}-${two(nd)}${date.substring(10)}';
}

/// Like-for-like YoY growth percent. Null when there is no overlapping
/// prior-year base (UI shows «—» / «لا توجد بيانات للعام السابق»).
double? likeForLikeYoyPct(double currentLikeForLike, double previousLikeForLike) {
  if (previousLikeForLike <= 0) return null;
  return ((currentLikeForLike - previousLikeForLike) / previousLikeForLike) * 100.0;
}

/// True when the explorer should trim each YoY side to months present in the
/// other year (no explicit month / custom range already pins the period).
bool sellOutNeedsYoyMonthIntersect({int? month, String? startDate, String? endDate}) {
  final hasMonth = month != null && month > 0;
  final hasRange = (startDate != null && startDate.isNotEmpty) || (endDate != null && endDate.isNotEmpty);
  return !hasMonth && !hasRange;
}

/// Filter combo used both for the request and as the cache key.
class SellOutExplorerQuery {
  final String? chain;
  final String? storeId;
  final String? category;
  final String query;
  final String? startDate;
  final String? endDate;
  final int? year;
  final int? month;
  final int limit;

  /// Branch-matrix params (chart chain + matrix year / comparison year).
  final String? matrixChain;
  final int? matrixYear;
  final int compYear;

  /// Brand filter for store-matrix / YoY branch aggregates (null / 'all' = every brand).
  final String? matrixBrand;

  const SellOutExplorerQuery({
    this.chain,
    this.storeId,
    this.category,
    this.query = '',
    this.startDate,
    this.endDate,
    this.year,
    this.month,
    this.limit = 1000,
    this.matrixChain,
    this.matrixYear,
    required this.compYear,
    this.matrixBrand,
  });

  List<Object?> get parts =>
      [chain, storeId, category, query, startDate, endDate, year, month, limit, matrixChain, matrixYear, compYear, matrixBrand];
}

/// Repository for the Sell-Out explorer (records + branch analytics). Caches per filter combo
/// (tenant/role aware); uploads, sheet deletes and product edits must call [invalidateAll].
class SellOutExplorerRepository {
  static const feature = 'sell_out_explorer';

  final ApiClient api;
  final CacheStore cache;

  SellOutExplorerRepository(this.api, {CacheStore? cache})
      : cache = cache ?? AppCache.forApi(api);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  Future<Result<SellOutExplorerData>> load(SellOutExplorerQuery q, {bool forceRefresh = false}) {
    final u = api.currentUser;
    final k = CacheStore.key(api.tenantId, feature, [u?.role, u?.assignedChain, u?.assignedRegion, ...q.parts]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<SellOutExplorerData>(k, () async {
          final records = await api.getRecords(
            chain: q.chain,
            storeId: q.storeId,
            category: q.category,
            query: q.query,
            startDate: q.startDate,
            endDate: q.endDate,
            year: q.year,
            month: q.month,
            limit: q.limit,
          );
          final summary = api.lastSellOutSummary;
          // Side widgets fail independently: the table only depends on getRecords.
          Object? sideError;
          Future<T> side<T>(Future<T> f, T empty) => f.catchError((Object e) {
                sideError ??= e;
                return empty;
              });
          final intersect = sellOutNeedsYoyMonthIntersect(
            month: q.month,
            startDate: q.startDate,
            endDate: q.endDate,
          );
          final refYearForPrev = q.matrixYear ?? (q.compYear + 1);
          final brand = q.matrixBrand;
          final results = await Future.wait([
            side<Object>(api.getStores(), const <Map<String, dynamic>>[]),
            side<Object>(
              api.getStoreBenchmarkMatrix(
                chain: q.matrixChain,
                brand: brand,
                year: q.matrixYear,
                month: q.month,
                startDate: q.startDate,
                endDate: q.endDate,
              ),
              const <StoreBenchmarkItem>[],
            ),
            side<Object>(
              api.getStoreBenchmarkMatrix(
                chain: q.matrixChain,
                brand: brand,
                year: q.compYear,
                month: q.month,
                // Same period last year: the date range is shifted one year
                // and, with no month picked, only months present in the
                // selected year are kept (aligns prev side of the intersection).
                startDate: shiftDateByYears(q.startDate, -1),
                endDate: shiftDateByYears(q.endDate, -1),
                sameMonthsAs: intersect ? refYearForPrev : null,
              ),
              const <StoreBenchmarkItem>[],
            ),
            // Like-for-like CURRENT year for YoY only: months that exist last
            // year. Displayed totals keep the full current matrix above.
            side<Object>(
              intersect
                  ? api.getStoreBenchmarkMatrix(
                      chain: q.matrixChain,
                      brand: brand,
                      year: q.matrixYear,
                      month: q.month,
                      startDate: q.startDate,
                      endDate: q.endDate,
                      sameMonthsAs: q.compYear,
                    )
                  : Future<List<StoreBenchmarkItem>>.value(const <StoreBenchmarkItem>[]),
              const <StoreBenchmarkItem>[],
            ),
            // Label only: a failure (or an older backend without the route) must
            // not flag sideError, the table works without the month caption.
            (intersect && q.matrixYear != null && q.matrixYear! > 0
                    ? api.getYoyMatchedMonths(
                        chain: q.matrixChain,
                        year: q.matrixYear!,
                        compYear: q.compYear,
                      )
                    : Future<List<int>>.value(const <int>[]))
                .catchError((Object _) => const <int>[]),
          ]);
          final current = results[1] as List<StoreBenchmarkItem>;
          final yoyCurrentRaw = results[3] as List<StoreBenchmarkItem>;
          return SellOutExplorerData(
            records: records,
            summary: summary,
            stores: results[0] as List<Map<String, dynamic>>,
            currentBranchMatrix: current,
            prevBranchMatrix: results[2] as List<StoreBenchmarkItem>,
            yoyCurrentBranchMatrix: intersect ? yoyCurrentRaw : current,
            matchedMonths: results[4] as List<int>,
            sideError: sideError,
          );
        }));
  }
}

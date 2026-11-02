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
  final List<StoreBenchmarkItem> currentBranchMatrix;
  final List<StoreBenchmarkItem> prevBranchMatrix;

  const SellOutExplorerData({
    required this.records,
    required this.summary,
    required this.stores,
    required this.currentBranchMatrix,
    required this.prevBranchMatrix,
    this.sideError,
  });

  /// Set when a side request (stores / branch matrix) failed. The records table is
  /// still shown; only the widgets fed by the failed request render empty.
  final Object? sideError;
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
  });

  List<Object?> get parts =>
      [chain, storeId, category, query, startDate, endDate, year, month, limit, matrixChain, matrixYear, compYear];
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
          final results = await Future.wait([
            side<Object>(api.getStores(), const <Map<String, dynamic>>[]),
            side<Object>(
              api.getStoreBenchmarkMatrix(
                chain: q.matrixChain,
                year: q.matrixYear,
                month: q.month,
                startDate: q.startDate,
                endDate: q.endDate,
              ),
              const <StoreBenchmarkItem>[],
            ),
            side<Object>(
              api.getStoreBenchmarkMatrix(chain: q.matrixChain, year: q.compYear, month: q.month),
              const <StoreBenchmarkItem>[],
            ),
          ]);
          return SellOutExplorerData(
            records: records,
            summary: summary,
            stores: results[0] as List<Map<String, dynamic>>,
            currentBranchMatrix: results[1] as List<StoreBenchmarkItem>,
            prevBranchMatrix: results[2] as List<StoreBenchmarkItem>,
            sideError: sideError,
          );
        }));
  }
}

import '../../../core/data/app_cache.dart';
import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';

/// Filter combo used both for the Sell-In request and as the cache key.
class SellInExplorerQuery {
  final String? chain;
  final int? year;
  final int? month;
  final String query;
  final int limit;
  final int offset;

  const SellInExplorerQuery({this.chain, this.year, this.month, this.query = '', this.limit = 250, this.offset = 0});

  List<Object?> get parts => [chain, year, month, query, limit, offset];

  SellInExplorerQuery copyWith({int? limit, int? offset}) => SellInExplorerQuery(
        chain: chain,
        year: year,
        month: month,
        query: query,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
      );
}

/// Repository for Sell-In explorer records. Caches per filter combo (tenant/role aware);
/// uploads and sheet deletes must call [invalidateAll].
class SellInExplorerRepository {
  static const feature = 'sell_in_explorer';

  /// Backend max rows per sell-in-records request.
  static const exportPageSize = 1000;

  /// Hard stop for [loadAllPages]: 200 × 1000 rows, far above any tenant's filtered Sell-In.
  static const maxExportPages = 200;

  final ApiClient api;
  final CacheStore cache;

  SellInExplorerRepository(this.api, {CacheStore? cache})
      : cache = cache ?? AppCache.forApi(api);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  /// One page of rows ([SellInExplorerQuery.limit] / [SellInExplorerQuery.offset]) plus the
  /// server-side totals for the whole filter.
  Future<Result<SellInExplorerResponse>> load(SellInExplorerQuery q, {bool forceRefresh = false}) {
    final u = api.currentUser;
    final k = CacheStore.key(api.tenantId, feature, [u?.role, u?.assignedChain, u?.assignedRegion, ...q.parts]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<SellInExplorerResponse>(
          k,
          () => api.getSellInRecords(
            chain: q.chain,
            year: q.year,
            month: q.month,
            query: q.query,
            limit: q.limit,
            offset: q.offset,
          ),
        ));
  }

  /// Every row of [q]'s filter, for exports only (never for display). Uncached, sequential and
  /// bounded: stops at total_count, on a short or empty page, when a page brings no new
  /// record ids (a backend ignoring offset), after [maxPages], or once [isCancelled] is true.
  Future<Result<List<SellInRecordItem>>> loadAllPages(
    SellInExplorerQuery q, {
    int pageSize = exportPageSize,
    int maxPages = maxExportPages,
    bool Function()? isCancelled,
  }) {
    return Result.guard(() async {
      final out = <SellInRecordItem>[];
      final seen = <String>{};
      var offset = 0;
      for (var i = 0; i < maxPages; i++) {
        if (isCancelled?.call() ?? false) break;
        final page = await api.getSellInRecords(
          chain: q.chain,
          year: q.year,
          month: q.month,
          query: q.query,
          limit: pageSize,
          offset: offset,
          cacheable: false,
        );
        if (isCancelled?.call() ?? false) break;
        var fresh = 0;
        for (final r in page.records) {
          if (r.recordId.isEmpty || seen.add(r.recordId)) {
            out.add(r);
            fresh++;
          }
        }
        offset += page.records.length;
        if (fresh == 0 || page.records.length < pageSize || offset >= page.totalCount) break;
      }
      return out;
    });
  }
}

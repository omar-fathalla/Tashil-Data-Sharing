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

  const SellInExplorerQuery({this.chain, this.year, this.month, this.query = '', this.limit = 250});

  List<Object?> get parts => [chain, year, month, query, limit];
}

/// Repository for Sell-In explorer records. Caches per filter combo (tenant/role aware);
/// uploads and sheet deletes must call [invalidateAll].
class SellInExplorerRepository {
  static const feature = 'sell_in_explorer';

  final ApiClient api;
  final CacheStore cache;

  SellInExplorerRepository(this.api, {CacheStore? cache})
      : cache = cache ?? CacheStore(defaultTtl: const Duration(minutes: 5));

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

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
          ),
        ));
  }
}

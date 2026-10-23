import '../../../core/data/app_cache.dart';
import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';

/// Repository for the Store Benchmark (store matrix) screen. Wraps [ApiClient]
/// with [Result] errors and a tenant/role-aware cache keyed per filter combo.
class StoreBenchmarkRepository {
  static const feature = 'store_benchmark';

  final ApiClient api;
  final CacheStore cache;

  StoreBenchmarkRepository(this.api, {CacheStore? cache})
      : cache = cache ?? AppCache.forApi(api);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  Future<Result<List<StoreBenchmarkItem>>> loadMatrix({
    String? region,
    String? tier,
    String? chain,
    int? year,
    int? month,
    bool forceRefresh = false,
  }) {
    final u = api.currentUser;
    final k = CacheStore.key(api.tenantId, feature,
        [u?.role, u?.assignedChain, u?.assignedRegion, region, tier, chain, year, month]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<List<StoreBenchmarkItem>>(
          k,
          () => api.getStoreBenchmarkMatrix(region: region, tier: tier, chain: chain, year: year, month: month),
        ));
  }
}

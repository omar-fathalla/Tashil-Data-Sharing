import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';

/// Repository for the Executive Dashboard. Short-TTL cache (KPIs change as Excel is ingested)
/// keyed by tenant/role/assigned chain/period/date range/chain, plus [Result] errors.
/// ApiClient's own stale cache is still exposed via [peekStale] for instant first paint.
class ExecutiveDashboardRepository {
  static const feature = 'executive_kpis';
  static const ttl = Duration(seconds: 60);

  final ApiClient api;
  final CacheStore cache;

  ExecutiveDashboardRepository(this.api, {CacheStore? cache}) : cache = cache ?? CacheStore(defaultTtl: ttl);

  String _key(String period, String? startDate, String? endDate, String? chain) => CacheStore.key(api.tenantId,
      feature, [api.currentUser?.role, api.currentUser?.assignedChain, period, startDate, endDate, chain]);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  /// Fresh (within TTL) value from this repository's cache, if any.
  ExecutiveKPIsModel? peekFresh({required String period, String? startDate, String? endDate, String? chain}) =>
      cache.get<ExecutiveKPIsModel>(_key(period, startDate, endDate, chain));

  /// Possibly-stale value from ApiClient's long-lived cache (unchanged behavior).
  ExecutiveKPIsModel? peekStale({required String period, String? startDate, String? endDate, String? chain}) =>
      api.getCachedExecutiveKPIs(period: period, startDate: startDate, endDate: endDate, chain: chain);

  Future<Result<ExecutiveKPIsModel>> loadKpis({
    required String period,
    String? startDate,
    String? endDate,
    String? chain,
    bool forceRefresh = false,
  }) {
    final k = _key(period, startDate, endDate, chain);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<ExecutiveKPIsModel>(
          k,
          () => api.getExecutiveKPIs(period: period, startDate: startDate, endDate: endDate, chain: chain),
        ));
  }
}

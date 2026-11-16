import '../../../core/data/app_cache.dart';
import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';
import 'target_breakdown_models.dart';

/// Read-side repository for the Target Management panel (sell_out / sell_in targets).
/// Caches per target type + chain + year (tenant/role aware). Upserts and Excel uploads
/// must call [invalidateAll].
class TargetRepository {
  static const feature = 'targets';

  final ApiClient api;
  final CacheStore cache;

  TargetRepository(this.api, {CacheStore? cache})
      : cache = cache ?? AppCache.forApi(api);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  List<Object?> get _userParts {
    final u = api.currentUser;
    return [u?.role, u?.assignedChain, u?.assignedRegion];
  }

  Future<Result<TargetsSummaryModel>> loadSummary({
    required String targetType,
    String? chain,
    int? year,
    bool forceRefresh = false,
  }) {
    final k = CacheStore.key(api.tenantId, feature, ['summary', ..._userParts, targetType, chain, year]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<TargetsSummaryModel>(
          k,
          () => api.getTargetsSummary(targetType: targetType, chain: chain, year: year),
        ));
  }

  Future<Result<List<RetailChainModel>>> loadChains({bool forceRefresh = false}) {
    final k = CacheStore.key(api.tenantId, feature, ['chains', ..._userParts]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<List<RetailChainModel>>(k, () => api.getRetailChains()));
  }

  /// Branch / SKU distribution of one Sell-Out target (read-only, computed in BigQuery).
  Future<Result<TargetBreakdownModel>> loadBreakdown(
    String targetId, {
    bool forceRefresh = false,
  }) {
    final k = CacheStore.key(api.tenantId, feature, ['breakdown', ..._userParts, targetId]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<TargetBreakdownModel>(
          k,
          () async => TargetBreakdownModel.fromJson(await api.getTargetBreakdownJson(targetId)),
        ));
  }
}

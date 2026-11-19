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
  /// Optional [branch] (store key) and [month] (1..12) live-filter Monthly / KPIs / Items.
  Future<Result<TargetBreakdownModel>> loadBreakdown(
    String targetId, {
    String? branch,
    int? month,
    bool forceRefresh = false,
  }) {
    final branchKey = (branch ?? '').trim();
    final monthKey = (month != null && month >= 1 && month <= 12) ? month : 0;
    final k = CacheStore.key(
      api.tenantId,
      feature,
      ['breakdown', ..._userParts, targetId, branchKey, monthKey],
    );
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<TargetBreakdownModel>(
          k,
          () async => TargetBreakdownModel.fromJson(
            await api.getTargetBreakdownJson(
              targetId,
              branch: branchKey.isEmpty ? null : branchKey,
              month: monthKey == 0 ? null : monthKey,
            ),
          ),
        ));
  }
}

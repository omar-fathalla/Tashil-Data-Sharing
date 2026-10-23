import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';

/// Repository for the Competitor Comparison screen. Wraps [ApiClient] (which stays the
/// source of truth for HTTP + custom-SKU state) and adds [Result] errors + a tenant-aware cache.
class CompetitorComparisonRepository {
  static const feature = 'competitor_groups';

  final ApiClient api;
  final CacheStore cache;

  CompetitorComparisonRepository(this.api, {CacheStore? cache})
      : cache = cache ?? CacheStore(defaultTtl: const Duration(minutes: 5));

  String _key(String? chain, int year, int month) =>
      CacheStore.key(api.tenantId, feature, [api.currentUser?.role, api.currentUser?.assignedChain, chain, year, month]);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  /// Loads competitive groups (ingested sell-out + saved custom SKUs).
  /// [forceRefresh] bypasses the cache (used by the screen's refresh button).
  Future<Result<List<OwnSkuCompetitiveGroupModel>>> loadGroups({
    String? chain,
    required int year,
    required int month,
    bool forceRefresh = false,
  }) {
    final k = _key(chain, year, month);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<List<OwnSkuCompetitiveGroupModel>>(
          k,
          () => api.getCompetitiveComparisonGroups(chain: chain, year: year, month: month),
        ));
  }

  /// Re-renders from ApiClient's in-memory custom SKUs without a server round-trip.
  Future<Result<List<OwnSkuCompetitiveGroupModel>>> rebuildLocal({
    String? chain,
    required int year,
    required int month,
  }) {
    return Result.guard(() async {
      final groups = await api.getCompetitiveComparisonGroups(
          chain: chain, year: year, month: month, syncCustomSkus: false);
      cache.put(_key(chain, year, month), groups);
      return groups;
    });
  }

  bool isCustomSku(String barcode) => api.isCustomCompetitorSku(barcode);

  /// Optimistic add: ApiClient updates its local list synchronously, then POSTs.
  /// Returns a Result that completes when the server confirms.
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
  }) {
    final saving = api.addCustomCompetitorSku(
      ownBarcode: ownBarcode,
      ownSkuName: ownSkuName,
      ownUnitPrice: ownUnitPrice,
      ownVolumeUnits: ownVolumeUnits,
      ownVolumeUnitLabel: ownVolumeUnitLabel,
      competitorSkuName: competitorSkuName,
      competitorBrand: competitorBrand,
      competitorSupplier: competitorSupplier,
      category: category,
      packSizeLabel: packSizeLabel,
      packVolumeUnits: packVolumeUnits,
      competitorPrice: competitorPrice,
      retailerChain: retailerChain,
      isPromoActive: isPromoActive,
    );
    invalidateAll();
    return Result.guard(() async {
      try {
        await saving;
      } finally {
        invalidateAll();
      }
    });
  }

  /// Optimistic delete (local removal happens synchronously inside ApiClient).
  Future<Result<void>> deleteCustomSku(String barcode) {
    final deleting = api.deleteCustomCompetitorSku(barcode);
    invalidateAll();
    return Result.guard(() async {
      try {
        await deleting;
      } finally {
        invalidateAll();
      }
    });
  }
}

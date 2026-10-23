import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';

/// Read-side repository for the Product Master screen. Writes (upload, item edit, sheet delete)
/// stay on [ApiClient]; callers must [invalidateAll] (or [prime] with the server copy) after them.
class ProductMasterRepository {
  static const feature = 'product_master';

  final ApiClient api;
  final CacheStore cache;

  ProductMasterRepository(this.api, {CacheStore? cache})
      : cache = cache ?? CacheStore(defaultTtl: const Duration(minutes: 5));

  String _key([String? search]) =>
      CacheStore.key(api.tenantId, feature, [api.currentUser?.role, api.currentUser?.assignedChain, search]);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  /// Stores a server-returned summary (e.g. after an item edit) as the unfiltered summary.
  void prime(ProductMasterSummaryModel summary) {
    invalidateAll();
    cache.put(_key(), summary);
  }

  Future<Result<ProductMasterSummaryModel>> loadSummary({String? search, bool forceRefresh = false}) {
    final k = _key(search);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(
        () => cache.getOrLoad<ProductMasterSummaryModel>(k, () => api.getProductMaster(search: search)));
  }

  /// Uploaded Product Master sheets (not cached: archive changes on every upload/delete).
  Future<Result<List<ArchivedExcelFileModel>>> loadArchive() => Result.guard(() async {
        final resp = await api.getUploadedFilesArchive(fileType: 'product_master');
        return resp.files;
      });
}

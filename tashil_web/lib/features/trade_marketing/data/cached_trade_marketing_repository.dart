import '../../../core/data/app_cache.dart';
import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';
import '../domain/trade_marketing_models.dart';
import 'trade_marketing_repository.dart';

/// Caching decorator for [TradeMarketingRepository].
///
/// Reads (expenses list, ROI baselines) are cached per tenant/role/filter; every write
/// (save, delete, upload) invalidates the feature cache. It still implements the throwing
/// [TradeMarketingRepository] contract (so [TradeMarketingException] keeps reaching the screen)
/// and adds [Result]-returning helpers for new call sites.
class CachedTradeMarketingRepository implements TradeMarketingRepository {
  static const feature = 'trade_marketing';

  final TradeMarketingRepository inner;
  final ApiClient api;
  final CacheStore cache;

  CachedTradeMarketingRepository(this.inner, this.api, {CacheStore? cache})
      : cache = cache ?? AppCache.forApi(api);

  String _key(String kind, int? year, int? month, String? chain) => CacheStore.key(
      api.tenantId, feature, [api.currentUser?.role, api.currentUser?.assignedChain, kind, year, month, chain]);

  void invalidateAll() => cache.invalidatePrefix(CacheStore.prefix(api.tenantId, feature));

  @override
  Future<List<MarketingExpenseItem>> listExpenses({int? year, int? month, String? chain}) async {
    final list = await cache.getOrLoad<List<MarketingExpenseItem>>(
        _key('expenses', year, month, chain), () => inner.listExpenses(year: year, month: month, chain: chain));
    return List<MarketingExpenseItem>.from(list);
  }

  @override
  Future<List<TradeMarketingSalesBaseline>> getRoi({int? year, int? month, String? chain}) =>
      cache.getOrLoad<List<TradeMarketingSalesBaseline>>(
          _key('roi', year, month, chain), () => inner.getRoi(year: year, month: month, chain: chain));

  @override
  Future<MarketingExpenseItem> saveExpense(MarketingExpenseItem item, {required bool isNew}) async {
    try {
      return await inner.saveExpense(item, isNew: isNew);
    } finally {
      invalidateAll();
    }
  }

  @override
  Future<void> deleteExpense(String id) async {
    try {
      await inner.deleteExpense(id);
    } finally {
      invalidateAll();
    }
  }

  @override
  Future<ExpenseUploadResult> uploadExpenses(List<int> bytes, String filename) async {
    try {
      return await inner.uploadExpenses(bytes, filename);
    } finally {
      invalidateAll();
    }
  }

  // ---- Result helpers ----

  Future<Result<List<MarketingExpenseItem>>> loadExpenses({int? year, int? month, String? chain}) =>
      Result.guard(() => listExpenses(year: year, month: month, chain: chain));

  Future<Result<List<TradeMarketingSalesBaseline>>> loadRoi({int? year, int? month, String? chain}) =>
      Result.guard(() => getRoi(year: year, month: month, chain: chain));
}

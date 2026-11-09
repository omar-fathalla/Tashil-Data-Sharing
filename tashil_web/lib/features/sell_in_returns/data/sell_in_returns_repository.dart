import '../../../core/data/app_cache.dart';
import '../../../core/data/cache_store.dart';
import '../../../core/data/result.dart';
import '../../../core/network/api_client.dart';
import '../domain/sell_in_returns_models.dart';

class SellInReturnsQuery {
  final int? year;
  final int? month;
  final String? chain;
  final String? branch;
  final String? product;
  final String? productGroup;

  const SellInReturnsQuery({
    this.year,
    this.month,
    this.chain,
    this.branch,
    this.product,
    this.productGroup,
  });

  List<Object?> get parts => [year, month, chain, branch, product, productGroup];
}

/// Loads Phase-1 المرتجعات report. Injectable for widget tests.
abstract class SellInReturnsRepository {
  Future<Result<SellInReturnsReport>> load(SellInReturnsQuery q, {bool forceRefresh = false});
}

class ApiSellInReturnsRepository implements SellInReturnsRepository {
  static const feature = 'sell_in_returns';

  final ApiClient api;
  final CacheStore cache;

  ApiSellInReturnsRepository(this.api, {CacheStore? cache})
      : cache = cache ?? AppCache.forApi(api);

  @override
  Future<Result<SellInReturnsReport>> load(SellInReturnsQuery q, {bool forceRefresh = false}) {
    final u = api.currentUser;
    final k = CacheStore.key(api.tenantId, feature, [u?.role, u?.assignedChain, ...q.parts]);
    if (forceRefresh) cache.invalidate(k);
    return Result.guard(() => cache.getOrLoad<SellInReturnsReport>(
          k,
          () => api.getSellInReturns(
            year: q.year,
            month: q.month,
            chain: q.chain,
            branch: q.branch,
            product: q.product,
            productGroup: q.productGroup,
          ),
        ));
  }
}

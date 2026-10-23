import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/data/cache_store.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/store_benchmark/data/store_benchmark_repository.dart';

void main() {
  setUp(AppCache.clear);

  test('repos share one app-level cache by default; injected cache still wins', () {
    final api = ApiClient(tenantId: 'tenant-a', allowMockFallback: false);
    expect(identical(StoreBenchmarkRepository(api).cache, AppCache.shared), isTrue);
    final own = CacheStore();
    expect(identical(StoreBenchmarkRepository(api, cache: own).cache, own), isTrue);
  });

  test('tenant switch clears the shared cache; same session keeps it', () {
    final a = ApiClient(tenantId: 'tenant-a', allowMockFallback: false);
    AppCache.forApi(a).put('tenant-a|x|', 1);
    AppCache.forApi(a);
    expect(AppCache.shared.length, 1);
    AppCache.forApi(ApiClient(tenantId: 'tenant-b', allowMockFallback: false));
    expect(AppCache.shared.length, 0);
  });

  test('clear() (logout) empties the cache', () {
    AppCache.shared.put('k', 1);
    AppCache.clear();
    expect(AppCache.shared.length, 0);
  });
}

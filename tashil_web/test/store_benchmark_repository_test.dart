import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/store_benchmark/data/store_benchmark_repository.dart';

void main() {
  setUp(AppCache.clear);

  MockClient server(List<Uri> log, {bool fail = false}) => MockClient((req) async {
        log.add(req.url);
        if (fail) throw http.ClientException('down');
        return http.Response.bytes(
            utf8.encode(jsonEncode([
              {'store_id': 's1', 'store_name': 'فرع 1', 'retailer_chain': 'fathalla', 'region': 'شرق الإسكندرية', 'tier': 'Tier A', 'total_revenue': 100}
            ])),
            200,
            headers: {'content-type': 'application/json'});
      });

  test('caches per filter combo; forceRefresh refetches', () async {
    final log = <Uri>[];
    await http.runWithClient(() async {
      final repo = StoreBenchmarkRepository(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
      final r1 = await repo.loadMatrix(year: 2026);
      expect(r1.valueOrNull, hasLength(1));
      await repo.loadMatrix(year: 2026);
      expect(log, hasLength(1));
      await repo.loadMatrix(year: 2026, tier: 'Tier A');
      expect(log, hasLength(2));
      expect(log.last.queryParameters['tier'], 'Tier A');
      await repo.loadMatrix(year: 2026, forceRefresh: true);
      expect(log, hasLength(3));
    }, () => server(log));
  });

  test('network failure yields Failure (no stuck spinner)', () async {
    await http.runWithClient(() async {
      final repo = StoreBenchmarkRepository(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
      final r = await repo.loadMatrix(year: 2026);
      expect(r.isFailure, isTrue);
    }, () => server([], fail: true));
  });
}

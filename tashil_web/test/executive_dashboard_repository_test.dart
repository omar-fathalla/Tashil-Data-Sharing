import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/cache_store.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/executive_dashboard/data/executive_dashboard_repository.dart';

void main() {
  MockClient server(List<Uri> log, {bool fail = false}) => MockClient((req) async {
        log.add(req.url);
        if (fail) throw http.ClientException('down');
        return http.Response.bytes(utf8.encode(jsonEncode({'total_revenue': 1234.0})), 200,
            headers: {'content-type': 'application/json'});
      });

  test('short TTL cache per filter; expires; forceRefresh refetches', () async {
    final log = <Uri>[];
    var now = DateTime(2026, 10, 23, 12);
    await http.runWithClient(() async {
      final repo = ExecutiveDashboardRepository(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
          cache: CacheStore(defaultTtl: ExecutiveDashboardRepository.ttl, clock: () => now));
      final r = await repo.loadKpis(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31');
      expect(r.isSuccess, isTrue, reason: '${r.errorOrNull}');
      final n = log.length;
      await repo.loadKpis(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31');
      expect(log.length, n);
      expect(repo.peekFresh(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31'), isNotNull);
      await repo.loadKpis(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31', chain: 'fathalla');
      expect(log.length, greaterThan(n));
      final m = log.length;
      now = now.add(const Duration(seconds: 61));
      expect(repo.peekFresh(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31'), isNull);
      await repo.loadKpis(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31');
      expect(log.length, greaterThan(m));
      final o = log.length;
      await repo.loadKpis(period: 'YTD', startDate: '2026-01-01', endDate: '2026-12-31', forceRefresh: true);
      expect(log.length, greaterThan(o));
    }, () => server(log));
  });

  test('server failure without cache yields Failure', () async {
    await http.runWithClient(() async {
      final repo = ExecutiveDashboardRepository(ApiClient(tenantId: 'tenant-zz-fail', allowMockFallback: false));
      final r = await repo.loadKpis(period: 'MTD', startDate: '2026-03-01', endDate: '2026-03-31');
      expect(r.isFailure, isTrue);
    }, () => server([], fail: true));
  });
}

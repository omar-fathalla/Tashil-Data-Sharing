import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_in_explorer_repository.dart';

void main() {
  MockClient server(List<Uri> log) => MockClient((req) async {
        log.add(req.url);
        return http.Response.bytes(utf8.encode(jsonEncode({'records': [], 'total_count': 0})), 200,
            headers: {'content-type': 'application/json'});
      });

  ApiClient api() => ApiClient(tenantId: 'tenant-zz-empty', allowMockFallback: false);

  test('caches per filter combo; invalidateAll and forceRefresh refetch', () async {
    final log = <Uri>[];
    await http.runWithClient(() async {
      final repo = SellInExplorerRepository(api());
      const q = SellInExplorerQuery(year: 2026);
      final r = await repo.load(q);
      expect(r.isSuccess, isTrue, reason: '${r.errorOrNull}');
      final n = log.length;
      await repo.load(q);
      expect(log.length, n, reason: 'same combo served from cache');
      await repo.load(const SellInExplorerQuery(year: 2026, month: 3));
      expect(log.length, greaterThan(n));
      final m = log.length;
      repo.invalidateAll();
      await repo.load(q);
      expect(log.length, greaterThan(m));
      final o = log.length;
      await repo.load(q, forceRefresh: true);
      expect(log.length, greaterThan(o));
    }, () => server(log));
  });
}

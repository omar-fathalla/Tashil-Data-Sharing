import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';

void main() {
  MockClient server(List<Uri> log, {bool fail = false}) => MockClient((req) async {
        log.add(req.url);
        if (fail) throw http.ClientException('down');
        final body = req.url.path.contains('store') ? <Object>[] : {'records': [], 'total_count': 0};
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });

  ApiClient api() => ApiClient(tenantId: 'tenant-zz-empty', allowMockFallback: false);

  test('caches per filter combo; invalidateAll and forceRefresh refetch', () async {
    final log = <Uri>[];
    await http.runWithClient(() async {
      final repo = SellOutExplorerRepository(api());
      const q = SellOutExplorerQuery(year: 2026, matrixYear: 2026, compYear: 2025);
      final r = await repo.load(q);
      expect(r.isSuccess, isTrue, reason: '${r.errorOrNull}');
      final n = log.length;
      expect(n, greaterThan(0));
      await repo.load(q);
      expect(log.length, n, reason: 'same combo served from cache');
      await repo.load(const SellOutExplorerQuery(year: 2026, month: 3, matrixYear: 2026, compYear: 2025));
      expect(log.length, greaterThan(n), reason: 'different combo');
      final m = log.length;
      repo.invalidateAll();
      await repo.load(q);
      expect(log.length, greaterThan(m));
      final o = log.length;
      await repo.load(q, forceRefresh: true);
      expect(log.length, greaterThan(o));
    }, () => server(log));
  });

  test('network failure yields Failure', () async {
    await http.runWithClient(() async {
      final r = await SellOutExplorerRepository(api())
          .load(const SellOutExplorerQuery(year: 2026, matrixYear: 2026, compYear: 2025));
      expect(r.isFailure, isTrue);
    }, () => server([], fail: true));
  });
}

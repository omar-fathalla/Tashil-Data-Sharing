import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_repository.dart';

void main() {
  MockClient server(List<Uri> log) => MockClient((req) async {
        log.add(req.url);
        final body = req.url.path.contains('chain') ? <Object>[] : {'items': []};
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });

  ApiClient api() => ApiClient(tenantId: 'tenant-zz-empty', allowMockFallback: false);

  test('summary cached per type/chain/year; invalidateAll refetches', () async {
    final log = <Uri>[];
    await http.runWithClient(() async {
      final repo = TargetRepository(api());
      final r = await repo.loadSummary(targetType: 'sell_in', year: 2026);
      expect(r.isSuccess, isTrue, reason: '${r.errorOrNull}');
      final n = log.length;
      await repo.loadSummary(targetType: 'sell_in', year: 2026);
      expect(log.length, n);
      await repo.loadSummary(targetType: 'sell_out', year: 2026);
      expect(log.length, greaterThan(n));
      final m = log.length;
      repo.invalidateAll();
      await repo.loadSummary(targetType: 'sell_in', year: 2026);
      expect(log.length, greaterThan(m));
      final o = log.length;
      await repo.loadSummary(targetType: 'sell_in', year: 2026, forceRefresh: true);
      expect(log.length, greaterThan(o));
    }, () => server(log));
  });

  test('chains are cached', () async {
    final log = <Uri>[];
    await http.runWithClient(() async {
      final repo = TargetRepository(api());
      expect((await repo.loadChains()).isSuccess, isTrue);
      final n = log.length;
      await repo.loadChains();
      expect(log.length, n);
    }, () => server(log));
  });
}

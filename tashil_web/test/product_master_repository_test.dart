import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/product_master/data/product_master_repository.dart';

void main() {
  setUp(AppCache.clear);

  MockClient server(List<Uri> log, {bool fail = false}) => MockClient((req) async {
        log.add(req.url);
        if (fail) throw http.ClientException('down');
        final body = req.url.path.contains('archive') || req.url.path.contains('files')
            ? {'files': []}
            : {'tenant_id': 'tenant-zz-empty', 'total_skus': 0, 'items': []};
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });

  ApiClient api() => ApiClient(tenantId: 'tenant-zz-empty', allowMockFallback: false);

  test('summary cached; invalidateAll / forceRefresh refetch; prime serves server copy', () async {
    final log = <Uri>[];
    await http.runWithClient(() async {
      final repo = ProductMasterRepository(api());
      final r = await repo.loadSummary();
      expect(r.isSuccess, isTrue, reason: '${r.errorOrNull}');
      final n = log.length;
      await repo.loadSummary();
      expect(log.length, n);
      repo.invalidateAll();
      await repo.loadSummary();
      expect(log.length, greaterThan(n));
      final m = log.length;
      await repo.loadSummary(forceRefresh: true);
      expect(log.length, greaterThan(m));
      final primed = r.valueOrNull!;
      repo.prime(primed);
      final o = log.length;
      expect(identical((await repo.loadSummary()).valueOrNull, primed), isTrue);
      expect(log.length, o);
      expect((await repo.loadArchive()).isSuccess, isTrue);
    }, () => server(log));
  });

  test('network failure yields Failure', () async {
    await http.runWithClient(() async {
      final r = await ProductMasterRepository(api()).loadSummary();
      expect(r.isFailure, isTrue);
    }, () => server([], fail: true));
  });
}

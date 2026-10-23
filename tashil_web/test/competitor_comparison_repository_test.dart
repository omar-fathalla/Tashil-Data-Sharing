import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/competitor_comparison/data/competitor_comparison_repository.dart';

void main() {
  const ownBarcode = '6223000239438';

  Future<Result<void>> addSku(CompetitorComparisonRepository repo) => repo.addCustomSku(
        ownBarcode: ownBarcode,
        ownSkuName: 'فيبا 3 كجم',
        ownUnitPrice: 184.67,
        ownVolumeUnits: 3,
        ownVolumeUnitLabel: 'كجم',
        competitorSkuName: 'منافس ميداني 3 كجم',
        competitorBrand: 'Field Brand',
        competitorSupplier: 'Field Co',
        category: 'صابون سائل اطباق',
        packSizeLabel: '3 كجم',
        packVolumeUnits: 3,
        competitorPrice: 150,
        retailerChain: 'fathalla',
      );

  MockClient fakeServer(List<Map<String, dynamic>> store, {bool failWrites = false, List<String>? log}) {
    return MockClient((req) async {
      log?.add('${req.method} ${req.url.path}');
      if (!req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response('{"records":[]}', 200);
      }
      if (failWrites && req.method != 'GET') return _json('{"error":"boom"}', 500);
      switch (req.method) {
        case 'GET':
          return _json(jsonEncode({'custom_skus': store, 'count': store.length}), 200);
        case 'POST':
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final row = {...body, 'id': 'ccsku_1', 'tenant_id': 'adeco'};
          store
            ..removeWhere((r) => r['id'] == 'ccsku_1')
            ..add(row);
          return _json(jsonEncode({'custom_sku': row, 'updated': false}), 201);
        case 'DELETE':
          store.removeWhere((r) => r['id'] == req.url.pathSegments.last);
          return _json(jsonEncode({'deleted': req.url.pathSegments.last}), 200);
      }
      return http.Response('', 405);
    });
  }

  Iterable<CompetitorSkuComparisonModel> customs(List<OwnSkuCompetitiveGroupModel> g) => g
      .where((x) => x.ownBarcode == ownBarcode)
      .expand((x) => x.competitors)
      .where((c) => c.skuName == 'منافس ميداني 3 كجم');

  test('loadGroups caches per key; forceRefresh refetches', () async {
    final log = <String>[];
    await http.runWithClient(() async {
      final repo = CompetitorComparisonRepository(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
      final r1 = await repo.loadGroups(chain: 'fathalla', year: 2026, month: 0);
      expect(r1.isSuccess, isTrue);
      final n = log.length;
      await repo.loadGroups(chain: 'fathalla', year: 2026, month: 0);
      expect(log.length, n, reason: 'served from cache');
      await repo.loadGroups(chain: 'fathalla', year: 2026, month: 0, forceRefresh: true);
      expect(log.length, greaterThan(n));
    }, () => fakeServer([], log: log));
  });

  test('add + delete round-trip returns Success and invalidates cache', () async {
    final store = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      final repo = CompetitorComparisonRepository(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
      await repo.loadGroups(chain: 'fathalla', year: 2026, month: 0);
      expect((await addSku(repo)).isSuccess, isTrue);
      expect(store, hasLength(1));
      final groups = (await repo.loadGroups(chain: 'fathalla', year: 2026, month: 0)).valueOrNull!;
      final found = customs(groups).toList();
      expect(found, hasLength(1));
      expect(repo.isCustomSku(found.first.barcode), isTrue);
      expect((await repo.deleteCustomSku(found.first.barcode)).isSuccess, isTrue);
      expect(store, isEmpty);
      final after = (await repo.loadGroups(chain: 'fathalla', year: 2026, month: 0)).valueOrNull!;
      expect(customs(after), isEmpty);
    }, () => fakeServer(store));
  });

  test('failed save yields Failure and rolls back local SKU', () async {
    await http.runWithClient(() async {
      final repo = CompetitorComparisonRepository(ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false));
      final res = await addSku(repo);
      expect(res.isFailure, isTrue);
      final groups = (await repo.rebuildLocal(chain: 'fathalla', year: 2026, month: 0)).valueOrNull!;
      expect(customs(groups), isEmpty);
    }, () => fakeServer([], failWrites: true));
  });
}

http.Response _json(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

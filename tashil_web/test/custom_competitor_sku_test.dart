import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  const ownBarcode = '6223000239438';

  Future<void> addPril(ApiClient api) => api.addCustomCompetitorSku(
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

  /// Fake backend storing custom SKUs in memory, like the Go endpoints.
  /// Sell-out records include one live own-SKU row so production path never falls back to seeds.
  MockClient fakeServer(List<Map<String, dynamic>> store, {bool failWrites = false}) {
    return MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/records')) {
        return _json(
          jsonEncode({
            'records': [
              {
                'record_id': 'live-own-1',
                'retailer_chain': 'fathalla',
                'store_id': 's1',
                'store_name': 'فرع',
                'barcode': ownBarcode,
                'sku_name': 'فيبا 3 كجم',
                'category': 'صابون سائل اطباق',
                'quantity_sold': 10,
                'net_revenue': 1600.0,
                'unit_price': 160.0,
                'transaction_date': '2026-05-15',
              },
            ],
            'total_count': 1,
          }),
          200,
        );
      }
      if (!req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response('{"records":[]}', 200);
      }
      if (failWrites && req.method != 'GET') {
        return _json('{"error":"boom"}', 500);
      }
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
          final id = req.url.pathSegments.last;
          store.removeWhere((r) => r['id'] == id);
          return _json(jsonEncode({'deleted': id}), 200);
      }
      return http.Response('', 405);
    });
  }

  Iterable<CompetitorSkuComparisonModel> customs(List<OwnSkuCompetitiveGroupModel> groups) => groups
      .where((g) => g.ownBarcode == ownBarcode)
      .expand((g) => g.competitors)
      .where((c) => c.skuName == 'منافس ميداني 3 كجم');

  test('custom competitor SKU is POSTed and survives a fresh client (reload)', () async {
    final store = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await addPril(api);
      expect(store, hasLength(1));
      expect(store.first['retailer_chain'], 'fathalla');

      final reloaded = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final groups = await reloaded.getCompetitiveComparisonGroups(chain: 'fathalla');
      final found = customs(groups).toList();
      expect(found, hasLength(1));
      expect(reloaded.isCustomCompetitorSku(found.first.barcode), isTrue);

      await reloaded.deleteCustomCompetitorSku(found.first.barcode);
      expect(store, isEmpty);
      final after = await ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false)
          .getCompetitiveComparisonGroups(chain: 'fathalla');
      expect(customs(after), isEmpty);
    }, () => fakeServer(store));
  });

  test('failed save rolls back the in-memory SKU and rethrows', () async {
    final store = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(addPril(api), throwsA(isA<Exception>()));
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla', syncCustomSkus: false);
      expect(customs(groups), isEmpty);
    }, () => fakeServer(store, failWrites: true));
  });

  test('custom competitor with no history → empty monthlyPrices; current price kept', () async {
    final store = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await addPril(api);
      final groups = await api.getCompetitiveComparisonGroups(chain: 'fathalla');
      final found = customs(groups).single;
      expect(found.unitPrice, 150);
      expect(found.monthlyPrices, isEmpty);
      expect(found.allMonthlyPrices, isEmpty);
      // Own live May only — Jan–Apr must not appear on own or custom series.
      final own = groups.firstWhere((g) => g.ownBarcode == ownBarcode);
      expect(own.monthlyPrices.map((p) => p.monthNum).toSet(), {5});
      expect(own.monthlyPrices.any((p) => p.monthNum <= 4), isFalse);
      expect(found.monthlyPrices.any((p) => p.monthNum <= 4), isFalse);
    }, () => fakeServer(store));
  });
}

http.Response _json(String body, int status) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

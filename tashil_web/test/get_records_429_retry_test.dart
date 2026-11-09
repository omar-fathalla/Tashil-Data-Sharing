import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  test('getRecords retries on HTTP 429 then succeeds', () async {
    var calls = 0;
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final list = await api.getRecords(category: 'صابون سائل اطباق', year: 2026, month: 1);
      expect(calls, greaterThanOrEqualTo(2));
      expect(list, isNotEmpty);
      expect(api.lastSellOutSummary?.totalCount, 28);
      expect(api.lastSellOutSummary?.totalCartonsSold, 688.7);
      expect(api.lastSellOutSummary?.totalFactoryCost, 595500);
      expect(api.lastSellOutSummary?.totalRetailerGrossProfit, -274639);
    }, () => MockClient((req) async {
          calls++;
          if (calls == 1) {
            return http.Response('{"error":"rate limited"}', 429, headers: {'retry-after': '0'});
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'records': [
                {
                  'record_id': 'r1',
                  'retailer_chain': 'fathalla',
                  'store_id': 's1',
                  'store_name': 'فرع',
                  'barcode': '1',
                  'sku_name': 'Rahab',
                  'category': 'صابون سائل اطباق',
                  'quantity_sold': 1,
                  'net_revenue': 10,
                  'unit_price': 10,
                  'transaction_date': '2026-01-10',
                }
              ],
              'total_count': 28,
              'total_cartons_sold': 688.7,
              'total_factory_cost': 595500,
              'total_retailer_gross_profit': -274639,
            })),
            200,
            headers: {'content-type': 'application/json'},
          );
        }));
  });

  test('getRecords clears lastSellOutSummary on terminal failure', () async {
    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      api.lastSellOutSummary = const SellOutRecordsSummaryModel(totalCount: 99, totalFactoryCost: 1);
      try {
        await api.getRecords(year: 2026, month: 1);
        fail('expected throw');
      } on ServerConnectionException {
        expect(api.lastSellOutSummary?.totalCount, 0);
        expect(api.lastSellOutSummary?.totalFactoryCost, 0);
      }
    }, () => MockClient((_) async => http.Response('nope', 500)));
  });
}

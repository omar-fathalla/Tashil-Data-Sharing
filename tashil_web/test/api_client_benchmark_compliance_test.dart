import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  group('ApiClient Store Benchmark & Pricing Compliance Unit Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient();
    });

    test('StoreBenchmarkItem JSON serialization and deserialization', () {
      final json = {
        'store_id': 'crf_cairo_maadi',
        'store_name': 'كارفور المعادي سيتي سنتر',
        'retailer_chain': 'carrefour',
        'region': 'القاهرة الكبرى',
        'tier': 'Tier A',
        'total_revenue': 852400.0,
        'total_units': 7210,
        'velocity_units_per_day': 240.3,
        'rank': 1,
      };

      final item = StoreBenchmarkItem.fromJson(json);
      expect(item.storeId, 'crf_cairo_maadi');
      expect(item.storeName, 'كارفور المعادي سيتي سنتر');
      expect(item.retailerChain, 'carrefour');
      expect(item.region, 'القاهرة الكبرى');
      expect(item.tier, 'Tier A');
      expect(item.totalRevenue, 852400.0);
      expect(item.totalUnits, 7210);
      expect(item.velocityUnitsPerDay, 240.3);
      expect(item.rank, 1);

      final exported = item.toJson();
      expect(exported['store_id'], 'crf_cairo_maadi');
      expect(exported['tier'], 'Tier A');
      expect(exported['total_revenue'], 852400.0);
    });

    test('PricingComplianceItem JSON serialization and deserialization', () {
      final json = {
        'sku_name': 'Adeco Pure Sunflower Oil 1L',
        'barcode': '6221155001241',
        'category': 'زيوت طعام',
        'retailer_chain': 'carrefour',
        'store_name': 'كارفور المعادي سيتي سنتر',
        'actual_price': 98.0,
        'recommended_price': 110.0,
        'price_delta_pct': -10.9,
        'violation_type': 'under_cutting',
        'is_promo_active': true,
        'promo_uplift_pct': 34.5,
      };

      final item = PricingComplianceItem.fromJson(json);
      expect(item.skuName, 'Adeco Pure Sunflower Oil 1L');
      expect(item.barcode, '6221155001241');
      expect(item.category, 'زيوت طعام');
      expect(item.retailerChain, 'carrefour');
      expect(item.actualPrice, 98.0);
      expect(item.recommendedPrice, 110.0);
      expect(item.priceDeltaPct, -10.9);
      expect(item.violationType, 'under_cutting');
      expect(item.isPromoActive, true);
      expect(item.promoUpliftPct, 34.5);

      final exported = item.toJson();
      expect(exported['violation_type'], 'under_cutting');
      expect(exported['is_promo_active'], true);
    });

    test('getStoreBenchmarkMatrix returns full dataset without filters', () async {
      final stores = await apiClient.getStoreBenchmarkMatrix();
      expect(stores.isNotEmpty, true);
      expect(stores.length, greaterThanOrEqualTo(8));

      // Verify Tier A, B, and C exist
      expect(stores.any((s) => s.tier == 'Tier A'), true);
      expect(stores.any((s) => s.tier == 'Tier B'), true);
      expect(stores.any((s) => s.tier == 'Tier C'), true);

      // Verify rankings are sorted descending by revenue
      for (int i = 0; i < stores.length; i++) {
        expect(stores[i].rank, i + 1);
        if (i > 0) {
          expect(stores[i].totalRevenue, lessThanOrEqualTo(stores[i - 1].totalRevenue));
        }
      }
    });

    test('getStoreBenchmarkMatrix filters by region and tier', () async {
      // Filter region: شرق الإسكندرية
      final eastAlex = await apiClient.getStoreBenchmarkMatrix(region: 'شرق الإسكندرية');
      expect(eastAlex.isNotEmpty, true);
      for (final s in eastAlex) {
        expect(s.region, 'شرق الإسكندرية');
      }

      // Filter tier: Tier A
      final tierA = await apiClient.getStoreBenchmarkMatrix(tier: 'Tier A');
      expect(tierA.isNotEmpty, true);
      for (final s in tierA) {
        expect(s.tier, 'Tier A');
      }
    });

    test('getPricingCompliance returns diverse items and filters correctly', () async {
      Map<String, dynamic> row(String sku, String chain, String type, bool promo, double uplift) => {
            'sku_name': sku,
            'barcode': '622115500${sku.length}',
            'category': 'زيوت طعام',
            'retailer_chain': chain,
            'store_name': '$chain store',
            'actual_price': 100.0,
            'recommended_price': 100.0,
            'price_delta_pct': 0.0,
            'violation_type': type,
            'is_promo_active': promo,
            'promo_uplift_pct': uplift,
          };
      final serverRows = [
        row('Adeco Oil 1L', 'carrefour', 'under_cutting', true, 34.5),
        row('Adeco Ghee 1kg', 'carrefour', 'compliant', false, 0),
        row('Adeco Oil 2L', 'spinneys', 'price_gouging', false, 0),
        row('Adeco Corn Oil 1L', 'fathalla', 'compliant', false, 0),
      ];
      final server = MockClient((req) async {
        if (req.url.path.endsWith('/api/v1/analytics/pricing-compliance')) {
          return http.Response(jsonEncode(serverRows), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        throw http.ClientException('down');
      });

      await http.runWithClient(() async {
        final allItems = await apiClient.getPricingCompliance();
        expect(allItems.isNotEmpty, true);

        // Check violation types presence
        expect(allItems.any((i) => i.violationType == 'compliant'), true);
        expect(allItems.any((i) => i.violationType == 'under_cutting'), true);
        expect(allItems.any((i) => i.violationType == 'price_gouging'), true);

        // Check active promo presence with uplift
        final promoItems = allItems.where((i) => i.isPromoActive).toList();
        expect(promoItems.isNotEmpty, true);
        expect(promoItems.any((i) => i.promoUpliftPct > 0), true);

        // Filter by violationOnly: true
        final violations = await apiClient.getPricingCompliance(violationOnly: true);
        expect(violations.isNotEmpty, true);
        for (final v in violations) {
          expect(v.violationType, isNot('compliant'));
        }

        // Filter by chain: carrefour
        final carrefourItems = await apiClient.getPricingCompliance(chain: 'carrefour');
        expect(carrefourItems.isNotEmpty, true);
        for (final c in carrefourItems) {
          expect(c.retailerChain, 'carrefour');
        }
      }, () => server);
    });
  });
}

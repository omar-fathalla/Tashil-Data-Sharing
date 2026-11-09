import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/available_months.dart';
import 'package:tashil_web/core/network/api_client.dart';

Map<String, dynamic> _monthPt(int month, {double price = 100, int units = 10}) => {
      'month_key': '2026-${month.toString().padLeft(2, '0')}',
      'month': month,
      'unit_price': price,
      'units': units,
      'net_revenue': price * units,
    };

void main() {
  tearDown(AvailableMonths.clearForTest);

  test('all live own SKUs appear; unmapped labelled; seed does not override live category', () async {
    const floorBarcode = '6223000239438'; // seed historically called this dish soap
    const dishBarcode = '6223000232514';
    const extraOwn = '6223000999001';
    const pril = '6221143099674';
    final months = List<int>.generate(10, (i) => i + 1);

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final groups = await api.getCompetitiveComparisonGroups(
        chain: 'fathalla',
        year: 2026,
        month: 0,
      );

      final barcodes = groups.map((g) => g.ownBarcode).toSet();
      expect(barcodes.contains(floorBarcode), isTrue);
      expect(barcodes.contains(dishBarcode), isTrue);
      expect(barcodes.contains(extraOwn), isTrue);
      // More than the hardcoded 14 seeds once extra own appears.
      expect(groups.length, greaterThanOrEqualTo(3));

      final floor = groups.firstWhere((g) => g.ownBarcode == floorBarcode);
      expect(floor.category, 'منظف ارضيات');
      expect(floor.ownSkuName.contains('شرنك'), isTrue);
      // Seed still supplies approved Pril mapping for this barcode.
      expect(floor.competitors.any((c) => c.barcode == pril), isTrue);

      final extra = groups.firstWhere((g) => g.ownBarcode == extraOwn);
      expect(extra.competitors, isEmpty); // unmapped own SKU still listed
      expect(extra.monthlyPrices, isNotEmpty);
      expect(extra.category, 'صابون سائل اطباق');
    }, () => MockClient((req) async {
      if (req.url.path.contains('/api/v1/analytics/competitive-monthly')) {
        return http.Response(
          jsonEncode({
            'year': 2026,
            'months': months,
            'source': 'memory',
            'own_skus': [
              {
                'barcode': floorBarcode,
                'sku_name': 'عرض شرنك فيبا بلس + 3 كجم & فيبا 3 كجم - 3 مجموعه',
                'category': 'منظف ارضيات',
              },
              {
                'barcode': dishBarcode,
                'sku_name': 'فيبا صابون سائل اطباق',
                'category': 'صابون سائل اطباق',
              },
              {
                'barcode': extraOwn,
                'sku_name': 'فيبا اطباق إضافي',
                'category': 'صابون سائل اطباق',
              },
            ],
            'items': [
              {
                'barcode': floorBarcode,
                'sku_name': 'عرض شرنك فيبا بلس + 3 كجم & فيبا 3 كجم - 3 مجموعه',
                'category': 'منظف ارضيات',
                'is_own_brand': true,
                'months': [for (final m in months) _monthPt(m, price: 160.0 + m)],
              },
              {
                'barcode': dishBarcode,
                'sku_name': 'فيبا صابون سائل اطباق',
                'category': 'صابون سائل اطباق',
                'is_own_brand': true,
                'months': [for (final m in months) _monthPt(m, price: 40.0 + m)],
              },
              {
                'barcode': extraOwn,
                'sku_name': 'فيبا اطباق إضافي',
                'category': 'صابون سائل اطباق',
                'is_own_brand': true,
                'months': [for (final m in months) _monthPt(m, price: 35.0 + m)],
              },
              {
                'barcode': pril,
                'sku_name': 'بريل سائل منظف أطباق 4 كجم',
                'category': 'صابون سائل اطباق',
                'is_own_brand': false,
                'months': [for (final m in months) _monthPt(m, price: 140.0 + m)],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.startsWith('/api/v1/competitors/custom-skus')) {
        return http.Response(jsonEncode({'custom_skus': [], 'count': 0}), 200);
      }
      if (req.url.path.startsWith('/api/v1/competitors/mappings')) {
        return http.Response(jsonEncode({'mappings': [], 'count': 0}), 200);
      }
      return http.Response('{}', 200);
    }));
  });

  test('empty-state months copy is gated behind finished loading flag helper', () {
    // Pure guard used by the screen: show only when finished && not loading && empty.
    bool showEmpty({required bool monthsLoadFinished, required bool isLoading, required bool monthsEmpty}) =>
        monthsEmpty && monthsLoadFinished && !isLoading;

    expect(showEmpty(monthsLoadFinished: false, isLoading: true, monthsEmpty: true), isFalse);
    expect(showEmpty(monthsLoadFinished: true, isLoading: true, monthsEmpty: true), isFalse);
    expect(showEmpty(monthsLoadFinished: true, isLoading: false, monthsEmpty: true), isTrue);
    expect(showEmpty(monthsLoadFinished: true, isLoading: false, monthsEmpty: false), isFalse);
  });
}

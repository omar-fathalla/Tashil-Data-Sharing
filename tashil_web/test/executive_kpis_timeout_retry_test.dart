import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';
import 'package:tashil_web/core/network/api_endpoints.dart';

void main() {
  tearDown(() {
    ApiClient.executiveKpisTimeout = const Duration(seconds: 45);
    BackendHttp.cache.clear();
    ApiClient.invalidateExecutiveKpisCache();
  });

  Map<String, dynamic> kpiJson() => {
        'total_revenue': 100.0,
        'revenue_growth_pct': 1.0,
        'total_units_sold': 10,
        'units_growth_pct': 1.0,
        'active_stores_count': 1,
        'oos_rate_pct': 0.0,
        'total_oos_incidents': 0,
        'estimated_lost_revenue': 0.0,
        'currency': 'EGP',
        'reporting_period': 'YTD',
        'chain_shares': <dynamic>[],
        'daily_trends': <dynamic>[],
      };

  test('getExecutiveKPIs uses ~45s timeout by default', () {
    expect(ApiClient.executiveKpisTimeout, const Duration(seconds: 45));
  });

  test('getExecutiveKPIs retries once on TimeoutException then succeeds', () async {
    var calls = 0;
    final server = MockClient((req) async {
      expect(req.url.path, contains('/api/v1/analytics/executive-summary'));
      calls++;
      // Throw TimeoutException (same type Future.timeout uses) so the retry
      // path runs without racing HttpSwrCache in-flight coalescing.
      if (calls == 1) {
        throw TimeoutException('executive-summary cold start');
      }
      return http.Response(
        jsonEncode(kpiJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final kpis = await api.getExecutiveKPIs(period: 'YTD');
      expect(kpis.totalRevenue, 100.0);
      expect(kpis.reportingPeriod, 'YTD');
      expect(calls, 2);
    }, () => server);
  });

  test('getExecutiveKPIs surfaces error after timeout + failed retry', () async {
    var calls = 0;
    final server = MockClient((req) async {
      calls++;
      throw TimeoutException('still cold');
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(
        api.getExecutiveKPIs(period: 'YTD'),
        throwsA(isA<ServerConnectionException>()),
      );
      expect(calls, 2);
    }, () => server);
  });

  test('executive summary endpoint path is stable', () {
    expect(ApiEndpoints.executiveSummary, contains('/api/v1/analytics/executive-summary'));
  });
}

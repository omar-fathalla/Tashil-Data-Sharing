import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';

void main() {
  tearDown(() {
    BackendHttp.cache.clear();
  });

  test('suggestCompetitorsForSku POST does not bump dataRevision (breaks Compare hang loop)',
      () async {
    var posts = 0;
    MockClient fake() => MockClient((req) async {
          if (req.method == 'POST' &&
              req.url.path.contains('/competitors/suggestions/sku')) {
            posts++;
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'suggestions': [],
                'cached': true,
                'include_in_kpi_averages': false,
              })),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"error":"unhandled"}', 500);
        });

    await http.runWithClient(() async {
      final before = BackendHttp.dataRevision.value;
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await api.suggestCompetitorsForSku(
        barcode: 'OWN1',
        chain: 'fathalla',
        year: 2026,
      );
      expect(posts, 1);
      expect(
        BackendHttp.dataRevision.value,
        before,
        reason: 'AI picks read-like POST must not invalidate SWR / bump revision',
      );
      expect(ApiClient.includeAiSuggestionsInKpiAverages, isFalse);
    }, fake);
  });

  test('mutating approve POST still bumps dataRevision', () async {
    MockClient fake() => MockClient((req) async {
          if (req.method == 'POST' &&
              req.url.path.contains('/competitors/suggestions/approve')) {
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'suggestion': {'id': 'csug_1', 'status': 'approved'},
                'mapping': {'id': 'cmap_1'},
              })),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"error":"unhandled"}', 500);
        });

    await http.runWithClient(() async {
      final before = BackendHttp.dataRevision.value;
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await api.approveCompetitorSuggestion('csug_1');
      expect(BackendHttp.dataRevision.value, greaterThan(before));
    }, fake);
  });

  test('competitive-monthly timeout surfaces Arabic error', () async {
    MockClient hang() => MockClient((req) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return http.Response('{}', 200);
        });

    final prev = ApiClient.competitiveMonthlyTimeout;
    final prevDelay = ApiClient.connectionRetryDelay;
    final prevAttempts = ApiClient.competitiveMonthlyMaxAttempts;
    ApiClient.competitiveMonthlyTimeout = const Duration(milliseconds: 40);
    ApiClient.connectionRetryDelay = Duration.zero;
    ApiClient.competitiveMonthlyMaxAttempts = 2;
    addTearDown(() {
      ApiClient.competitiveMonthlyTimeout = prev;
      ApiClient.connectionRetryDelay = prevDelay;
      ApiClient.competitiveMonthlyMaxAttempts = prevAttempts;
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      Object? err;
      try {
        await api.getCompetitiveMonthly(chain: 'fathalla', year: 2026);
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(err.toString(), contains('انتهت مهلة تحميل بيانات مقارنة الأسعار'));
    }, hang);
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';

void main() {
  setUp(() {
    ApiClient.suggestionsRunMaxAttempts = 3;
    ApiClient.competitiveMonthlyMaxAttempts = 3;
    ApiClient.connectionRetryDelay = Duration.zero;
    BackendHttp.cache.clear();
  });

  tearDown(() {
    ApiClient.suggestionsRunMaxAttempts = 3;
    ApiClient.competitiveMonthlyMaxAttempts = 3;
    ApiClient.connectionRetryDelay = const Duration(seconds: 1);
    BackendHttp.cache.clear();
  });

  test('isTransientConnectionFailure detects ERR_CONNECTION_CLOSED', () {
    expect(
      ApiClient.isTransientConnectionFailure(
        http.ClientException('net::ERR_CONNECTION_CLOSED'),
      ),
      isTrue,
    );
    expect(
      ApiClient.isTransientConnectionFailure(
        Exception('ClientException: Failed to fetch'),
      ),
      isTrue,
    );
    expect(
      ApiClient.isTransientConnectionFailure(TimeoutException('slow')),
      isTrue,
    );
    expect(
      ApiClient.isTransientConnectionFailure(Exception('فشل تشغيل الاقتراحات (502)')),
      isFalse,
    );
  });

  test('runCompetitorSuggestions retries ERR_CONNECTION_CLOSED then succeeds',
      () async {
    var calls = 0;
    final server = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, contains('/competitors/suggestions/run'));
      calls++;
      if (calls < 3) {
        throw http.ClientException('net::ERR_CONNECTION_CLOSED');
      }
      return http.Response(
        jsonEncode({
          'created_count': 1,
          'processed_own': 1,
          'remaining_uncovered': 0,
          'suggestions': <dynamic>[],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final out = await api.runCompetitorSuggestions(
        chain: 'fathalla',
        limit: 10,
        year: 2026,
      );
      expect(out['created_count'], 1);
      expect(calls, 3);
    }, () => server);
  });

  test('runCompetitorSuggestions throws connection exception after max attempts',
      () async {
    var calls = 0;
    final server = MockClient((req) async {
      calls++;
      throw http.ClientException('net::ERR_CONNECTION_CLOSED');
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(
        api.runCompetitorSuggestions(chain: 'fathalla', year: 2026),
        throwsA(isA<CompetitorSuggestConnectionException>()),
      );
      expect(calls, 3);
    }, () => server);
  });

  test('runCompetitorSuggestions still surfaces 429 without connection retries',
      () async {
    var calls = 0;
    final server = MockClient((req) async {
      calls++;
      return http.Response(
        jsonEncode({'error': 'rate limit: wait before re-running'}),
        429,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(
        api.runCompetitorSuggestions(chain: 'fathalla', year: 2026),
        throwsA(isA<CompetitorSuggestRateLimitException>()),
      );
      expect(calls, 1);
    }, () => server);
  });

  test('getCompetitiveMonthly retries connection closed then succeeds', () async {
    var calls = 0;
    final server = MockClient((req) async {
      expect(req.url.path, contains('/analytics/competitive-monthly'));
      calls++;
      if (calls == 1) {
        throw http.ClientException('net::ERR_CONNECTION_CLOSED');
      }
      return http.Response(
        jsonEncode({
          'months': [1, 2],
          'items': <dynamic>[],
          'own_skus': <dynamic>[],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      final agg = await api.getCompetitiveMonthly(chain: 'fathalla', year: 2026);
      expect(agg.months, [1, 2]);
      expect(calls, 2);
    }, () => server);
  });

  test('getCompetitiveMonthly Arabic error after exhausted connection retries',
      () async {
    var calls = 0;
    final server = MockClient((req) async {
      calls++;
      throw http.ClientException('net::ERR_CONNECTION_CLOSED');
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(
        api.getCompetitiveMonthly(chain: 'fathalla', year: 2026),
        throwsA(
          predicate<Object>(
            (e) => e
                .toString()
                .contains('انقطع الاتصال أثناء تحميل بيانات مقارنة الأسعار'),
          ),
        ),
      );
      expect(calls, 3);
    }, () => server);
  });
}

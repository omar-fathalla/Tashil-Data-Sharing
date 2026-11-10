import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';

void main() {
  tearDown(() {
    ApiClient.productMasterTimeout = const Duration(seconds: 45);
    BackendHttp.cache.clear();
  });

  test('getProductMaster default timeout is 45s (not the old 10s hang ceiling)', () {
    expect(ApiClient.productMasterTimeout, const Duration(seconds: 45));
  });

  test('getProductMaster throws Arabic ServerConnectionException on timeout', () async {
    ApiClient.productMasterTimeout = const Duration(milliseconds: 40);
    final server = MockClient((req) async {
      throw TimeoutException('product-master pull-stats hang');
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(
        api.getProductMaster(),
        throwsA(
          isA<ServerConnectionException>().having(
            (e) => e.message,
            'message',
            contains('تعذّر تحميل كارتة الأصناف والأسعار'),
          ),
        ),
      );
    }, () => server);
  });

  test('getProductMaster throws Arabic error on non-200 (no silent mock)', () async {
    final server = MockClient((req) async {
      return http.Response(
        jsonEncode({'status': 'loading', 'error': 'Data is still loading'}),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await http.runWithClient(() async {
      final api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
      await expectLater(
        api.getProductMaster(),
        throwsA(isA<ServerConnectionException>()),
      );
    }, () => server);
  });
}

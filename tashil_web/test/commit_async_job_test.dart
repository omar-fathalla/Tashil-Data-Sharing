import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';

/// Large Sell-Out commits (out26 ≈ 80k rows) must use 202 + job poll — never a
/// long sync POST that hits Cloud Run / WriteTimeout with a false 503.
void main() {
  tearDown(BackendHttp.cache.clear);

  test('commitStagedUpload sends async header and follows 202 to terminal success',
      () async {
    var sawAsyncHeader = false;
    var polls = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/api/v1/ingest/commit')) {
        expect(req.headers[BackendHttp.asyncJobHeader], '1');
        sawAsyncHeader = true;
        return http.Response(
          jsonEncode({'job_id': 'job_commit_out26', 'status': 'running'}),
          202,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: http.Request('POST', req.url),
        );
      }
      if (req.method == 'GET' && req.url.path.contains('/api/v1/jobs/')) {
        polls++;
        if (polls < 3) {
          return http.Response(
            jsonEncode({'job_id': 'job_commit_out26', 'status': 'running'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'job_id': 'job_commit_out26',
            'status': 'done',
            'http_status': 200,
            'body': {
              'batch_id': 'batch_out26',
              'filename': 'out26.xlsx',
              'valid_rows': 81294,
              'total_rows': 81294,
              'total_revenue': 1.0,
              'is_committed': true,
              'is_staged': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('unexpected ${req.method} ${req.url}', 500);
    });

    await http.runWithClient(() async {
      final api = ApiClient(
        tenantId: 'tenant-adeco',
        authToken: 'tok',
        allowMockFallback: false,
      );
      final result = await api.commitStagedUpload(
        batchId: 'batch_out26',
        targetChain: 'fathalla',
      );
      expect(result.validRows, 81294);
      expect(result.isCommitted, isTrue);
      expect(result.batchId, 'batch_out26');
    }, () => client);

    expect(sawAsyncHeader, isTrue);
    expect(polls, greaterThanOrEqualTo(3));
  });

  test('commitStagedUpload maps HTTP 429 to UploadRateLimitedException', () async {
    final client = MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/api/v1/ingest/commit')) {
        return http.Response(
          jsonEncode({
            'error': 'rate_limited',
            'message': uploadRateLimitMessage,
          }),
          429,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'retry-after': '15',
            'access-control-allow-origin': '*',
          },
          request: http.Request('POST', req.url),
        );
      }
      return http.Response('unexpected', 500);
    });

    await http.runWithClient(() async {
      final api = ApiClient(
        tenantId: 'tenant-adeco',
        authToken: 'tok',
        allowMockFallback: false,
      );
      expect(
        () => api.commitStagedUpload(batchId: 'batch_x', targetChain: 'fathalla'),
        throwsA(isA<UploadRateLimitedException>()),
      );
    }, () => client);
  });
}

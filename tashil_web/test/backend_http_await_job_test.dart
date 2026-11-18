import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/sell_in_upload_target.dart';

/// Advances [now] by [d] with no wall-clock wait — keeps awaitJob tests load-proof.
Future<void> Function(Duration) _advance(DateTime Function() read, void Function(DateTime) write) {
  return (Duration d) async {
    write(read().add(d));
  };
}

/// Long Sell-In jobs (in26 ≈ 5–6 min) must keep polling past the old 5-minute UI ceiling.
void main() {
  tearDown(BackendHttp.cache.clear);

  test('UI timeout ceiling matches awaitJob and is far past five minutes', () {
    expect(BackendHttp.defaultJobMaxWait, const Duration(minutes: 45));
    expect(sellInUploadTimeout, BackendHttp.defaultJobMaxWait);
    expect(sellInUploadTimeout, greaterThan(const Duration(minutes: 5)));
  });

  test('awaitJob keeps polling a long-running job until a terminal success', () async {
    var polls = 0;
    // Many "running" polls model a job that outlasts the old 5-minute client abort.
    const runningPolls = 8;
    final client = MockClient((req) async {
      expect(req.url.path, '/api/v1/jobs/job-long');
      polls++;
      if (polls < runningPolls) {
        return http.Response(
          jsonEncode({'job_id': 'job-long', 'status': 'running'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'job_id': 'job-long',
          'status': 'done',
          'http_status': 200,
          'body': {
            'batch_id': 'b1',
            'filename': 'in26.xlsx',
            'valid_rows': 40927,
            'total_rows': 40927,
            'total_revenue': 1.0,
            'is_committed': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    var now = DateTime.utc(2024, 1, 1);
    await http.runWithClient(() async {
      final accepted = http.Response(
        jsonEncode({'job_id': 'job-long', 'status': 'running'}),
        202,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: http.Request(
            'POST', Uri.parse('https://api.example/api/v1/ingest/load-sell-in-plan')),
      );
      final done = await BackendHttp.awaitJob(
        accepted,
        pollEvery: const Duration(milliseconds: 20),
        maxWait: const Duration(seconds: 5),
        clock: () => now,
        delay: _advance(() => now, (v) => now = v),
      );
      expect(done.statusCode, 200);
      final body = jsonDecode(done.body) as Map<String, dynamic>;
      expect(body['valid_rows'], 40927);
      expect(body['filename'], 'in26.xlsx');
    }, () => client);

    expect(polls, runningPolls);
  });

  test('awaitJob returns still_processing 504 only after its ceiling — never mid-run as rejection',
      () async {
    var polls = 0;
    final client = MockClient((req) async {
      polls++;
      return http.Response(
        jsonEncode({'job_id': 'job-slow', 'status': 'running'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    // Virtual clock: maxWait / pollEvery = 120ms / 30ms → exactly 4 polls, then 504.
    // No wall-clock dependence (was flaky under Mac CI load: Expected >1 Actual: <1>).
    const pollEvery = Duration(milliseconds: 30);
    const maxWait = Duration(milliseconds: 120);
    const expectedPolls = 4; // floor(maxWait / pollEvery) while advancing after each sleep
    var now = DateTime.utc(2024, 6, 1, 12);

    await http.runWithClient(() async {
      final accepted = http.Response(
        jsonEncode({'job_id': 'job-slow', 'status': 'running'}),
        202,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: http.Request(
            'POST', Uri.parse('https://api.example/api/v1/ingest/load-sell-in-plan')),
      );
      final timedOut = await BackendHttp.awaitJob(
        accepted,
        pollEvery: pollEvery,
        maxWait: maxWait,
        clock: () => now,
        delay: _advance(() => now, (v) => now = v),
      );
      expect(timedOut.statusCode, 504);
      final body = jsonDecode(timedOut.body) as Map<String, dynamic>;
      expect(body['still_processing'], isTrue);
      expect(body['message'], contains('لسه بيتعالج'));
      expect(body['message'], isNot(contains('مفيش حاجة اتحفظت')));
      // Same mapping uploadSellInFile applies for job-wait 504:
      expect(
        () {
          if (timedOut.statusCode == 504) throw UploadStillProcessingException();
        },
        throwsA(isA<UploadStillProcessingException>()),
      );
      expect(isUploadWaitTimeout(UploadStillProcessingException()), isTrue);
      expect(uploadFailureMessage(UploadStillProcessingException()),
          isNot(contains('مفيش حاجة اتحفظت')));
    }, () => client);

    expect(polls, expectedPolls);
    expect(now, DateTime.utc(2024, 6, 1, 12).add(maxWait));
  });

  test('awaitJob does not emit 504 before the ceiling when the job is still running', () async {
    var polls = 0;
    final client = MockClient((req) async {
      polls++;
      if (polls < 3) {
        return http.Response(
          jsonEncode({'job_id': 'job-mid', 'status': 'running'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'job_id': 'job-mid',
          'status': 'done',
          'http_status': 200,
          'body': {'ok': true},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    var now = DateTime.utc(2024, 6, 1, 12);
    await http.runWithClient(() async {
      final accepted = http.Response(
        jsonEncode({'job_id': 'job-mid', 'status': 'running'}),
        202,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: http.Request(
            'POST', Uri.parse('https://api.example/api/v1/ingest/load-sell-in-plan')),
      );
      final done = await BackendHttp.awaitJob(
        accepted,
        pollEvery: const Duration(milliseconds: 50),
        maxWait: const Duration(milliseconds: 500),
        clock: () => now,
        delay: _advance(() => now, (v) => now = v),
      );
      expect(done.statusCode, 200);
      expect(jsonDecode(done.body)['ok'], isTrue);
    }, () => client);

    expect(polls, 3);
    // Only three poll intervals elapsed — well under the 500ms ceiling.
    expect(now, DateTime.utc(2024, 6, 1, 12).add(const Duration(milliseconds: 150)));
  });

  test('uploadSellInFile follows a long job to terminal success (not a false failure)', () async {
    var polls = 0;
    const runningBeforeDone = 3;
    final client = MockClient((req) async {
      if (req.method == 'POST' && req.url.path.contains('load-sell-in-plan')) {
        final accepted = http.Response(
          jsonEncode({'job_id': 'job-sellin', 'status': 'running'}),
          202,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: http.Request('POST', req.url),
        );
        return accepted;
      }
      expect(req.url.path, contains('/api/v1/jobs/job-sellin'));
      polls++;
      if (polls < runningBeforeDone) {
        return http.Response(
          jsonEncode({'job_id': 'job-sellin', 'status': 'running'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'job_id': 'job-sellin',
          'status': 'done',
          'http_status': 200,
          'body': {
            'batch_id': 'batch_in26',
            'filename': 'in26.xlsx',
            'retailer_detected': 'fathalla',
            'valid_rows': 40927,
            'total_rows': 40927,
            'anomaly_rows': 0,
            'total_revenue': 133191402.85,
            'total_quantity': 1,
            'confidence_score': 0.0,
            'is_staged': false,
            'is_committed': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final api = ApiClient(
      tenantId: 'tenant-adeco',
      authToken: 'tok',
      allowMockFallback: false,
    );

    // Override poll interval by calling awaitJob is already covered; here we use the real
    // upload path. Default pollEvery is 2s — keep runningBeforeDone small.
    await http.runWithClient(() async {
      final res = await api.uploadSellInFile(
        filename: 'in26.xlsx',
        fileBytes: [1, 2, 3, 4],
        chain: 'fathalla',
      );
      expect(res.validRows, 40927);
      expect(res.filename, 'in26.xlsx');
      expect(res.isCommitted, isTrue);
    }, () => client);

    expect(polls, runningBeforeDone);
  });
}

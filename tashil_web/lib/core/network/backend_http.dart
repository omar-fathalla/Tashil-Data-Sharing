import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_swr_cache.dart';

/// Single entry point for every backend HTTP call.
///
/// Every response passes through [onResponseStatus], which ApiClient wires to
/// its session-expired handling: a 401/403 (refused or expired login, e.g. a
/// stale token after a deploy) logs the user out to the login screen instead
/// of leaving pages blank.
class BackendHttp {
  BackendHttp._();

  static void Function(int statusCode, Uri url)? onResponseStatus;

  static T _note<T extends http.BaseResponse>(T r, Uri url) {
    onResponseStatus?.call(r.statusCode, url);
    return r;
  }

  /// Stale-while-revalidate cache for backend GET reads (see [HttpSwrCache]).
  static final HttpSwrCache cache = HttpSwrCache();

  /// Bumped whenever cached backend data is known to have changed (a background
  /// revalidation got new content, or this client made a successful write).
  /// Data screens listen to it to refresh silently.
  static ValueNotifier<int> get dataRevision => cache.revision;

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      cache.get(url, headers, (h) async => _note(await http.get(url, headers: h), url));

  static T _mutated<T extends http.BaseResponse>(T r) {
    if (r.statusCode >= 200 && r.statusCode < 300) cache.invalidateAll();
    return r;
  }

  static Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _mutated(_note(await http.post(url, headers: headers, body: body), url));

  static Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _mutated(_note(await http.put(url, headers: headers, body: body), url));

  static Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _mutated(_note(await http.patch(url, headers: headers, body: body), url));

  static Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _mutated(_note(await http.delete(url, headers: headers, body: body), url));

  static Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      request.method == 'GET'
          ? _note(await request.send(), request.url)
          : _mutated(_note(await request.send(), request.url));

  /// Header that asks the backend to run a large ingest as a background job.
  static const asyncJobHeader = 'X-Tashil-Async';

  /// When [response] is a 202 with a `job_id`, polls `GET /api/v1/jobs/{id}` until the
  /// job finishes and returns the job's own HTTP status and body, so callers handle it
  /// like a normal synchronous response. Any other response is returned unchanged.
  static Future<http.Response> awaitJob(
    http.Response response, {
    Map<String, String>? headers,
    Duration pollEvery = const Duration(seconds: 2),
    Duration maxWait = const Duration(minutes: 20),
  }) async {
    if (response.statusCode != 202) return response;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return response;
    }
    if (decoded is! Map || decoded['job_id'] is! String) return response;
    final origin = response.request?.url;
    if (origin == null) return response;
    final jobUri = origin.replace(
      path: '/api/v1/jobs/${decoded['job_id']}',
      queryParameters: const <String, String>{},
    ).removeFragment();
    final pollHeaders = Map<String, String>.from(headers ?? const {})
      ..remove('Content-Type')
      ..remove(asyncJobHeader);
    final deadline = DateTime.now().add(maxWait);
    var misses = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      http.Response poll;
      try {
        poll = await get(jobUri, headers: pollHeaders).timeout(const Duration(seconds: 20));
      } catch (_) {
        continue;
      }
      if (poll.statusCode == 404 && ++misses < 10) continue;
      if (poll.statusCode != 200) return poll;
      final job = jsonDecode(utf8.decode(poll.bodyBytes));
      if (job is! Map) continue;
      final status = job['status'];
      if (status == 'running') continue;
      final httpStatus = (job['http_status'] as num?)?.toInt() ?? 500;
      final body = job['body'];
      final bodyText = body == null
          ? jsonEncode({'message': job['error'] ?? 'job failed'})
          : (body is String ? body : jsonEncode(body));
      return http.Response.bytes(utf8.encode(bodyText), httpStatus,
          request: poll.request, headers: const {'content-type': 'application/json; charset=utf-8'});
    }
    return http.Response(jsonEncode({'message': 'انتهت مهلة انتظار معالجة الملف'}), 504);
  }
}

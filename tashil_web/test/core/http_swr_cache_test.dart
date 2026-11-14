import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tashil_web/core/network/http_swr_cache.dart';

void main() {
  final url = Uri.parse('https://x/api/v1/analytics/records');

  test('serves cached instantly, revalidates with ETag, bumps only on change',
      () async {
    var now = DateTime(2026);
    final cache = HttpSwrCache(clock: () => now);
    var calls = 0;
    var body = 'v1';
    final seenTags = <String?>[];
    Future<http.Response> send(Map<String, String>? h) async {
      calls++;
      seenTags.add(h?['If-None-Match']);
      final tag = '"$body"';
      if (h?['If-None-Match'] == tag) return http.Response('', 304);
      return http.Response(body, 200, headers: {'etag': tag});
    }

    expect((await cache.get(url, {}, send)).body, 'v1');
    expect((await cache.get(url, {}, send)).body, 'v1');
    expect(calls, 1);

    now = now.add(const Duration(minutes: 1));
    expect((await cache.get(url, {}, send)).body, 'v1');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    expect(seenTags.last, '"v1"');
    expect(cache.revision.value, 0);

    body = 'v2';
    now = now.add(const Duration(minutes: 1));
    expect((await cache.get(url, {}, send)).body, 'v1');
    await Future<void>.delayed(Duration.zero);
    expect(cache.revision.value, 1);
    expect((await cache.get(url, {}, send)).body, 'v2');
  });

  test('invalidateAll drops entries and notifies; other sessions isolated',
      () async {
    final cache = HttpSwrCache();
    var calls = 0;
    Future<http.Response> send(Map<String, String>? h) async {
      calls++;
      return http.Response('${h?['Authorization']}', 200);
    }

    expect((await cache.get(url, {'Authorization': 'a'}, send)).body, 'a');
    expect((await cache.get(url, {'Authorization': 'b'}, send)).body, 'b');
    expect(calls, 2);
    cache.invalidateAll();
    expect(cache.revision.value, 1);
    await cache.get(url, {'Authorization': 'a'}, send);
    expect(calls, 3);
  });

  test('304 without a cached entry is retried unconditionally, never surfaced',
      () async {
    final cache = HttpSwrCache();
    final seen = <String?>[];
    Future<http.Response> send(Map<String, String>? h) async {
      seen.add(h?['If-None-Match']);
      if (seen.length == 1) return http.Response('', 304);
      return http.Response('fresh', 200, headers: {'etag': '"f"'});
    }

    final r = await cache.get(url, {'If-None-Match': '"browser"'}, send);
    expect(r.statusCode, 200);
    expect(r.body, 'fresh');
    expect(seen.last, isNull);
  });

  test('generation change mid-flight: 304 is retried, inFlight cleared',
      () async {
    var now = DateTime(2026);
    final cache = HttpSwrCache(clock: () => now);
    var calls = 0;
    final gate = Completer<void>();
    Future<http.Response> send(Map<String, String>? h) async {
      calls++;
      if (h?['If-None-Match'] != null) {
        await gate.future;
        return http.Response('', 304);
      }
      return http.Response('v$calls', 200, headers: {'etag': '"e"'});
    }

    expect((await cache.get(url, {}, send)).body, 'v1');
    cache.expireAll();
    final pending = cache.get(url, {}, send);
    await Future<void>.delayed(Duration.zero);
    cache.invalidateAll();
    gate.complete();
    final r = await pending;
    expect(r.statusCode, 200);
    expect(r.body, 'v3');
    expect((await cache.get(url, {}, send)).statusCode, 200);
  });

  test('expireAll keeps bodies and revalidates with ETag before serving',
      () async {
    final cache = HttpSwrCache();
    var calls = 0;
    Future<http.Response> send(Map<String, String>? h) async {
      calls++;
      if (h?['If-None-Match'] == '"a"') return http.Response('', 304);
      return http.Response('a', 200, headers: {'etag': '"a"'});
    }

    await cache.get(url, {}, send);
    cache.expireAll();
    final r = await cache.get(url, {}, send);
    expect(r.statusCode, 200);
    expect(r.body, 'a');
    expect(calls, 2);
    expect(cache.revision.value, 0);
  });

  test('invalidateUrl drops that URL and next read is unconditional', () async {
    final cache = HttpSwrCache();
    var calls = 0;
    Future<http.Response> send(Map<String, String>? h) async {
      calls++;
      if (h?['If-None-Match'] != null) {
        fail(
            'invalidateUrl must not send If-None-Match, got ${h?['If-None-Match']}');
      }
      return http.Response('body$calls', 200, headers: {'etag': '"$calls"'});
    }

    expect((await cache.get(url, {}, send)).body, 'body1');
    cache.invalidateUrl(url);
    expect((await cache.get(url, {}, send)).body, 'body2');
    expect(calls, 2);
  });
}

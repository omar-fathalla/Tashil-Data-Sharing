import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tashil_web/core/network/http_swr_cache.dart';

void main() {
  final url = Uri.parse('https://x/api/v1/analytics/records');

  test('serves cached instantly, revalidates with ETag, bumps only on change', () async {
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

  test('invalidateAll drops entries and notifies; other sessions isolated', () async {
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
}

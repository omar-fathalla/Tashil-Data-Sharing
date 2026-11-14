import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// In-memory stale-while-revalidate cache for backend GET JSON reads.
///
/// - A cached response is returned immediately, so screens re-opened after navigation
///   render at once instead of showing a spinner.
/// - Older than [freshFor], it is revalidated in the background with `If-None-Match`
///   (the backend answers 304 when nothing changed, so only a tiny request is made).
/// - When the content did change, the entry is replaced and [revision] is bumped so
///   listening screens reload silently from the fresh entry.
/// - Any successful write ([invalidateAll]) drops every entry and bumps [revision].
///
/// Entries are keyed by URL and request headers (token, tenant, role), so data never
/// crosses sessions; [clear] is called on logout.
class HttpSwrCache {
  HttpSwrCache({
    this.freshFor = const Duration(seconds: 20),
    this.maxEntries = 80,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration freshFor;
  final int maxEntries;
  final DateTime Function() _now;
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, _SwrEntry> _entries = <String, _SwrEntry>{};
  final Map<String, Future<http.Response>> _inFlight =
      <String, Future<http.Response>>{};

  int get length => _entries.length;

  static bool _eligible(Uri url) {
    final p = url.path;
    return p.startsWith('/api/v1/') &&
        !p.endsWith('/download') &&
        !p.startsWith('/api/v1/jobs/') &&
        !p.startsWith('/api/v1/auth/') &&
        p != '/api/v1/version';
  }

  static String _key(Uri url, Map<String, String>? headers) {
    final h = (headers ?? const <String, String>{}).entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return '$url\n${h.map((e) => '${e.key.toLowerCase()}=${e.value}').join('\n')}';
  }

  Future<http.Response> get(
    Uri url,
    Map<String, String>? headers,
    Future<http.Response> Function(Map<String, String>? headers) send,
  ) async {
    if (!_eligible(url)) return send(headers);
    final key = _key(url, headers);
    final hit = _entries[key];
    if (hit != null) {
      if (hit.mustRevalidate) {
        // Explicitly expired (forceRefresh): wait for a cheap conditional check.
        return _revalidate(key, hit, headers, send);
      }
      if (_now().difference(hit.checkedAt) >= freshFor) {
        unawaited(_revalidate(key, hit, headers, send)
            .catchError((_) => hit.toResponse()));
      }
      return hit.toResponse();
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _fetch(key, null, headers, send);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<http.Response> _revalidate(
    String key,
    _SwrEntry hit,
    Map<String, String>? headers,
    Future<http.Response> Function(Map<String, String>? headers) send,
  ) {
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _fetch(key, hit, headers, send);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  /// Never returns a 304 to the caller: a 304 is mapped to the cached body when it
  /// is still valid, otherwise the request is retried without `If-None-Match`.
  Future<http.Response> _fetch(
    String key,
    _SwrEntry? previous,
    Map<String, String>? headers,
    Future<http.Response> Function(Map<String, String>? headers) send,
  ) async {
    final generation = _generation;
    final reqHeaders = <String, String>{...?headers};
    final tag = previous?.etag;
    if (tag != null) reqHeaders['If-None-Match'] = tag;
    var resp = await send(reqHeaders);
    final stale = generation != _generation;
    if (resp.statusCode == 304) {
      if (previous != null && !stale) {
        previous.checkedAt = _now();
        previous.mustRevalidate = false;
        return previous.toResponse();
      }
      final plain = <String, String>{...?headers}..remove('If-None-Match');
      resp = await send(plain);
      if (resp.statusCode == 304) {
        throw http.ClientException(
            'Unexpected 304 for unconditional request', resp.request?.url);
      }
    }
    if (stale || generation != _generation) return resp;
    if (resp.statusCode == 200) {
      final etag = resp.headers['etag'];
      final changed = previous == null ||
          (etag == null || previous.etag == null
              ? !listEquals(resp.bodyBytes, previous.bodyBytes)
              : etag != previous.etag);
      _put(key, _SwrEntry(resp.bodyBytes, resp.headers, etag, _now()));
      if (previous != null && changed) _bump();
    }
    return resp;
  }

  void _put(String key, _SwrEntry entry) {
    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  int _generation = 0;

  void _bump() => revision.value++;

  /// Drops every cached response and notifies listeners (after uploads, edits, deletes).
  void invalidateAll() {
    _generation++;
    _entries.clear();
    _inFlight.clear();
    _bump();
  }

  /// Keeps cached bodies but makes the next read of each wait for an ETag
  /// revalidation (cheap 304 when unchanged). Used for scoped refreshes so one
  /// screen's forceRefresh does not throw away every other screen's data.
  void expireAll() {
    for (final e in _entries.values) {
      e.mustRevalidate = true;
    }
  }

  /// Makes the next read of [url] (any headers) wait for a revalidation.
  void expireUrl(Uri url) {
    final prefix = '$url\n';
    for (final e in _entries.entries) {
      if (e.key.startsWith(prefix)) e.value.mustRevalidate = true;
    }
  }

  /// Drops cached responses for [url] (any headers) and bumps [revision] so
  /// the next read hits the network without If-None-Match. Used after archive
  /// delete/upload so the files tab does not keep an empty or stale list.
  void invalidateUrl(Uri url) {
    final prefix = '$url\n';
    final before = _entries.length;
    _entries.removeWhere((k, _) => k.startsWith(prefix));
    if (_entries.length != before) {
      _generation++;
      _bump();
    }
  }

  /// Drops every cached response without notifying (logout / session switch).
  void clear() {
    _generation++;
    _entries.clear();
    _inFlight.clear();
  }
}

class _SwrEntry {
  _SwrEntry(this.bodyBytes, this.headers, this.etag, this.checkedAt);

  final Uint8List bodyBytes;
  final Map<String, String> headers;
  final String? etag;
  DateTime checkedAt;
  bool mustRevalidate = false;

  http.Response toResponse() =>
      http.Response.bytes(bodyBytes, 200, headers: headers);
}

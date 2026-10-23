/// Simple in-memory TTL cache keyed by string. Use [key] to build tenant-aware keys
/// so data never leaks across tenants on the same browser session.
class CacheStore {
  final Duration defaultTtl;
  final DateTime Function() _now;
  final Map<String, _Entry> _entries = {};

  CacheStore({this.defaultTtl = const Duration(minutes: 5), DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// Builds `tenant|feature|part1|part2...`.
  static String key(String tenantId, String feature, [List<Object?> parts = const []]) =>
      [tenantId, feature, ...parts.map((p) => p?.toString() ?? '')].join('|');

  /// Prefix covering every key of one tenant + feature, for [invalidatePrefix].
  static String prefix(String tenantId, String feature) => '$tenantId|$feature|';

  T? get<T>(String key) {
    final e = _entries[key];
    if (e == null) return null;
    if (!_now().isBefore(e.expiresAt)) {
      _entries.remove(key);
      return null;
    }
    final v = e.value;
    return v is T ? v : null;
  }

  void put<T>(String key, T value, {Duration? ttl}) {
    _entries[key] = _Entry(value, _now().add(ttl ?? defaultTtl));
  }

  /// Returns the cached value or computes, stores and returns it.
  Future<T> getOrLoad<T>(String key, Future<T> Function() load, {Duration? ttl}) async {
    final hit = get<T>(key);
    if (hit != null) return hit;
    final v = await load();
    put<T>(key, v, ttl: ttl);
    return v;
  }

  bool contains(String key) => get<Object?>(key) != null;
  void invalidate(String key) => _entries.remove(key);
  void invalidatePrefix(String prefix) => _entries.removeWhere((k, _) => k.startsWith(prefix));
  void clear() => _entries.clear();
  int get length => _entries.length;
}

class _Entry {
  final Object? value;
  final DateTime expiresAt;
  _Entry(this.value, this.expiresAt);
}

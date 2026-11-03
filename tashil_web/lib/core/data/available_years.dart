import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/backend_http.dart';

/// Years offered by the year filters: every year that has data plus the current year, newest first.
/// The default is the latest year that has data (never a hard-coded year).
@immutable
class YearOptions {
  final List<int> years;
  final int defaultYear;

  const YearOptions({required this.years, required this.defaultYear});

  /// Before the server answers: the current year only.
  factory YearOptions.fallback([DateTime? now]) {
    final y = (now ?? DateTime.now()).year;
    return YearOptions(years: [y], defaultYear: y);
  }

  factory YearOptions.fromJson(Map<String, dynamic> j, [DateTime? now]) {
    final current = (now ?? DateTime.now()).year;
    final set = <int>{current};
    for (final v in (j['years'] as List?) ?? const []) {
      final y = v is int ? v : int.tryParse('$v');
      if (y != null && y >= 2000 && y <= 2100) set.add(y);
    }
    final def = j['default_year'] is int ? j['default_year'] as int : int.tryParse('${j['default_year']}');
    final years = set.toList()..sort((a, b) => b.compareTo(a));
    return YearOptions(years: years, defaultYear: def != null && set.contains(def) ? def : years.first);
  }

  /// The list to show in a filter; keeps an already selected year visible.
  List<int> including(int selected) {
    if (selected < 2000 || years.contains(selected)) return years;
    return [...years, selected]..sort((a, b) => b.compareTo(a));
  }
}

/// App-wide cache of [YearOptions], loaded once per session from GET /api/v1/sell-in/years.
class AvailableYears {
  AvailableYears._();

  static final ValueNotifier<YearOptions> notifier = ValueNotifier<YearOptions>(YearOptions.fallback());
  static Future<YearOptions>? _inFlight;
  static bool _loaded = false;

  static YearOptions get current => notifier.value;
  static bool get isLoaded => _loaded;

  /// Loads once; later calls return the cached value unless [force] is set (e.g. after an upload).
  static Future<YearOptions> load(ApiClient api, {bool force = false}) {
    if (_loaded && !force) return Future.value(notifier.value);
    final pending = _inFlight;
    if (force && pending != null) {
      // A request started before the upload may miss its year: fetch again after it.
      return _inFlight = pending.then((_) => _fetch(api, force: true)).whenComplete(() => _inFlight = null);
    }
    return _inFlight ??= _fetch(api, force: force).whenComplete(() => _inFlight = null);
  }

  static Future<YearOptions> _fetch(ApiClient api, {bool force = false}) async {
    try {
      // Skip a cached (pre-upload) answer.
      if (force) BackendHttp.cache.expireUrl(Uri.parse(ApiEndpoints.dataYears));
      final res = await BackendHttp.get(Uri.parse(ApiEndpoints.dataYears), headers: api.requestHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        notifier.value = YearOptions.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
        _loaded = true;
      }
    } catch (_) {
      // Keep the fallback (current year); filters stay usable.
    }
    return notifier.value;
  }

  @visibleForTesting
  static void setForTest(YearOptions o) {
    notifier.value = o;
    _loaded = true;
  }
}

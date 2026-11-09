import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/backend_http.dart';

/// Months that have Sell-Out data for a year (1..12), ascending.
@immutable
class MonthOptions {
  final int year;
  final List<int> months;

  const MonthOptions({required this.year, required this.months});

  factory MonthOptions.empty(int year) => MonthOptions(year: year, months: const []);

  factory MonthOptions.fromJson(Map<String, dynamic> j, {int? fallbackYear}) {
    final year = j['year'] is int ? j['year'] as int : int.tryParse('${j['year']}') ?? fallbackYear ?? DateTime.now().year;
    final set = <int>{};
    for (final v in (j['months'] as List?) ?? const []) {
      final m = v is int ? v : int.tryParse('$v');
      if (m != null && m >= 1 && m <= 12) set.add(m);
    }
    final months = set.toList()..sort();
    return MonthOptions(year: year, months: months);
  }

  /// Keeps an already-selected month visible even if the server list is briefly stale.
  List<int> including(int selected) {
    if (selected < 1 || selected > 12 || months.contains(selected)) return months;
    return [...months, selected]..sort();
  }
}

/// Per-year cache of [MonthOptions] from GET /api/v1/sell-out/months.
class AvailableMonths {
  AvailableMonths._();

  static final Map<int, MonthOptions> _byYear = {};
  static final Map<int, Future<MonthOptions>> _inFlight = {};
  static final ValueNotifier<MonthOptions?> notifier = ValueNotifier<MonthOptions?>(null);

  static MonthOptions currentFor(int year) => _byYear[year] ?? MonthOptions.empty(year);

  static Future<MonthOptions> load(ApiClient api, int year, {bool force = false}) {
    if (year <= 0) return Future.value(MonthOptions.empty(year));
    if (!force && _byYear.containsKey(year)) return Future.value(_byYear[year]!);
    final pending = _inFlight[year];
    if (force && pending != null) {
      return _inFlight[year] = pending.then((_) => _fetch(api, year, force: true)).whenComplete(() => _inFlight.remove(year));
    }
    return _inFlight[year] ??= _fetch(api, year, force: force).whenComplete(() => _inFlight.remove(year));
  }

  static Future<MonthOptions> _fetch(ApiClient api, int year, {bool force = false}) async {
    try {
      final uri = Uri.parse(ApiEndpoints.dataMonths).replace(queryParameters: {'year': '$year'});
      if (force) BackendHttp.cache.expireUrl(uri);
      final res = await BackendHttp.get(uri, headers: api.requestHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final opts = MonthOptions.fromJson(
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
          fallbackYear: year,
        );
        _byYear[year] = opts;
        notifier.value = opts;
        return opts;
      }
    } catch (_) {
      // Keep last known / empty; screen can still derive months from returned series.
    }
    return _byYear[year] ?? MonthOptions.empty(year);
  }

  @visibleForTesting
  static void setForTest(MonthOptions o) {
    _byYear[o.year] = o;
    notifier.value = o;
  }

  @visibleForTesting
  static void clearForTest() {
    _byYear.clear();
    _inFlight.clear();
    notifier.value = null;
  }
}

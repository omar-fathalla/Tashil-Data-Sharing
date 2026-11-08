import '../../../core/network/api_client.dart';

/// Builds Arabic month picker options from the months that actually have data.
class CompetitorMonthOptions {
  CompetitorMonthOptions._();

  /// e.g. `كل الشهور (يناير - أكتوبر) — 2026` or `كل الشهور` when empty.
  static String allMonthsLabel(List<int> months, {int? year}) {
    final sorted = [...months.where((m) => m >= 1 && m <= 12)]..sort();
    String base;
    if (sorted.isEmpty) {
      base = 'كل الشهور';
    } else if (sorted.length == 1) {
      base = 'كل الشهور (${ApiClient.formatArabicMonthOnly(sorted.first)})';
    } else {
      final first = ApiClient.formatArabicMonthOnly(sorted.first);
      final last = ApiClient.formatArabicMonthOnly(sorted.last);
      base = 'كل الشهور ($first - $last)';
    }
    if (year != null && year > 0) return '$base — $year';
    return base;
  }

  /// Short range for copy: `يناير - أكتوبر` / `يناير` / `كل الشهور`.
  static String rangeLabel(List<int> months) {
    final sorted = [...months.where((m) => m >= 1 && m <= 12)]..sort();
    if (sorted.isEmpty) return 'كل الشهور';
    if (sorted.length == 1) return ApiClient.formatArabicMonthOnly(sorted.first);
    return '${ApiClient.formatArabicMonthOnly(sorted.first)} - ${ApiClient.formatArabicMonthOnly(sorted.last)}';
  }

  /// Comma-separated Arabic month names for narrative copy.
  static String enumeratedLabel(List<int> months) {
    final sorted = [...months.where((m) => m >= 1 && m <= 12)]..sort();
    if (sorted.isEmpty) return 'كل الشهور';
    return sorted.map(ApiClient.formatArabicMonthOnly).join('، ');
  }

  static List<({int month, String labelAr})> build(List<int> months, {int? year}) {
    final sorted = [...months.where((m) => m >= 1 && m <= 12)]..sort();
    return [
      (month: 0, labelAr: allMonthsLabel(sorted, year: year)),
      for (final m in sorted)
        (
          month: m,
          labelAr: '${ApiClient.formatArabicMonthOnly(m)} (${m.toString().padLeft(2, '0')})',
        ),
    ];
  }

  /// Distinct month numbers from a year's price series (ascending).
  static List<int> monthsFromSeries(Iterable<SkuMonthlyPricePointModel> points, {int? year}) {
    final set = <int>{};
    for (final p in points) {
      if (year != null && year > 0 && p.year != year) continue;
      if (p.monthNum >= 1 && p.monthNum <= 12) set.add(p.monthNum);
    }
    return set.toList()..sort();
  }

  /// Picker months: prefer the server sell-out month list (complete for the year)
  /// over a possibly seed-truncated series. Fall back to series only when API is empty.
  static List<int> resolveDataMonths({
    List<int> apiMonths = const [],
    List<int> seriesMonths = const [],
  }) {
    final api = [...apiMonths.where((m) => m >= 1 && m <= 12)]..sort();
    if (api.isNotEmpty) return api;
    return [...seriesMonths.where((m) => m >= 1 && m <= 12)]..sort();
  }
}

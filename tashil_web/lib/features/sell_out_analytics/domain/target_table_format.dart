import '../../../core/utils/currency_formatter.dart';

/// Display labels for the Sell-Out «المستهدف مقابل المحقق» table.
///
/// Formatting only. Stored month, scope, and amounts are unchanged, and the
/// full exact money / quantity stays available for tooltips.
abstract final class TargetTableFormat {
  static const _months = <String>[
    '',
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  /// Full year → `2027`. A month → `مارس 2026`. A quarter label → `Q1 2026`.
  static String period({
    required int year,
    required int month,
    required String monthLabel,
  }) {
    final label = monthLabel.trim();
    final quarter = _quarter(label, year);
    if (quarter != null) return quarter;
    if (month >= 1 && month <= 12) {
      final built = '${_months[month]} $year';
      if (label.isNotEmpty &&
          label.length <= 18 &&
          !label.contains('كل الشهور') &&
          !label.contains('إجمالي') &&
          label.contains(_months[month])) {
        return label;
      }
      return built;
    }
    return '$year';
  }

  /// `كل الفروع` when the target covers every branch and category.
  /// A specific branch and/or category keeps just that name.
  static String scope({required String branch, required String category}) {
    final b = branch.trim();
    final c = category.trim();
    final allBranches = _isAll(b, 'كل الفروع');
    final allCategories = _isAll(c, 'كل الفئات');
    if (allBranches && allCategories) return 'كل الفروع';
    if (allBranches) return c;
    if (allCategories) return b;
    return '$b • $c';
  }

  /// `84.8%`, or `—` when the period has no sales yet.
  static String achievement({required double pct, required bool hasActuals}) {
    if (!hasActuals) return '—';
    return '${pct.toStringAsFixed(1)}%';
  }

  /// Compact table money: `180M ج.م`, `127.1M ج.م`, `−22.9M ج.م`.
  static String money(double amount) {
    if (amount.abs() < 0.5) return '0 ج.م';
    final negative = amount < 0;
    final out = '${_scaled(amount.abs(), millionsDecimals: 1)} ج.م';
    if (!negative) return out;
    return '\u2066\u2212$out\u2069';
  }

  /// Exact money for the tooltip, e.g. `127,135,120 ج.م`.
  static String moneyExact(double amount) =>
      CurrencyFormatter.formatEGP(amount);

  /// `1.53M / 250K وحدة`, or `— / 250K وحدة` when actuals are missing.
  static String quantity({
    required double? actual,
    required double target,
    required String unit,
  }) {
    final t = _scaled(target.abs(), millionsDecimals: 2);
    final a = actual == null ? '—' : _scaled(actual.abs(), millionsDecimals: 2);
    return '\u2066$a / $t\u2069 $unit';
  }

  /// Exact quantity for the tooltip, e.g. `1,532,854 / 250,000 وحدة`.
  static String quantityExact({
    required double? actual,
    required double target,
    required String unit,
  }) {
    final t = CurrencyFormatter.formatNumber(target.round());
    final a =
        actual == null ? '—' : CurrencyFormatter.formatNumber(actual.round());
    return '\u2066$a / $t\u2069 $unit';
  }

  static bool _isAll(String value, String allLabel) {
    if (value.isEmpty) return true;
    return value == allLabel || value.toLowerCase() == 'all';
  }

  static String? _quarter(String label, int year) {
    if (label.isEmpty) return null;
    final en = RegExp(r'Q([1-4])', caseSensitive: false).firstMatch(label);
    if (en != null) return 'Q${en.group(1)} $year';
    if (!label.contains('ربع')) return null;
    const ordered = <(String, int)>[
      ('الأول', 1),
      ('الاول', 1),
      ('الثاني', 2),
      ('الثالث', 3),
      ('الرابع', 4),
    ];
    for (final (name, n) in ordered) {
      if (label.contains(name)) return 'Q$n $year';
    }
    final num = RegExp(r'ربع\s*([1-4])').firstMatch(label);
    if (num != null) return 'Q${num.group(1)} $year';
    return null;
  }

  /// Millions use [millionsDecimals] (1 for money, 2 for quantities).
  /// Thousands use one decimal. Trailing zeros are dropped (`180M`, `250K`).
  static String _scaled(double abs, {required int millionsDecimals}) {
    if (abs >= 1e9) {
      return _suffix(abs / 1e9, millionsDecimals, 'B');
    }
    if (abs >= 1e6) {
      return _suffix(abs / 1e6, millionsDecimals, 'M');
    }
    if (abs >= 1e3) {
      return _suffix(abs / 1e3, 1, 'K');
    }
    return abs.round().toString();
  }

  static String _suffix(double value, int decimals, String scale) {
    var s = value.toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return CurrencyFormatter.bindScaleSuffix(s, scale);
  }
}

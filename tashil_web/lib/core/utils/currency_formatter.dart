import 'package:intl/intl.dart';

/// Formatter for Egyptian Pounds (EGP) and large metric numbers.
class CurrencyFormatter {
  /// Signed percentage for RTL text: '+' / U+2212 MINUS SIGN stay on the
  /// left of the digits ("−3.5%", "+12.0%") because the whole value
  /// sits in an LRI…PDI isolate; a bare '-' in Arabic text renders as
  /// "3.5-%". A value that rounds to zero has no sign.
  static String formatSignedPct(double pct, {int decimals = 1}) {
    final abs = pct.abs().toStringAsFixed(decimals);
    final isZero = double.parse(abs) == 0.0;
    final sign = isZero ? '' : (pct > 0 ? '+' : '\u2212');
    return '\u2066$sign$abs%\u2069';
  }

  CurrencyFormatter._();

  static final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _integerFormat = NumberFormat('#,##0', 'en_US');

  /// Formats exact currency value: e.g. "14,500.50 ج.م"
  static String formatEGP(double amount, {bool showDecimals = false}) {
    if (showDecimals) {
      return '${_currencyFormat.format(amount)} ج.م';
    }
    return '${_integerFormat.format(amount.round())} ج.م';
  }

  /// Compact EGP for charts & cards, one place for spacing/rounding.
  /// - `words: false` (default) → "127.14M ج.م" / "250.0K ج.م" (KPI cards, unchanged).
  /// - `words: true` → "19.1 مليون ج.م" / "950 ألف ج.م" / "1.2 مليار ج.م" (chart axes).
  /// Always a normal space between number, scale word and currency; [isolate]
  /// wraps the value in FSI…PDI so it never reorders inside RTL text.
  static String formatCompactEGP(double amount,
      {bool words = false, int? decimals, bool isolate = false}) {
    if (amount < 0) {
      return '−${formatCompactEGP(-amount, words: words, decimals: decimals, isolate: isolate)}';
    }
    String trim(double v, int d) {
      final s = v.toStringAsFixed(d);
      return d > 0 && s.contains('.')
          ? s.replaceFirst(RegExp(r'\.?0+$'), '')
          : s; // 19.0 → 19
    }

    final String out;
    if (words && amount >= 1e9) {
      out = '${trim(amount / 1e9, decimals ?? 1)} مليار ج.م';
    } else if (amount >= 1e6) {
      out = words
          ? '${trim(amount / 1e6, decimals ?? 1)} مليون ج.م'
          : '${(amount / 1e6).toStringAsFixed(decimals ?? 2)}M ج.م';
    } else if (amount >= 1e3) {
      out = words
          ? '${trim(amount / 1e3, decimals ?? 0)} ألف ج.م'
          : '${(amount / 1e3).toStringAsFixed(decimals ?? 1)}K ج.م';
    } else {
      out = '${amount.toStringAsFixed(0)} ج.م';
    }
    return isolate ? '\u2068$out\u2069' : out;
  }

  /// Formats integer count with thousands separators: e.g. "125,400"
  static String formatUnits(int count) {
    return _integerFormat.format(count);
  }

  /// Formats any numeric count (int or double) with thousands separators.
  static String formatNumber(num count) {
    return _integerFormat.format(count.round());
  }

  /// Compact formatting for unit quantities: e.g. "45.2K وحدة"
  static String formatCompactUnits(int count) {
    if (count >= 1000000) {
      final inM = count / 1000000.0;
      return '${inM.toStringAsFixed(1)}M قطعة';
    } else if (count >= 1000) {
      final inK = count / 1000.0;
      return '${inK.toStringAsFixed(1)}K قطعة';
    }
    return '$count قطعة';
  }

  /// Chain margin amount. A loss reads "خسارة 21.36M ج.م" with no minus sign
  /// (Lexicon rule); a profit is the plain amount. [compact] picks the
  /// "21.36M" form, otherwise the full "21,360,308" form with separators.
  static String formatMarginEGP(double amount, {bool compact = true}) {
    final abs = amount.abs();
    final text = compact ? formatCompactEGP(abs) : formatEGP(abs);
    return amount < 0 ? 'خسارة $text' : text;
  }

  /// Margin percentage. A loss reads "خسارة 52.7%" (no minus sign); a profit
  /// reads "هامش 12.3%".
  static String formatMarginPct(double pct) {
    final text = '${pct.abs().toStringAsFixed(1)}%';
    return pct < 0 ? 'خسارة $text' : 'هامش $text';
  }

  /// Amount and percentage together, e.g. "خسارة 21.36M ج.م (52.7%)" or
  /// "4.10M ج.م (هامش 12.3%)".
  static String formatMarginSummary(double amount, double pct, {bool compact = true}) {
    final money = compact ? formatCompactEGP(amount.abs()) : formatEGP(amount.abs());
    final p = '${pct.abs().toStringAsFixed(1)}%';
    if (amount < 0 || pct < 0) {
      return 'خسارة $money ($p)';
    }
    return '$money (هامش $p)';
  }
}

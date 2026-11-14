import 'package:intl/intl.dart';

/// Formatter for Egyptian Pounds (EGP) and large metric numbers.
class CurrencyFormatter {
  /// Word joiner (U+2060) binds a compact number to its K/M suffix so
  /// CanvasKit cannot break "401.0K" into "401.0" / "K". Zero-width;
  /// currency (ج.م) stays after a normal space and may wrap.
  static const scaleJoiner = '\u2060';

  /// Bind a compact number to a Latin scale suffix (K/M) without a
  /// visible gap and without a line-break opportunity.
  static String bindScaleSuffix(String number, String suffix) =>
      '$number$scaleJoiner$suffix';

  /// Signed percentage for RTL text: '+' / U+2212 MINUS SIGN stay on the
  /// left of the digits ("−3.5%", "+12.0%") because the whole value
  /// sits in an LRI…PDI isolate; a bare '-' in Arabic text renders as
  /// "3.5-%". A value that rounds to zero has no sign unless
  /// [plusForZero] is true (then it is "+0.0%"), which matches the
  /// previous Trade Marketing subtitle rule.
  static String formatSignedPct(
    double pct, {
    int decimals = 1,
    bool plusForZero = false,
  }) {
    final abs = pct.abs().toStringAsFixed(decimals);
    final isZero = double.parse(abs) == 0.0;
    final String sign;
    if (isZero) {
      sign = plusForZero ? '+' : '';
    } else {
      sign = pct > 0 ? '+' : '\u2212';
    }
    return '\u2066$sign$abs%\u2069';
  }

  CurrencyFormatter._();

  static final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _integerFormat = NumberFormat('#,##0', 'en_US');

  /// Formats exact currency value: e.g. "14,500.50 ج.م".
  /// A negative amount keeps U+2212 on the left of the digits in RTL
  /// because the whole "−14,500 ج.م" sits in an LRI…PDI isolate.
  static String formatEGP(double amount, {bool showDecimals = false}) {
    final negative = amount < 0;
    final value = amount.abs();
    final body = showDecimals
        ? _currencyFormat.format(value)
        : _integerFormat.format(value.round());
    final out = negative ? '\u2212$body ج.م' : '$body ج.م';
    return negative ? '\u2066$out\u2069' : out;
  }

  /// Compact EGP for charts & cards, one place for spacing/rounding.
  /// - `words: false` (default) → "127.14M ج.م" / "250.0K ج.م" (KPI cards).
  ///   The K/M suffix is bound to the number with [scaleJoiner] so it
  ///   cannot wrap apart from the digits; «ج.م» stays on a normal space.
  /// - `words: true` → "19.1 مليون ج.م" / "950 ألف ج.م" / "1.2 مليار ج.م" (chart axes).
  /// Always a normal space between number, scale word and currency; [isolate]
  /// wraps the value in FSI…PDI so it never reorders inside RTL text.
  /// A negative amount always wraps the signed value (U+2212 plus the
  /// compact body, including "ج.م") in LRI…PDI so the minus stays on the
  /// left of the digits in RTL; [isolate] is still applied to positives.
  static String formatCompactEGP(double amount,
      {bool words = false, int? decimals, bool isolate = false}) {
    final negative = amount < 0;
    amount = amount.abs();
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
          : '${bindScaleSuffix((amount / 1e6).toStringAsFixed(decimals ?? 2), 'M')} ج.م';
    } else if (amount >= 1e3) {
      out = words
          ? '${trim(amount / 1e3, decimals ?? 0)} ألف ج.م'
          : '${bindScaleSuffix((amount / 1e3).toStringAsFixed(decimals ?? 1), 'K')} ج.م';
    } else {
      out = '${amount.toStringAsFixed(0)} ج.م';
    }
    final signed = negative ? '\u2212$out' : out;
    if (negative) return '\u2066$signed\u2069';
    return isolate ? '\u2068$signed\u2069' : signed;
  }

  /// Formats integer count with thousands separators: e.g. "125,400".
  /// Negatives use U+2212 inside LRI…PDI so the minus stays on the left
  /// of the digits in RTL; positives are unchanged.
  static String formatUnits(int count) => _signedInteger(count);

  /// Formats any numeric count (int or double) with thousands separators.
  static String formatNumber(num count) => _signedInteger(count.round());

  static String _signedInteger(int count) {
    if (count < 0) {
      return '\u2066\u2212${_integerFormat.format(count.abs())}\u2069';
    }
    return _integerFormat.format(count);
  }

  /// Compact formatting for unit quantities: e.g. "45.2K وحدة"
  static String formatCompactUnits(int count) {
    final negative = count < 0;
    final value = count.abs();
    final String out;
    if (value >= 1000000) {
      final inM = value / 1000000.0;
      out = '${bindScaleSuffix(inM.toStringAsFixed(1), 'M')} قطعة';
    } else if (value >= 1000) {
      final inK = value / 1000.0;
      out = '${bindScaleSuffix(inK.toStringAsFixed(1), 'K')} قطعة';
    } else {
      out = '$value قطعة';
    }
    final signed = negative ? '\u2212$out' : out;
    return negative ? '\u2066$signed\u2069' : signed;
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

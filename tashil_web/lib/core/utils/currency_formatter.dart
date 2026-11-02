import 'package:intl/intl.dart';

/// Formatter for Egyptian Pounds (EGP) and large metric numbers.
class CurrencyFormatter {
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

  /// Compact formatting for Bento cards: e.g. "1.45M ج.م" or "250K ج.م"
  static String formatCompactEGP(double amount) {
    if (amount < 0) {
      return '−${formatCompactEGP(-amount)}';
    }
    if (amount >= 1000000) {
      final inM = amount / 1000000.0;
      return '${inM.toStringAsFixed(2)}M ج.م';
    } else if (amount >= 1000) {
      final inK = amount / 1000.0;
      return '${inK.toStringAsFixed(1)}K ج.م';
    }
    return '${amount.toStringAsFixed(0)} ج.م';
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

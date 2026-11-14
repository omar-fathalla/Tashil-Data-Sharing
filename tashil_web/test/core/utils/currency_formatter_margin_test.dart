import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter margins', () {
    test('compact negative keeps M/K scaling instead of raw digits', () {
      expect(CurrencyFormatter.formatCompactEGP(-21360308),
          '\u2066−21.36M ج.م\u2069');
      expect(CurrencyFormatter.formatCompactEGP(-2500), '\u2066−2.5K ج.م\u2069');
    });

    test('loss reads خسارة with no minus sign', () {
      final s = CurrencyFormatter.formatMarginSummary(-21360308, -52.7);
      expect(s, 'خسارة 21.36M ج.م (52.7%)');
      expect(s.contains('-'), isFalse);
      expect(s.contains('−'), isFalse);
    });

    test('full form uses thousands separators', () {
      expect(CurrencyFormatter.formatMarginEGP(-21360308, compact: false), 'خسارة 21,360,308 ج.م');
      expect(CurrencyFormatter.formatMarginSummary(-22903739, -71.2, compact: false), 'خسارة 22,903,739 ج.م (71.2%)');
    });

    test('profit reads هامش', () {
      expect(CurrencyFormatter.formatMarginSummary(4100000, 12.3), '4.10M ج.م (هامش 12.3%)');
      expect(CurrencyFormatter.formatMarginPct(-60.9), 'خسارة 60.9%');
      expect(CurrencyFormatter.formatMarginPct(8), 'هامش 8.0%');
    });
  });
}

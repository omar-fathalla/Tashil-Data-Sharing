import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';

void main() {
  group('formatCompactEGP', () {
    test('default (KPI cards) output is unchanged', () {
      expect(CurrencyFormatter.formatCompactEGP(127.14e6), '127.14M ج.م');
      expect(CurrencyFormatter.formatCompactEGP(1.45e6), '1.45M ج.م');
      expect(CurrencyFormatter.formatCompactEGP(250e3), '250.0K ج.م');
      expect(CurrencyFormatter.formatCompactEGP(1e9), '1000.00M ج.م');
      expect(CurrencyFormatter.formatCompactEGP(512), '512 ج.م');
    });

    test('words: spaced Arabic scale words for chart axes', () {
      expect(CurrencyFormatter.formatCompactEGP(19.1e6, words: true),
          '19.1 مليون ج.م');
      expect(CurrencyFormatter.formatCompactEGP(19e6, words: true),
          '19 مليون ج.م');
      expect(CurrencyFormatter.formatCompactEGP(9.5e6, words: true),
          '9.5 مليون ج.م');
      expect(CurrencyFormatter.formatCompactEGP(950e3, words: true),
          '950 ألف ج.م');
      expect(CurrencyFormatter.formatCompactEGP(1.2e9, words: true),
          '1.2 مليار ج.م');
      expect(CurrencyFormatter.formatCompactEGP(0, words: true), '0 ج.م');
    });

    test('isolate wraps the value in FSI/PDI', () {
      expect(
          CurrencyFormatter.formatCompactEGP(1e6, words: true, isolate: true),
          '\u20681 مليون ج.م\u2069');
    });
  });
}

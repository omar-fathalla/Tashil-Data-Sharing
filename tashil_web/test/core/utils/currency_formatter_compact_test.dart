import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/currency_formatter.dart';

void main() {
  const wj = CurrencyFormatter.scaleJoiner;

  group('formatCompactEGP', () {
    test('default (KPI cards) uses compact K/M scaling', () {
      expect(CurrencyFormatter.formatCompactEGP(127.14e6), '127.14${wj}M ج.م');
      expect(CurrencyFormatter.formatCompactEGP(1.45e6), '1.45${wj}M ج.م');
      expect(CurrencyFormatter.formatCompactEGP(250e3), '250.0${wj}K ج.م');
      expect(CurrencyFormatter.formatCompactEGP(1e9), '1000.00${wj}M ج.م');
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

    test('negative compact wraps minus inside LRI and keeps currency placement', () {
      const lri = '\u2066';
      const pdi = '\u2069';
      const minus = '\u2212';
      expect(CurrencyFormatter.formatCompactEGP(-847), '${lri}${minus}847 ج.م${pdi}');
      expect(CurrencyFormatter.formatCompactEGP(-238), '${lri}${minus}238 ج.م${pdi}');
      expect(CurrencyFormatter.formatCompactEGP(-118), '${lri}${minus}118 ج.م${pdi}');
      // isolate:true on a negative still uses a single LRI, not a nested FSI.
      expect(
          CurrencyFormatter.formatCompactEGP(-2500, isolate: true),
          '${lri}${minus}2.5${wj}K ج.م${pdi}');
    });

    test('formatEGP negatives isolate the minus; positives stay unchanged', () {
      expect(CurrencyFormatter.formatEGP(14500), '14,500 ج.م');
      expect(CurrencyFormatter.formatEGP(-14500), '\u2066\u221214,500 ج.م\u2069');
      expect(
          CurrencyFormatter.formatEGP(-847.4, showDecimals: true),
          '\u2066\u2212847.40 ج.م\u2069');
    });

    test('K/M suffix is bound to the number with a word joiner', () {
      expect(CurrencyFormatter.formatCompactEGP(401000), '401.0${wj}K ج.م');
      expect(CurrencyFormatter.formatCompactEGP(401000).contains('401.0K'), isFalse);
      expect(CurrencyFormatter.formatCompactUnits(45200), '45.2${wj}K قطعة');
    });

    test('formatEGP isolate wraps a positive so RTL does not flip ج.م', () {
      expect(CurrencyFormatter.formatEGP(0, isolate: true), '\u20660 ج.م\u2069');
      expect(CurrencyFormatter.formatEGP(14500, isolate: true),
          '\u206614,500 ج.م\u2069');
    });

    test('formatNumber negatives isolate the minus; positives stay unchanged', () {
      expect(CurrencyFormatter.formatNumber(125400), '125,400');
      expect(CurrencyFormatter.formatNumber(-125400), '\u2066\u2212125,400\u2069');
    });

  });
}

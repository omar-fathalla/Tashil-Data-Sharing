import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/bidi_text.dart';

void main() {
  group('ltrIsolate', () {
    test('wraps Latin text in LRI…PDI', () {
      expect(ltrIsolate('file.xlsx'), '\u2066file.xlsx\u2069');
    });

    test('leaves empty text unchanged and does not double-wrap', () {
      expect(ltrIsolate(''), '');
      final once = ltrIsolate('SKU-1');
      expect(ltrIsolate(once), once);
    });
  });

  group('quotedLtr', () {
    test('quotes an isolated filename so a trailing ؟ stays at the end', () {
      const name = 'master.xlsx';
      expect(quotedLtr(name), '"\u2066$name\u2069"');
      expect(
        'هل تريد حذف ملف ${quotedLtr(name)}؟',
        'هل تريد حذف ملف "\u2066$name\u2069"؟',
      );
    });
  });

  group('rtlEnd', () {
    test('appends RLM so a trailing ASCII period stays at the end', () {
      const sentence = 'سيتم الحذف من Sell-Out.';
      expect(rtlEnd(sentence), '$sentence\u200F');
    });
  });
}

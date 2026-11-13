import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/shared_display_prefix.dart';

void main() {
  group('stripSharedLeadingPrefix', () {
    test('strips a shared Arabic prefix cut at a hyphen, keeping the remainder',
        () {
      final names = [
        'سلسلة تجريبية XYZ - مخزن ألفا',
        'سلسلة تجريبية XYZ - فرع بيتا',
        'سلسلة تجريبية XYZ - المستودع المركزي',
      ];
      expect(stripSharedLeadingPrefix(names), [
        'مخزن ألفا',
        'فرع بيتا',
        'المستودع المركزي',
      ]);
    });

    test('supports en-dash, em-dash and colon separators', () {
      expect(
        stripSharedLeadingPrefix(
            ['Acme Markets – Downtown', 'Acme Markets – Harbour']),
        ['Downtown', 'Harbour'],
      );
      expect(
        stripSharedLeadingPrefix(
            ['Acme Markets — Downtown', 'Acme Markets — Harbour']),
        ['Downtown', 'Harbour'],
      );
      expect(
        stripSharedLeadingPrefix(['Region: North', 'Region: South']),
        ['North', 'South'],
      );
    });

    test('trims Arabic and Unicode whitespace around the separator', () {
      const nbsp = '\u00A0';
      const thin = '\u2009';
      final names = [
        'سلسلة تجريبية$nbsp-  مخزن ألفا',
        'سلسلة تجريبية$nbsp-$thin فرع بيتا',
      ];
      expect(stripSharedLeadingPrefix(names), ['مخزن ألفا', 'فرع بيتا']);
    });

    test('leaves names unchanged when there is no common prefix', () {
      final names = ['مخزن ألفا', 'فرع بيتا'];
      expect(stripSharedLeadingPrefix(names), names);
    });

    test('leaves names unchanged when the common prefix has no separator', () {
      final names = [
        'سلسلة النور التجارية الشمالية',
        'سلسلة النور التجارية الجنوبية'
      ];
      expect(stripSharedLeadingPrefix(names), names);
    });

    test('leaves a single name unchanged', () {
      expect(stripSharedLeadingPrefix(['سلسلة تجريبية XYZ - مخزن ألفا']),
          ['سلسلة تجريبية XYZ - مخزن ألفا']);
    });

    test('leaves an empty list unchanged', () {
      expect(stripSharedLeadingPrefix(const []), isEmpty);
    });

    test(
        'never produces an empty name: skips stripping if any remainder is empty',
        () {
      final names = [
        'سلسلة تجريبية XYZ -',
        'سلسلة تجريبية XYZ - فرع بيتا',
      ];
      expect(stripSharedLeadingPrefix(names), names);
    });

    test('display map keeps the original name as the key', () {
      final names = [
        'سلسلة تجريبية XYZ - مخزن ألفا',
        'سلسلة تجريبية XYZ - فرع بيتا',
      ];
      final map = displayNamesWithoutSharedPrefix(names);
      expect(map['سلسلة تجريبية XYZ - مخزن ألفا'], 'مخزن ألفا');
      expect(
        displayNameWithoutSharedPrefix('سلسلة تجريبية XYZ - فرع بيتا', names),
        'فرع بيتا',
      );
    });
  });
}

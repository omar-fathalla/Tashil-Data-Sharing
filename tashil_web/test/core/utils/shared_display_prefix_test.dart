import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/shared_display_prefix.dart';

void main() {
  group('stripSharedLeadingPrefix', () {
    test(
      'strips a shared Arabic prefix cut at a hyphen, keeping the remainder',
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
      },
    );

    test(
      'strips a prefix repeated across ALL branches (Returns owner rule)',
      () {
        // Every name shares the chain prefix; display-only strip leaves the
        // branch remainder. Stored strings are unchanged (map keys).
        final names = [
          'فرع سلسلة تجريبية - الأنفوشي',
          'فرع سلسلة تجريبية - سيدي جابر',
          'فرع سلسلة تجريبية - الدخيلة',
          'فرع سلسلة تجريبية - العجمي',
          'فرع سلسلة تجريبية - كفر 2',
        ];
        final stripped = stripSharedLeadingPrefix(names);
        expect(stripped, [
          'الأنفوشي',
          'سيدي جابر',
          'الدخيلة',
          'العجمي',
          'كفر 2',
        ]);
        final map = displayNamesWithoutSharedPrefix(names);
        for (var i = 0; i < names.length; i++) {
          expect(map[names[i]], stripped[i]);
          expect(names[i], startsWith('فرع سلسلة تجريبية -'));
        }
      },
    );

    test('supports en-dash, em-dash and colon separators', () {
      expect(
        stripSharedLeadingPrefix([
          'Acme Markets – Downtown',
          'Acme Markets – Harbour',
        ]),
        ['Downtown', 'Harbour'],
      );
      expect(
        stripSharedLeadingPrefix([
          'Acme Markets — Downtown',
          'Acme Markets — Harbour',
        ]),
        ['Downtown', 'Harbour'],
      );
      expect(stripSharedLeadingPrefix(['Region: North', 'Region: South']), [
        'North',
        'South',
      ]);
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
        'سلسلة النور التجارية الجنوبية',
      ];
      expect(stripSharedLeadingPrefix(names), names);
    });

    test('leaves a single name unchanged', () {
      expect(stripSharedLeadingPrefix(['سلسلة تجريبية XYZ - مخزن ألفا']), [
        'سلسلة تجريبية XYZ - مخزن ألفا',
      ]);
    });

    test('leaves an empty list unchanged', () {
      expect(stripSharedLeadingPrefix(const []), isEmpty);
    });

    test(
      'never produces an empty name: leaves only the empty remainder unchanged',
      () {
        final names = ['سلسلة تجريبية XYZ -', 'سلسلة تجريبية XYZ - فرع بيتا'];
        expect(stripSharedLeadingPrefix(names), [
          'سلسلة تجريبية XYZ -',
          'فرع بيتا',
        ]);
      },
    );

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

    test(
      'normalises ة/ه, alef variants, dash variants and invisible marks',
      () {
        const rlm = '\u200F';
        const zwj = '\u200D';
        const nbsp = '\u00A0';
        // Live-like typo mix: ه vs ة, en-dash, NBSP, RLM/ZWJ.
        final names = [
          'سلسله تجريبيه XYZ - مخزن ألفا',
          'سلسلة تجريبية XYZ – فرع بيتا',
          'سلسلة تجريبية XYZ -$nbspالمستودع المركزي',
          '$rlmسلسلة تجريبية XYZ - $zwjفرع النيل',
        ];
        expect(stripSharedLeadingPrefix(names), [
          'مخزن ألفا',
          'فرع بيتا',
          'المستودع المركزي',
          'فرع النيل',
        ]);
      },
    );

    test('strips a majority prefix even when an outlier has no prefix', () {
      final names = [
        'سلسلة تجريبية XYZ - مخزن ألفا',
        'سلسلة تجريبية XYZ - فرع بيتا',
        'سلسلة تجريبية XYZ - المستودع المركزي',
        'فرع منفصل بدون بادئة',
      ];
      expect(stripSharedLeadingPrefix(names), [
        'مخزن ألفا',
        'فرع بيتا',
        'المستودع المركزي',
        'فرع منفصل بدون بادئة',
      ]);
    });

    test('does not strip a prefix that appears on only one name', () {
      final names = [
        'سلسلة تجريبية XYZ - مخزن ألفا',
        'فرع بيتا',
        'المستودع المركزي',
      ];
      expect(stripSharedLeadingPrefix(names), names);
    });

    test('strips a cluster shared by two names even when it is under 50%', () {
      final names = [
        'سلسلة تجريبية XYZ - مخزن ألفا',
        'سلسلة تجريبية XYZ - فرع بيتا',
        'المستودع المركزي',
        'فرع النيل',
        'فرع المعادي',
      ];
      expect(stripSharedLeadingPrefix(names), [
        'مخزن ألفا',
        'فرع بيتا',
        'المستودع المركزي',
        'فرع النيل',
        'فرع المعادي',
      ]);
    });

    test('strips multiple prefix clusters independently', () {
      // Mirrors the live v151 Returns pattern: a majority "ماركت -" group
      // and a minority "ماركت مواد عناية -" group, plus typo ة/ه variants.
      // Names are fictional; only the cluster structure is live-like.
      final names = [
        'عائله سلسله تجريبيه - مخزن ألفا',
        'عائلة سلسلة تجريبية - فرع بيتا',
        'عائله سلسله تجريبيه - عصمي التجريبي',
        'عائله سلسله تجريبيه مواد عناية - عصمي التجريبي',
        'عائله سلسله تجريبيه مواد عناية - فرع المطروح',
        'عائله سلسله تجريبيه مواد عناية - أبو يوسف التجريبي',
        'فرع منفصل بدون بادئة',
      ];
      expect(stripSharedLeadingPrefix(names), [
        'مخزن ألفا',
        'فرع بيتا',
        'عصمي التجريبي',
        'مواد عناية - عصمي التجريبي',
        'فرع المطروح',
        'أبو يوسف التجريبي',
        'فرع منفصل بدون بادئة',
      ]);
    });

    test('keeps enough of the prefix when stripping would collide', () {
      final names = [
        'سلسلة شمال - فرع الوسط',
        'سلسلة جنوب - فرع الوسط',
        'سلسلة شمال - فرع الشرق',
        'سلسلة جنوب - فرع الغرب',
      ];
      expect(stripSharedLeadingPrefix(names), [
        'شمال - فرع الوسط',
        'جنوب - فرع الوسط',
        'فرع الشرق',
        'فرع الغرب',
      ]);
    });

    test(
      'treats remainders that differ only by spaces next to digits as a collision',
      () {
        // Mirrors the live v153 Returns case: main-chain "… - كفر 2"
        // vs personal-care "… مواد عناية - كفر2" (no space before 2).
        // Fictional names only.
        const nbsp = '\u00A0';
        final names = [
          'عائله سلسله تجريبيه - كفر التجريبي',
          'عائله سلسله تجريبيه - كفر التجريبي 2',
          'عائلة سلسلة تجريبية - كفر التجريبي$nbsp 2',
          'عائله سلسله تجريبيه مواد عناية - كفر التجريبي',
          'عائله سلسله تجريبيه مواد عناية - كفر التجريبي2',
          'عائله سلسله تجريبيه مواد عناية - فرع المطروح',
        ];
        expect(stripSharedLeadingPrefix(names), [
          'كفر التجريبي',
          'كفر التجريبي 2',
          'كفر التجريبي$nbsp 2',
          'مواد عناية - كفر التجريبي',
          'مواد عناية - كفر التجريبي2',
          'فرع المطروح',
        ]);
      },
    );

    test('strips a live-like Store Matrix فرع prefix, leaving the outlier', () {
      final names = [
        'فرع سلسلة تجريبية - سيدي جابر ميني',
        'فرع سلسلة تجريبية - نيس2',
        'فرع سلسلة تجريبية - الدخيلة ميني',
        'غير موزع علي فرع',
      ];
      expect(stripSharedLeadingPrefix(names), [
        'سيدي جابر ميني',
        'نيس2',
        'الدخيلة ميني',
        'غير موزع علي فرع',
      ]);
    });

    test(
      'leaves a name that would become empty unchanged, strips the others',
      () {
        final names = [
          'سلسلة تجريبية XYZ -',
          'سلسلة تجريبية XYZ - فرع بيتا',
          'سلسلة تجريبية XYZ - مخزن ألفا',
        ];
        expect(stripSharedLeadingPrefix(names), [
          'سلسلة تجريبية XYZ -',
          'فرع بيتا',
          'مخزن ألفا',
        ]);
      },
    );
  });
}

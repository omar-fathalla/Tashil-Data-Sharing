import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/app_date_format.dart';

void main() {
  group('AppDateFormat.tryFormat', () {
    test('formats ISO dates', () {
      expect(
        AppDateFormat.tryFormat('2026-03-15T14:30:00'),
        '2026-03-15 14:30',
      );
      expect(
        AppDateFormat.tryFormat('2026-03-15T14:30:00', withTime: false),
        '2026-03-15',
      );
    });

    test('parses dd-MM-yyyy and dd/MM/yyyy', () {
      expect(AppDateFormat.tryFormat('15-03-2026 14:30'), '2026-03-15 14:30');
      expect(
        AppDateFormat.tryFormat('15/03/2026', withTime: false),
        '2026-03-15',
      );
    });

    test('empty or unparseable input returns the fallback or original', () {
      expect(AppDateFormat.tryFormat(''), 'غير محدد');
      expect(AppDateFormat.tryFormat('   ', fallback: '—'), '—');
      expect(AppDateFormat.tryFormat('not-a-date'), 'not-a-date');
    });
  });
}

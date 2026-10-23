import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/date_range.dart';

void main() {
  test('month end respects real month length', () {
    expect(DateRangeUtils.monthEnd(2026, 2), '2026-02-28');
    expect(DateRangeUtils.monthEnd(2028, 2), '2028-02-29');
    expect(DateRangeUtils.monthEnd(2026, 4), '2026-04-30');
    expect(DateRangeUtils.monthEnd(2026, 6), '2026-06-30');
    expect(DateRangeUtils.monthEnd(2026, 12), '2026-12-31');
    expect(DateRangeUtils.monthEnd(2026, 1), '2026-01-31');
  });
  test('month start is zero padded', () {
    expect(DateRangeUtils.monthStart(2026, 3), '2026-03-01');
  });
}

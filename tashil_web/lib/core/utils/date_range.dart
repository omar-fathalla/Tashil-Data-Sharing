/// Calendar helpers for building inclusive ISO (yyyy-MM-dd) date ranges.
class DateRangeUtils {
  DateRangeUtils._();

  /// Number of days in [month] (1-12) of [year], leap years included.
  static int daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  /// First day of the month as yyyy-MM-dd.
  static String monthStart(int year, int month) =>
      '$year-${_two(month)}-01';

  /// Last real day of the month as yyyy-MM-dd (28/29/30/31).
  static String monthEnd(int year, int month) =>
      '$year-${_two(month)}-${_two(daysInMonth(year, month))}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}

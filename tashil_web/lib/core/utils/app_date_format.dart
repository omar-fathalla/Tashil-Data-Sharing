import 'package:intl/intl.dart';

/// App-wide ISO display dates. Display only — stored values unchanged.
class AppDateFormat {
  AppDateFormat._();

  static final DateFormat dateTime = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat date = DateFormat('yyyy-MM-dd');

  /// Formats [dt] as `yyyy-MM-dd HH:mm` in the local zone.
  static String formatDateTime(DateTime dt) => dateTime.format(dt.toLocal());

  /// Formats [dt] as `yyyy-MM-dd` in the local zone.
  static String formatDate(DateTime dt) => date.format(dt.toLocal());

  /// Parses ISO or `dd-MM-yyyy` / `dd/MM/yyyy` (optional time) and
  /// returns the ISO display form. Empty or unparseable [raw] is
  /// returned as [fallback] (default «غير محدد»).
  static String tryFormat(
    String raw, {
    bool withTime = true,
    String fallback = 'غير محدد',
  }) {
    final s = raw.trim();
    if (s.isEmpty) return fallback;
    final dt = DateTime.tryParse(s) ?? _parseDmy(s);
    if (dt == null) return s;
    return withTime ? formatDateTime(dt) : formatDate(dt);
  }

  static DateTime? _parseDmy(String raw) {
    final m = RegExp(
      r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(raw);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4) ?? '0');
    final minute = int.parse(m.group(5) ?? '0');
    final second = int.parse(m.group(6) ?? '0');
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day, hour, minute, second);
  }
}

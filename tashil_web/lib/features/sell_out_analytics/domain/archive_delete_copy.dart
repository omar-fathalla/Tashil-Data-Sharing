import '../../../core/utils/bidi_text.dart';

/// True when deleting [targetMonth] would remove every month currently shown
/// (the file is not a single calendar month, or it is the last remaining file).
bool archiveFileCoversAllMonths(String targetMonth,
    {required bool isLastFile}) {
  final m = targetMonth.trim().toLowerCase();
  final specific = RegExp(r'^(0?[1-9]|1[0-2])$').hasMatch(m);
  return !specific || isLastFile;
}

/// Consequence line in the Sell-Out delete dialog. Never claims other months
/// are unaffected when this file covers all of them.
String sellOutDeleteConsequenceText({required bool coversAllMonths}) {
  if (coversAllMonths) {
    return rtlEnd('لن تتأثر بيانات ${ltrIsolate('Sell-In')}.');
  }
  return rtlEnd('لن تتأثر باقي الشهور ولا بيانات ${ltrIsolate('Sell-In')}.');
}

/// Consequence line in the Sell-In delete dialog.
String sellInDeleteConsequenceText({required bool coversAllMonths}) {
  if (coversAllMonths) {
    return rtlEnd(
        'سيُعاد حساب المخزون، ولن تتأثر بيانات ${ltrIsolate('Sell-Out')}.');
  }
  return rtlEnd(
      'سيُعاد حساب المخزون، ولن تتأثر باقي الشهور ولا بيانات ${ltrIsolate('Sell-Out')}.');
}

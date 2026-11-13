/// Short chip label + grey description for the Sell-In monthly stock-health
/// status (backend `stock_health_status` / `stock_health_label_ar`).
///
/// The chip always shows a short label (one or two words); the description
/// sits under it in smaller grey text. The full backend label stays in the
/// tooltip.
class MonthlyStatusText {
  const MonthlyStatusText(this.short, this.description);

  final String short;
  final String description;

  static const Map<String, MonthlyStatusText> byStatus = {
    'drawdown': MonthlyStatusText(
      'سحب عالٍ',
      'السحب أعلى من توريد الشهر، يحتاج تعويض',
    ),
    'balanced': MonthlyStatusText(
      'تصريف صحي',
      'معدل تصريف صحي ورصيد متبقي آمن',
    ),
    'accumulation': MonthlyStatusText(
      'تراكم مخزني',
      'التوريد أعلى من السحب، راقب الرصيد المتبقي',
    ),
    'awaiting_sell_out': MonthlyStatusText(
      'بانتظار Sell-Out',
      'توريد مضاف للمخزن، بانتظار رفع شيت كاشير السلسلة للشهر',
    ),
    'awaiting_sell_in': MonthlyStatusText(
      'بانتظار Sell-In',
      'سحب فعلي مسجل، بانتظار رفع شيت التوريد للشهر',
    ),
  };

  /// Known statuses use the mapping. Unknown ones fall back to the backend
  /// label: the part before "(" (or its first two words) in the chip and the
  /// rest underneath.
  static MonthlyStatusText resolve(String status, String label) {
    final known = byStatus[status.trim()];
    if (known != null) return known;
    final text = label.trim();
    final open = text.indexOf('(');
    if (open > 0) {
      final head = text.substring(0, open).trim();
      final detail =
          text.substring(open + 1).replaceAll(RegExp(r'\)\s*$'), '').trim();
      final words = head.split(RegExp(r'\s+'));
      if (words.length <= 2) return MonthlyStatusText(head, detail);
      return MonthlyStatusText(words.take(2).join(' '), '$head، $detail');
    }
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 2) return MonthlyStatusText(text, '');
    return MonthlyStatusText(words.take(2).join(' '), text);
  }
}

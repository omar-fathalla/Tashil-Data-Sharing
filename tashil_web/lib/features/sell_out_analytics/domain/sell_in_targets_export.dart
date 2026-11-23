import '../../../core/network/api_client.dart';

/// Group label for SKUs that have no brand in the Product Master.
const kNoBrandLabelAr = 'بدون براند';

/// Rows of the derived Sell-In targets export (one row per target × SKU).
///
/// Quantity (pieces, then cases) comes first and value (EGP) second, as on
/// screen. Only SKUs of the selected [brands] are exported (all when empty),
/// and the Brand column is always present.
class SellInTargetsExport {
  const SellInTargetsExport({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<dynamic>> rows;

  static const _headers = <String>[
    'السلسلة',
    'الفترة',
    'النطاق',
    'العلامة التجارية (Brand)',
    'كود الصنف',
    'الصنف',
    'المستهدف (قطعة)',
    'المستهدف (كرتونة)',
    'المحقق (قطعة)',
    'المحقق (كرتونة)',
    'الفرق (قطعة)',
    'نسبة تحقيق الكمية %',
    'المستهدف (ج.م)',
    'المحقق (ج.م)',
    'الفرق (ج.م)',
    'نسبة تحقيق القيمة %',
    'مستبعد من الإجماليات',
  ];

  static String brandOf(TargetSKUBreakdownModel s) {
    final b = s.brand.trim();
    return b.isEmpty ? kNoBrandLabelAr : b;
  }

  static dynamic _pct(double actual, double target) => target > 0
      ? double.parse((actual / target * 100).toStringAsFixed(1))
      : '';

  factory SellInTargetsExport.from(
    TargetsSummaryModel summary, {
    Iterable<String> brands = const [],
  }) {
    final wanted = brands.toSet();
    final rows = <List<dynamic>>[];
    for (final item in summary.items) {
      final period =
          item.monthLabel.trim().isNotEmpty ? item.monthLabel : '${item.year}';
      final scope = '${item.branchName} • ${item.category}';
      for (final s in item.chainSkuTotals) {
        final brand = brandOf(s);
        if (wanted.isNotEmpty && !wanted.contains(brand)) continue;
        final actual = item.hasActuals;
        rows.add([
          item.chainDisplayName,
          period,
          scope,
          brand,
          s.itemCode,
          s.skuName,
          s.targetUnits,
          s.targetCases ?? '',
          actual ? s.actualUnits : '',
          actual ? (s.actualCases ?? '') : '',
          actual ? s.actualUnits - s.targetUnits : '',
          actual ? _pct(s.actualUnits, s.targetUnits) : '',
          s.costMissing ? '' : s.targetRevenueEgp,
          actual && !s.costMissing ? s.actualRevenueEgp : '',
          actual && !s.costMissing
              ? s.actualRevenueEgp - s.targetRevenueEgp
              : '',
          actual && !s.costMissing
              ? _pct(s.actualRevenueEgp, s.targetRevenueEgp)
              : '',
          item.excludedFromTotals ? 'نعم' : '',
        ]);
      }
    }
    return SellInTargetsExport(headers: _headers, rows: rows);
  }
}

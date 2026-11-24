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

  static const _branchHeaders = <String>[
    'السلسلة',
    'السنة',
    'الشهر',
    'الفرع',
    'كود الفرع',
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
    'ملاحظات',
  ];

  /// SKUs of a branch, largest target (pieces) first, limited to [brands]
  /// (all when empty).
  static List<TargetSKUBreakdownModel> branchSkus(
    TargetBranchBreakdownModel branch, {
    Iterable<String> brands = const [],
  }) {
    final wanted = brands.toSet();
    final indexed = [
      for (final (i, s) in branch.skus.indexed)
        if (wanted.isEmpty || wanted.contains(brandOf(s))) (i, s),
    ];
    indexed.sort((a, b) {
      final byTarget = b.$2.targetUnits.compareTo(a.$2.targetUnits);
      return byTarget != 0 ? byTarget : a.$1.compareTo(b.$1);
    });
    return [for (final (_, s) in indexed) s];
  }

  /// True when the branch has any actual Sell-In (direct or allocated).
  static bool branchHasActuals(TargetBranchBreakdownModel b) =>
      b.actualUnits != 0 || b.actualRevenueEgp != 0;

  /// Rows of the branch × SKU export of one target: every branch in
  /// [branches] (pass one branch for a single-branch file).
  ///
  /// Cases read «—» without a Product Master pack size; value stays blank
  /// without a cost price (flagged in «ملاحظات», never estimated).
  factory SellInTargetsExport.branches(
    TargetComparisonModel item,
    Iterable<TargetBranchBreakdownModel> branches, {
    Iterable<String> brands = const [],
  }) {
    final month = item.month > 0
        ? (item.monthLabel.trim().isNotEmpty
            ? item.monthLabel.trim()
            : '${item.month}')
        : 'سنوي';
    final rows = <List<dynamic>>[];
    for (final b in branches) {
      final actual = branchHasActuals(b);
      for (final s in branchSkus(b, brands: brands)) {
        final notes = [
          if (s.packSizeMissing) 'بدون حجم عبوة في Product Master',
          if (s.costMissing) 'بدون سعر تكلفة (القيمة غير مقدّرة)',
        ];
        rows.add([
          item.chainDisplayName,
          item.year,
          month,
          b.branchName,
          b.branchCode,
          brandOf(s),
          s.itemCode,
          s.skuName,
          s.targetUnits,
          s.packSizeMissing ? '—' : (s.targetCases ?? '—'),
          actual ? s.actualUnits : '',
          actual ? (s.packSizeMissing ? '—' : (s.actualCases ?? '—')) : '',
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
          notes.join('، '),
        ]);
      }
    }
    return SellInTargetsExport(headers: _branchHeaders, rows: rows);
  }

  static final _unsafeFileChars = RegExp(r'[\\/:*?"<>|\s]+');

  /// CSV file name for a branch export: chain, branch (or «كل_الفروع»),
  /// year and, for a monthly target, the month.
  static String branchFileName(
    TargetComparisonModel item, {
    TargetBranchBreakdownModel? branch,
  }) {
    String safe(String v) => v
        .trim()
        .replaceAll(_unsafeFileChars, '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final chain = safe(item.retailerChain).isEmpty
        ? 'all'
        : safe(item.retailerChain);
    final scope = branch == null
        ? 'كل_الفروع'
        : (safe(branch.branchName).isNotEmpty
            ? safe(branch.branchName)
            : safe(branch.branchCode));
    final period = item.month > 0
        ? '${item.year}_${item.month.toString().padLeft(2, '0')}'
        : '${item.year}';
    return 'tashil_sell_in_targets_${chain}_${scope}_$period.csv';
  }
}

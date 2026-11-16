import '../../../core/utils/excel_export_service.dart';
import '../../../core/utils/shared_display_prefix.dart';
import '../data/target_breakdown_models.dart';

/// Branch display names for one breakdown: a prefix repeated across every
/// branch is stripped (display only; keys and totals are untouched).
Map<String, String> breakdownBranchDisplayNames(TargetBreakdownModel m) {
  return displayNamesWithoutSharedPrefix([
    ...m.branches.map((b) => b.branchName),
    ...m.noHistory.where((n) => n.branchName.isNotEmpty).map((n) => n.branchName),
  ]);
}

const List<String> targetBreakdownCsvHeaders = [
  'المستوى',
  'الفرع',
  'الصنف',
  'الحصة %',
  'المستهدف (ج.م)',
  'الكمية المستهدفة (وحدة)',
  'الكمية المستهدفة (كرتونة)',
  'المحقق (ج.م)',
  'الكمية المحققة (وحدة)',
  'نسبة التحقيق %',
  'الفرق (ج.م)',
];

/// Rows of the export, in the order shown on screen: every branch followed by
/// its SKUs, the exact-target total, then the zero-baseline list. Missing
/// values stay empty cells (never 0).
List<List<dynamic>> buildTargetBreakdownRows(TargetBreakdownModel m) {
  final names = breakdownBranchDisplayNames(m);
  final rows = <List<dynamic>>[];
  final dec = m.showDecimals ? 2 : 0;
  String money(double v) => v.toStringAsFixed(dec);
  String? pct(double? v) => v?.toStringAsFixed(1);
  String actual(double v) => m.hasActuals ? money(v) : '';
  String actualUnits(int v) => m.hasActuals ? '$v' : '';
  String gap(double v) => m.hasActuals ? money(v) : '';

  for (final b in m.branches) {
    rows.add([
      'فرع',
      names[b.branchName] ?? b.branchName,
      '',
      b.sharePct.toStringAsFixed(2),
      money(b.allocatedTargetEgp),
      b.allocatedUnits ?? '',
      b.allocatedCartons?.toStringAsFixed(1) ?? '',
      actual(b.actualRevenueEgp),
      actualUnits(b.actualUnits),
      m.hasActuals ? (pct(b.achievementPct) ?? '') : '',
      gap(b.gapEgp),
    ]);
    for (final s in b.skus) {
      rows.add([
        'صنف',
        names[b.branchName] ?? b.branchName,
        s.skuName,
        s.sharePct.toStringAsFixed(2),
        money(s.allocatedTargetEgp),
        s.allocatedUnits ?? '',
        s.allocatedCartons?.toStringAsFixed(1) ?? '',
        actual(s.actualRevenueEgp),
        actualUnits(s.actualUnits),
        m.hasActuals ? (pct(s.achievementPct) ?? '') : '',
        gap(s.gapEgp),
      ]);
    }
  }
  rows.add([
    'الإجمالي',
    '',
    '',
    m.hasBranches ? '100.00' : '',
    money(m.targetRevenueEgp),
    m.allocatedUnitsTotal ?? '',
    m.allocatedCartonsTotal?.toStringAsFixed(1) ?? '',
    actual(m.actualRevenueEgp),
    actualUnits(m.actualUnits),
    m.hasActuals ? (pct(m.achievementPct) ?? '') : '',
    gap(m.gapEgp),
  ]);
  for (final n in m.noHistory) {
    rows.add([
      'بدون مبيعات سابقة',
      names[n.branchName] ?? n.branchName,
      n.skuName,
      '',
      '',
      '',
      '',
      actual(n.actualRevenueEgp),
      actualUnits(n.actualUnits),
      '',
      '',
    ]);
  }
  return rows;
}

String buildTargetBreakdownCsv(TargetBreakdownModel m) =>
    ExcelExportService.generateCsv(
      headers: targetBreakdownCsvHeaders,
      rows: buildTargetBreakdownRows(m),
    );

String targetBreakdownFileName(TargetBreakdownModel m) {
  final chain = m.retailerChain.isEmpty ? 'target' : m.retailerChain;
  return 'target_breakdown_${chain}_${m.year}.csv';
}

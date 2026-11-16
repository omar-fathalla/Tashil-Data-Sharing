import '../../../core/network/api_client.dart';
import '../data/sell_out_explorer_repository.dart';

/// A branch as listed on the Sell-Out page for the selected (full) period.
class BranchGrowthBase {
  final String storeId;
  final String storeName;
  final String chain;
  final String region;
  final int units;

  /// Full selected-period revenue (every uploaded month of the selected year).
  final double revenue;

  const BranchGrowthBase({
    required this.storeId,
    required this.storeName,
    required this.chain,
    required this.region,
    required this.units,
    required this.revenue,
  });
}

/// One row of the «نمو الفروع» table.
///
/// [currentRevenue] and [prevRevenue] always cover the SAME month window, so
/// [varianceEgp] == [currentRevenue] - [prevRevenue] and [yoyGrowthPct] is
/// computed from those same two numbers. [fullPeriodRevenue] is the unmatched
/// selected-period total (used for ranking ties, status and the monthly average).
class BranchGrowthRow {
  final String storeId;
  final String storeName;
  final String chain;
  final String region;
  final double currentRevenue;
  final double prevRevenue;
  final double varianceEgp;
  final double? yoyGrowthPct;
  final double fullPeriodRevenue;
  final int currentUnits;
  final int prevUnits;
  final String status;

  const BranchGrowthRow({
    required this.storeId,
    required this.storeName,
    required this.chain,
    required this.region,
    required this.currentRevenue,
    required this.prevRevenue,
    required this.varianceEgp,
    required this.yoyGrowthPct,
    required this.fullPeriodRevenue,
    required this.currentUnits,
    required this.prevUnits,
    required this.status,
  });

  bool get hasPrevYear => prevRevenue > 0;
}

StoreBenchmarkItem? _lookup(
  Map<String, StoreBenchmarkItem> byId,
  String storeId,
  String storeName,
) {
  final direct = byId[storeId];
  if (direct != null) return direct;
  for (final e in byId.values) {
    if (e.storeName == storeName) return e;
  }
  return null;
}

/// Builds the growth table rows.
///
/// [prevByStore] is last year trimmed to the months that exist in the selected
/// year; [currentLikeForLikeByStore] is the selected year trimmed to the months
/// that exist last year (identical to the full-period matrix when a month or
/// date range is picked). Both therefore share one month window, which is what
/// the displayed sales columns, the difference and the % all use.
List<BranchGrowthRow> buildBranchGrowthRows({
  required List<BranchGrowthBase> branches,
  required Map<String, StoreBenchmarkItem> prevByStore,
  required Map<String, StoreBenchmarkItem> currentLikeForLikeByStore,
}) {
  final rows = branches.map((b) {
    final prevItem = _lookup(prevByStore, b.storeId, b.storeName);
    final curItem = _lookup(currentLikeForLikeByStore, b.storeId, b.storeName);
    final prevRev = prevItem?.totalRevenue ?? 0.0;
    final curRev = curItem?.totalRevenue ?? 0.0;
    final pct = likeForLikeYoyPct(curRev, prevRev);
    final status = prevRev <= 0
        ? (b.revenue > 0 ? 'new_branch' : 'declining')
        : ((pct ?? 0.0) >= 0 ? 'growing' : 'declining');
    return BranchGrowthRow(
      storeId: b.storeId,
      storeName: b.storeName,
      chain: b.chain,
      region: b.region != '—' ? b.region : (prevItem?.region ?? '—'),
      currentRevenue: curRev,
      prevRevenue: prevRev,
      varianceEgp: curRev - prevRev,
      yoyGrowthPct: pct,
      fullPeriodRevenue: b.revenue,
      currentUnits: b.units,
      prevUnits: prevItem?.totalUnits ?? 0,
      status: status,
    );
  }).toList();
  // Rank by what the table shows (matched window); full-period revenue breaks ties.
  rows.sort((a, b) {
    final c = b.currentRevenue.compareTo(a.currentRevenue);
    return c != 0 ? c : b.fullPeriodRevenue.compareTo(a.fullPeriodRevenue);
  });
  return rows;
}

const _monthNamesAr = <int, String>{
  1: 'يناير',
  2: 'فبراير',
  3: 'مارس',
  4: 'أبريل',
  5: 'مايو',
  6: 'يونيو',
  7: 'يوليو',
  8: 'أغسطس',
  9: 'سبتمبر',
  10: 'أكتوبر',
  11: 'نوفمبر',
  12: 'ديسمبر',
};

/// «يناير–أبريل» for a contiguous run, «يناير، مارس، مايو» otherwise,
/// «يناير» for a single month, empty when [months] has no valid month.
String matchedMonthsLabelAr(List<int> months) {
  final sorted = months.where(_monthNamesAr.containsKey).toSet().toList()
    ..sort();
  if (sorted.isEmpty) return '';
  if (sorted.length == 1) return _monthNamesAr[sorted.first]!;
  final contiguous = sorted.last - sorted.first == sorted.length - 1;
  if (contiguous) {
    return '${_monthNamesAr[sorted.first]}–${_monthNamesAr[sorted.last]}';
  }
  return sorted.map((m) => _monthNamesAr[m]!).join('، ');
}

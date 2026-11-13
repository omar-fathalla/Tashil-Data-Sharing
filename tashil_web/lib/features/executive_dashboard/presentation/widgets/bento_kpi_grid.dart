import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/arabic_plural.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/shared_display_prefix.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/m3_summary_kpi_card.dart';

/// Executive summary KPIs, using the shared Sell-Out card (138px, 1+1 lines).
class BentoKpiGrid extends StatelessWidget {
  final ExecutiveKPIsModel kpis;

  const BentoKpiGrid({super.key, required this.kpis});

  /// Shown on the detail line when there is no last-year data to compare.
  static const String noLastYearLabel = 'لا توجد بيانات للعام السابق';

  static String _formatSignedPct(double pct) {
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(1)}%';
  }

  /// One-line YoY/MoM detail. When last-year data is missing, the value is
  /// «—» and the explanation sits on the same detail line (Sell-Out 138px).
  static String _yearDetail({
    required bool yoyAvailable,
    required double momPct,
    required double yoyPct,
  }) {
    if (!yoyAvailable) {
      return '— · $noLastYearLabel';
    }
    return '${_formatSignedPct(momPct)} شهر · ${_formatSignedPct(yoyPct)} مقارنة بالعام السابق';
  }

  static String _shortChainNameAr(ChainShareItem item) {
    switch (item.retailerChain.toLowerCase().trim()) {
      case 'fathalla':
        return 'أسواق فتح الله';
      case 'gomla':
        return 'جملة ماركت';
      case 'carrefour':
        return 'كارفور';
      case 'spinneys':
        return 'سبينيس';
      default:
        final raw = item.displayName.trim();
        if (raw.isNotEmpty) {
          return raw.split('(').first.trim();
        }
        return item.retailerChain;
    }
  }

  String _buildActiveBranchesSubtitle() {
    final activeChains = kpis.chainShares
        .where((c) => c.totalRevenue > 0 || c.totalUnits > 0)
        .toList();
    if (activeChains.isNotEmpty) {
      final names = stripSharedLeadingPrefix(
        activeChains.map(_shortChainNameAr).toList(),
      );
      if (names.length == 1) {
        return names.first;
      }
      // Short enough for the 4-up live 1280 card: just the unique names.
      return names.join(' • ');
    }
    if (kpis.activeStoresCount == 0) {
      return 'لا توجد فروع نشطة في هذه الفترة';
    }
    return 'الفروع النشطة في الفترة المحددة';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same breakpoints as Sell-Out `_buildFourCardResponsiveLayout`
        // (960 / 580). At the live 1280+sidebar shell the content after
        // 24dp page padding is ~982dp, which is 4 columns there and 2
        // columns at a 1024+sidebar shell (~726dp).
        final columns = constraints.maxWidth >= 960
            ? 4
            : (constraints.maxWidth >= 580 ? 2 : 1);
        return M3EqualHeightGrid(
          key: const ValueKey('exec_kpi_grid'),
          columns: columns,
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: [
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_exec_sellout'),
              valueKey: const ValueKey('kpi_value_exec_sellout'),
              subtitleKey: const ValueKey('kpi_subtitle_exec_sellout'),
              title: 'إجمالي Sell-Out',
              value: CurrencyFormatter.formatCompactEGP(kpis.totalRevenue),
              subtitle: _yearDetail(
                yoyAvailable: kpis.yoyAvailable,
                momPct: kpis.revenueMomPct,
                yoyPct: kpis.revenueYoyPct,
              ),
              icon: AppIcons.money,
              color: colorScheme.primary,
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_exec_units'),
              valueKey: const ValueKey('kpi_value_exec_units'),
              subtitleKey: const ValueKey('kpi_subtitle_exec_units'),
              title: 'إجمالي الوحدات المباعة',
              value: CurrencyFormatter.formatCompactUnits(kpis.totalUnitsSold),
              subtitle: _yearDetail(
                yoyAvailable: kpis.yoyAvailable,
                momPct: kpis.unitsMomPct,
                yoyPct: kpis.unitsYoyPct,
              ),
              icon: AppIcons.units,
              color: colorScheme.tertiary,
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_exec_stores'),
              valueKey: const ValueKey('kpi_value_exec_stores'),
              subtitleKey: const ValueKey('kpi_subtitle_exec_stores'),
              title: 'الفروع النشطة',
              value: countBranches(kpis.activeStoresCount),
              subtitle: _buildActiveBranchesSubtitle(),
              icon: AppIcons.store,
              color: colorScheme.secondary,
            ),
            M3SummaryKpiCard(
              key: const ValueKey('kpi_card_exec_oos'),
              valueKey: const ValueKey('kpi_value_exec_oos'),
              subtitleKey: const ValueKey('kpi_subtitle_exec_oos'),
              title: 'نسبة النفاد',
              value: '${kpis.oosRatePct.toStringAsFixed(1)}%',
              subtitle:
                  'OSA ${kpis.osaRatePct.toStringAsFixed(1)}% · نفاد المخزون ${kpis.oosRatePct.toStringAsFixed(1)}%',
              icon: AppIcons.warning,
              color: colorScheme.error,
            ),
          ],
        );
      },
    );
  }
}

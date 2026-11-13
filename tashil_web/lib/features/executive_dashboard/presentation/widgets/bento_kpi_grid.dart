import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/m3_equal_height_grid.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/utils/currency_formatter.dart';

/// BentoKpiGrid renders executive KPIs in an M3 Bento-style asymmetric card layout.
class BentoKpiGrid extends StatelessWidget {
  final ExecutiveKPIsModel kpis;

  const BentoKpiGrid({
    super.key,
    required this.kpis,
  });

  /// Shown instead of "+0.0%" when there is no last-year data to compare.
  static const String noLastYearLabel = '— لا توجد بيانات للعام السابق';

  static String _formatSignedPctValue(double pct) {
    final sign = pct >= 0 ? '+' : '';
    return '$sign$pct%';
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
      final names = activeChains.map(_shortChainNameAr).toList();
      if (names.length == 1) {
        return 'فروع ${names.first} من الملف المرفوع';
      }
      return 'فروع ${names.join(' • ')} من الملفات المرفوعة';
    }
    if (kpis.activeStoresCount == 0) {
      return 'لا توجد فروع نشطة في هذه الفترة';
    }
    return 'الفروع النشطة في الفترة المحددة';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adaptive grid columns based on width
        final int crossAxisCount;
        if (constraints.maxWidth >= 1000) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 600) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 1;
        }

        final double cardWidth =
            (constraints.maxWidth - ((crossAxisCount - 1) * M3Spacing.sm)) /
                crossAxisCount;

        // All KPI cards share the tallest card's height (OOS has two tag
        // lines).
        return M3EqualHeightGrid(
          key: const ValueKey('exec_kpi_grid'),
          columns: crossAxisCount,
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: [
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'إجمالي Sell-Out',
                value: CurrencyFormatter.formatCompactEGP(kpis.totalRevenue),
                subtitle: CurrencyFormatter.formatEGP(kpis.totalRevenue),
                icon: AppIcons.money,
                growthPct: kpis.revenueGrowthPct,
                badgeLabel:
                    '${_formatSignedPctValue(kpis.revenueMomPct)} مقارنة بالشهر السابق',
                secondaryBadgeLabel: kpis.yoyAvailable
                    ? '${_formatSignedPctValue(kpis.revenueYoyPct)} مقارنة بالعام السابق'
                    : noLastYearLabel,
                isPositive: kpis.revenueMomPct >= 0,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'إجمالي الوحدات المباعة',
                value:
                    CurrencyFormatter.formatCompactUnits(kpis.totalUnitsSold),
                subtitle:
                    '${CurrencyFormatter.formatUnits(kpis.totalUnitsSold)} وحدة',
                icon: AppIcons.units,
                growthPct: kpis.unitsGrowthPct,
                badgeLabel:
                    '${_formatSignedPctValue(kpis.unitsMomPct)} مقارنة بالشهر السابق',
                secondaryBadgeLabel: kpis.yoyAvailable
                    ? '${_formatSignedPctValue(kpis.unitsYoyPct)} مقارنة بالعام السابق'
                    : noLastYearLabel,
                isPositive: kpis.unitsMomPct >= 0,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'الفروع النشطة',
                value:
                    '${kpis.activeStoresCount} ${kpis.activeStoresCount >= 3 && kpis.activeStoresCount <= 10 ? 'فروع' : 'فرع'}',
                subtitle: _buildActiveBranchesSubtitle(),
                icon: AppIcons.store,
                growthPct: 0.0,
                badgeLabel:
                    kpis.activeStoresCount > 0 ? 'نشطة' : 'لا توجد فروع نشطة',
                secondaryBadgeLabel: kpis.tenantMarketSharePct > 0
                    ? 'الحصة السوقية ${kpis.tenantMarketSharePct.toStringAsFixed(2)}% • ${kpis.totalSkusCount} صنف'
                    : null,
                isPositive: true,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'نسبة نفاد المخزون (OOS)',
                value: '${kpis.oosRatePct.toStringAsFixed(1)}%',
                subtitle:
                    'المبيعات المفقودة (تقديري): ${CurrencyFormatter.formatCompactEGP(kpis.estimatedLostRevenue)}',
                icon: AppIcons.warning,
                growthPct: -kpis.oosRatePct,
                badgeLabel:
                    'التوفر على الرف (OSA) ${kpis.osaRatePct.toStringAsFixed(1)}%',
                secondaryBadgeLabel:
                    'نفاد المخزون ${kpis.oosRatePct.toStringAsFixed(1)}% • ${kpis.totalOOSIncidents} حالة نفاد',
                isPositive: false,
                isAlert: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

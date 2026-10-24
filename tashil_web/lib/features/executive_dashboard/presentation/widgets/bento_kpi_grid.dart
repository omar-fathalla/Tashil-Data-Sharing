import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/utils/currency_formatter.dart';

/// BentoKpiGrid renders executive KPIs in an M3 Bento-style asymmetric card layout.
class BentoKpiGrid extends StatelessWidget {
  final ExecutiveKPIsModel kpis;

  const BentoKpiGrid({
    super.key,
    required this.kpis,
  });

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
        return 'فروع ${names.first} المستنتجة تلقائياً من الإكسيل';
      }
      return 'فروع ${names.join(' • ')} المستنتجة من الإكسيل';
    }
    if (kpis.activeStoresCount == 0) {
      return 'لا توجد فروع نشطة في هذه الفترة';
    }
    return 'فروع السلاسل النشطة في الفترة المحددة';
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

        final double cardWidth = (constraints.maxWidth - ((crossAxisCount - 1) * M3Spacing.sm)) / crossAxisCount;

        return Wrap(
          spacing: M3Spacing.sm,
          runSpacing: M3Spacing.sm,
          children: [
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'إجمالي مبيعات التجزئة',
                titleEn: 'Total Retail Sell-Out',
                value: CurrencyFormatter.formatCompactEGP(kpis.totalRevenue),
                subtitle: CurrencyFormatter.formatEGP(kpis.totalRevenue),
                icon: AppIcons.money,
                growthPct: kpis.revenueGrowthPct,
                badgeLabel: '${_formatSignedPctValue(kpis.revenueMomPct)} شهري',
                badgeLabelEn: 'MoM',
                secondaryBadgeLabel: '${_formatSignedPctValue(kpis.revenueYoyPct)} سنوي',
                secondaryBadgeLabelEn: 'YoY',
                isPositive: kpis.revenueMomPct >= 0,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'إجمالي الوحدات المباعة',
                titleEn: 'Total Units Sold',
                value: CurrencyFormatter.formatCompactUnits(kpis.totalUnitsSold),
                subtitle: '${CurrencyFormatter.formatUnits(kpis.totalUnitsSold)} عبوة',
                icon: AppIcons.units,
                growthPct: kpis.unitsGrowthPct,
                badgeLabel: '${_formatSignedPctValue(kpis.unitsMomPct)} شهري',
                badgeLabelEn: 'MoM',
                secondaryBadgeLabel: '${_formatSignedPctValue(kpis.unitsYoyPct)} سنوي',
                secondaryBadgeLabelEn: 'YoY',
                isPositive: kpis.unitsMomPct >= 0,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'الفروع النشطة المغطاة',
                titleEn: 'Active Covered Branches',
                value: '${kpis.activeStoresCount} فرع',
                subtitle: _buildActiveBranchesSubtitle(),
                icon: AppIcons.store,
                growthPct: 0.0,
                badgeLabel: kpis.activeStoresCount > 0 ? 'تغطية 100%' : 'تم التصفير (0 فرع)',
                badgeLabelEn: kpis.activeStoresCount > 0 ? '100% Coverage' : '0 Branches',
                secondaryBadgeLabel: kpis.tenantMarketSharePct > 0
                    ? 'الحصة السوقية: ${kpis.tenantMarketSharePct.toStringAsFixed(2)}% • ${kpis.totalSkusCount} صنف'
                    : null,
                secondaryBadgeLabelEn: kpis.tenantMarketSharePct > 0
                    ? 'Market Share • ${kpis.totalSkusCount} SKUs'
                    : null,
                isPositive: true,
                usePrimaryBadge: true,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                title: 'نسبة النواقص',
                titleEn: 'Out-of-Stock Rate (OOS Rate)',
                value: '${kpis.oosRatePct.toStringAsFixed(1)}%',
                subtitle: 'خسارة تقديرية: ${CurrencyFormatter.formatCompactEGP(kpis.estimatedLostRevenue)}',
                icon: AppIcons.warning,
                growthPct: -kpis.oosRatePct,
                badgeLabel: 'توافر الرفوف: ${kpis.osaRatePct.toStringAsFixed(1)}%',
                badgeLabelEn: 'On-Shelf Availability (OSA)',
                secondaryBadgeLabel: 'نسبة النواقص: ${kpis.oosRatePct.toStringAsFixed(1)}% • ${kpis.totalOOSIncidents} صنف ناقص',
                secondaryBadgeLabelEn: 'OOS Rate • ${kpis.totalOOSIncidents} OOS Incidents',
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

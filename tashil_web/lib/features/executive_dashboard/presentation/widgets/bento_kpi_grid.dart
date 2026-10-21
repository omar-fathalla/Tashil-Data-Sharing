import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';

/// BentoKpiGrid renders executive KPIs in an M3 Bento-style asymmetric card layout.
class BentoKpiGrid extends StatelessWidget {
  final ExecutiveKPIsModel kpis;

  const BentoKpiGrid({
    super.key,
    required this.kpis,
  });

  static String _formatSignedPct(double pct, String suffix) {
    final sign = pct >= 0 ? '+' : '';
    return '$sign$pct% $suffix';
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
              child: _KpiCard(
                title: 'إجمالي مبيعات التجزئة (Sell-Out)',
                value: CurrencyFormatter.formatCompactEGP(kpis.totalRevenue),
                subtitle: CurrencyFormatter.formatEGP(kpis.totalRevenue),
                icon: Icons.payments_rounded,
                growthPct: kpis.revenueGrowthPct,
                badgeLabel: _formatSignedPct(kpis.revenueMomPct, 'شهري MoM'),
                secondaryBadgeLabel: _formatSignedPct(kpis.revenueYoyPct, 'سنوي YoY'),
                isPositive: kpis.revenueMomPct >= 0,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                title: 'إجمالي الوحدات المباعة',
                value: CurrencyFormatter.formatCompactUnits(kpis.totalUnitsSold),
                subtitle: '${CurrencyFormatter.formatUnits(kpis.totalUnitsSold)} عبوة',
                icon: Icons.inventory_2_rounded,
                growthPct: kpis.unitsGrowthPct,
                badgeLabel: _formatSignedPct(kpis.unitsMomPct, 'شهري MoM'),
                secondaryBadgeLabel: _formatSignedPct(kpis.unitsYoyPct, 'سنوي YoY'),
                isPositive: kpis.unitsMomPct >= 0,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                title: 'الفروع النشطة المغطاة',
                value: '${kpis.activeStoresCount} فرع',
                subtitle: _buildActiveBranchesSubtitle(),
                icon: Icons.store_rounded,
                growthPct: 0.0,
                badgeLabel: kpis.activeStoresCount > 0 ? 'تغطية 100%' : 'تم التصفير (0 فرع)',
                secondaryBadgeLabel: kpis.tenantMarketSharePct > 0
                    ? 'الحصة السوقية: ${kpis.tenantMarketSharePct.toStringAsFixed(2)}% • ${kpis.totalSkusCount} صنف'
                    : null,
                isPositive: true,
                usePrimaryBadge: true,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                title: 'نسبة النواقص (OOS Rate)',
                value: '${kpis.oosRatePct.toStringAsFixed(1)}%',
                subtitle: 'خسارة تقديرية: ${CurrencyFormatter.formatCompactEGP(kpis.estimatedLostRevenue)}',
                icon: Icons.warning_amber_rounded,
                growthPct: -kpis.oosRatePct,
                badgeLabel: 'توافر الرفوف OSA: ${kpis.osaRatePct.toStringAsFixed(1)}%',
                secondaryBadgeLabel: 'نسبة النواقص (OOS Rate): ${kpis.oosRatePct.toStringAsFixed(1)}% • ${kpis.totalOOSIncidents} صنف ناقص',
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

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final double growthPct;
  final String badgeLabel;
  final String? secondaryBadgeLabel;
  final bool isPositive;
  final bool isAlert;
  final bool usePrimaryBadge;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.growthPct,
    required this.badgeLabel,
    this.secondaryBadgeLabel,
    required this.isPositive,
    this.isAlert = false,
    this.usePrimaryBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color badgeBg;
    final Color badgeFg;

    if (isAlert) {
      badgeBg = colorScheme.errorContainer;
      badgeFg = colorScheme.onErrorContainer;
    } else if (usePrimaryBadge) {
      badgeBg = colorScheme.primaryContainer;
      badgeFg = colorScheme.onPrimaryContainer;
    } else if (isPositive) {
      badgeBg = colorScheme.secondaryContainer;
      badgeFg = colorScheme.onSecondaryContainer;
    } else {
      badgeBg = colorScheme.errorContainer;
      badgeFg = colorScheme.onErrorContainer;
    }

    return Card(
      child: Padding(
        padding: M3Spacing.pSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: isAlert
                        ? colorScheme.errorContainer.withOpacity(0.4)
                        : colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Icon(
                    icon,
                    size: 20.0,
                    color: isAlert ? colorScheme.error : colorScheme.primary,
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      badgeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: badgeFg,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            M3Spacing.gapSM,
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4.0),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isAlert ? colorScheme.error : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (secondaryBadgeLabel != null) ...[
              const SizedBox(height: 6.0),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                decoration: BoxDecoration(
                  color: isAlert
                      ? colorScheme.errorContainer.withOpacity(0.65)
                      : colorScheme.primaryContainer.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  secondaryBadgeLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isAlert
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

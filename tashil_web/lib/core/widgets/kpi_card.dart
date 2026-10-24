import 'package:flutter/material.dart';
import '../theme/m3_shape.dart';
import '../theme/m3_spacing.dart';

/// Unified M3 KPI card (outlined card, tonal icon container, status badges).
///
/// Use this for every KPI tile in the app.
class KpiCard extends StatelessWidget {
  final String title;
  final String titleEn;
  final String value;
  final String subtitle;
  final IconData icon;
  final double growthPct;
  final String badgeLabel;
  final String? badgeLabelEn;
  final String? secondaryBadgeLabel;
  final String? secondaryBadgeLabelEn;
  final bool isPositive;
  final bool isAlert;
  final bool usePrimaryBadge;

  const KpiCard({
    super.key,
    required this.title,
    required this.titleEn,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.growthPct,
    required this.badgeLabel,
    this.badgeLabelEn,
    this.secondaryBadgeLabel,
    this.secondaryBadgeLabelEn,
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

    return Card.outlined(
      child: Padding(
        padding: M3Spacing.pSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(M3Spacing.xs),
                  decoration: BoxDecoration(
                    color: isAlert
                        ? colorScheme.errorContainer.withOpacity(0.4)
                        : colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: M3Shape.radiusSm,
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
                      borderRadius: M3Shape.radiusSm,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          badgeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: badgeFg,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (badgeLabelEn != null)
                          Text(
                            badgeLabelEn!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeFg.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            M3Spacing.gapSM,
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2.0),
            Text(
              titleEn,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isAlert ? colorScheme.error : colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6.0),
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
                  borderRadius: M3Shape.radiusSm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secondaryBadgeLabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isAlert
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (secondaryBadgeLabelEn != null)
                      Text(
                        secondaryBadgeLabelEn!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: (isAlert
                                  ? colorScheme.onErrorContainer
                                  : colorScheme.onPrimaryContainer)
                              .withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

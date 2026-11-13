import 'package:flutter/material.dart';
import '../theme/m3_spacing.dart';
import 'app_icons.dart';
import 'm3_status_tag.dart';

/// Unified M3 KPI card: outlined card, icon + title row, value, subtitle and
/// neutral/error status tags. Use this for every KPI tile in the app.
///
/// [titleEn], [badgeLabelEn], [secondaryBadgeLabelEn] and [usePrimaryBadge]
/// are kept for API compatibility but are no longer rendered: the M3 card is
/// Arabic-only and its tags use calm neutral roles (≥ 4.5:1).
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
    this.titleEn = '',
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
    final cs = theme.colorScheme;
    final badgeTone =
        isAlert || !isPositive ? M3StatusTone.error : M3StatusTone.neutral;

    return Card.outlined(
      child: Padding(
        padding: M3Spacing.pSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20.0,
                  color: isAlert ? cs.error : cs.onSurfaceVariant,
                ),
                M3Spacing.gapXS,
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            M3Spacing.gapXS,
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: isAlert ? cs.error : cs.onSurface,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            M3Spacing.gapXS,
            Wrap(
              spacing: M3Spacing.xs,
              runSpacing: M3Spacing.xs,
              children: [
                if (badgeLabel.isNotEmpty)
                  M3StatusTag(
                    label: badgeLabel,
                    tone: badgeTone,
                    icon: isAlert
                        ? AppIcons.warning
                        : (isPositive
                            ? AppIcons.trendingUp
                            : AppIcons.trendingDown),
                  ),
                if (secondaryBadgeLabel != null)
                  M3StatusTag(
                    label: secondaryBadgeLabel!,
                    tone: isAlert ? M3StatusTone.error : M3StatusTone.neutral,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

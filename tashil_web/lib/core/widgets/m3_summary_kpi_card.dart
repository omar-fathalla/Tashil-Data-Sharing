import 'package:flutter/material.dart';

import '../theme/m3_shape.dart';
import '../theme/m3_spacing.dart';
import 'm3_section_title.dart';
import 'm3_states.dart';

/// Geometry and type roles of the summary KPI card used on Sell-Out (the
/// reference) and every page that mirrors it (Compare, ...). Pages must use
/// [M3SummaryKpiCard] instead of per-page paddings, icon sizes or fonts.
abstract final class M3SummaryKpiStyle {
  static const EdgeInsets padding = EdgeInsets.all(16.0);
  static const BorderRadius radius = M3Shape.radiusLg;
  static const EdgeInsets iconPadding = EdgeInsets.all(8.0);
  static const BorderRadius iconRadius = M3Shape.radiusMd;
  static const double iconSize = 20.0;
  static const double iconGap = 8.0;
  static const double valueGap = 4.0;

  /// Title: [M3SectionTitle] (titleMedium).
  static TextStyle? titleStyle(BuildContext context) =>
      M3SectionTitle.styleOf(context);

  /// Numeric value: headlineSmall w900 (text values: titleLarge w700).
  static TextStyle? valueStyle(BuildContext context, {bool textValue = false}) {
    final t = Theme.of(context).textTheme;
    return (textValue ? t.titleLarge : t.headlineSmall)?.copyWith(
      fontWeight: textValue ? FontWeight.w700 : FontWeight.w900,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  /// Fixed line box for a text role. Glyphs the page font lacks (▲ ▼ on
  /// Compare) are drawn by a fallback font with another ascent / descent
  /// split, which made mixed lines taller (Compare 141px vs Sell-Out 138px
  /// live, v137). Forcing the strut keeps every line at the role's height.
  static StrutStyle? strut(TextStyle? style) => style == null
      ? null
      : StrutStyle.fromTextStyle(style, forceStrutHeight: true);

  /// Detail line: bodySmall onSurfaceVariant.
  static TextStyle? subtitleStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
}

/// Outlined summary KPI card: tinted icon + title row, value, detail line.
class M3SummaryKpiCard extends StatelessWidget {
  const M3SummaryKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.textValue = false,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
    this.titleTooltip,
    this.isLoading = false,
    this.titleKey,
    this.valueKey,
    this.subtitleKey,
    this.loadingKey,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool textValue;

  /// null = wrap freely (never ellipsized).
  final int? titleMaxLines;
  final int subtitleMaxLines;
  /// Optional tooltip with the full wording when the visible title is shortened.
  final String? titleTooltip;
  final bool isLoading;
  final Key? titleKey;
  final Key? valueKey;
  final Key? subtitleKey;
  final Key? loadingKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final valueStyle =
        M3SummaryKpiStyle.valueStyle(context, textValue: textValue);
    final subtitleStyle = M3SummaryKpiStyle.subtitleStyle(context);
    return Container(
      padding: M3SummaryKpiStyle.padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3SummaryKpiStyle.radius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: M3SummaryKpiStyle.iconPadding,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: M3SummaryKpiStyle.iconRadius,
                ),
                child: Icon(icon,
                    color: color, size: M3SummaryKpiStyle.iconSize),
              ),
              const SizedBox(width: M3SummaryKpiStyle.iconGap),
              Expanded(
                child: titleTooltip == null
                    ? M3SectionTitle(
                        title,
                        key: titleKey,
                        maxLines: titleMaxLines,
                        overflow: titleMaxLines == null
                            ? null
                            : TextOverflow.ellipsis,
                      )
                    : Tooltip(
                        message: titleTooltip,
                        child: M3SectionTitle(
                          title,
                          key: titleKey,
                          maxLines: titleMaxLines,
                          overflow: titleMaxLines == null
                              ? null
                              : TextOverflow.ellipsis,
                        ),
                      ),
              ),
            ],
          ),
          M3Spacing.gapSM,
          if (isLoading) ...[
            M3SkeletonBox(key: loadingKey, width: 120.0, height: 28.0),
            const SizedBox(height: M3SummaryKpiStyle.valueGap),
            const M3SkeletonBox(width: 180.0, height: 12.0),
          ] else ...[
            // Up to 2 lines; the full value is always in the tooltip.
            Tooltip(
              message: value,
              child: Text(
                value,
                key: valueKey,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
                strutStyle: M3SummaryKpiStyle.strut(valueStyle),
              ),
            ),
            const SizedBox(height: M3SummaryKpiStyle.valueGap),
            Text(
              subtitle,
              key: subtitleKey,
              maxLines: subtitleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
              strutStyle: M3SummaryKpiStyle.strut(subtitleStyle),
            ),
          ],
        ],
      ),
    );
  }
}

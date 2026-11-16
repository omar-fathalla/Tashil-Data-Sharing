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

  /// Detail line: bodySmall onSurfaceVariant. Kept on bodySmall so cards with
  /// [subtitleMaxLines] > 1 (Compare / Returns) stay at the Sell-Out 138px
  /// height; chip-under captions use [M3ChipStyle.captionStyle] (bodyMedium).
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
    this.valueMaxLines = 2,
    this.shrinkOverflowingValue = false,
    this.titleTooltip,
    this.subtitleTooltip,
    this.cardTooltip,
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

  /// Value line count. The shared default is 2. A card that must stay one
  /// line (a long product name beside numeric KPIs) passes 1.
  final int valueMaxLines;

  /// When the value is one line and does not fit at the role size, step the
  /// font down slightly. The line box stays the role's strut, so the card
  /// height matches the other cards in the row.
  final bool shrinkOverflowingValue;
  /// Optional tooltip with the full wording when the visible title is shortened.
  final String? titleTooltip;
  /// Optional tooltip with the full wording when the visible subtitle is shortened.
  final String? subtitleTooltip;
  /// Optional tooltip for the whole card (hover anywhere, including the value).
  /// When set, inner title/value/subtitle tooltips are skipped so they do not
  /// swallow the pointer and hide this message.
  final String? cardTooltip;
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
    final useCardTooltip = cardTooltip != null && cardTooltip!.isNotEmpty;
    final card = Container(
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
                child: useCardTooltip || titleTooltip == null
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
            // Up to [valueMaxLines] (shared default 2). The full value is in
            // the tooltip unless a card-level tooltip (e.g. ROMI method)
            // covers the whole card.
            _kpiValue(
              value: value,
              valueKey: valueKey,
              style: valueStyle,
              maxLines: valueMaxLines,
              shrinkToFit: shrinkOverflowingValue && valueMaxLines == 1,
              showTooltip: !useCardTooltip,
            ),
            const SizedBox(height: M3SummaryKpiStyle.valueGap),
            useCardTooltip || subtitleTooltip == null
                ? Text(
                    subtitle,
                    key: subtitleKey,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                    strutStyle: M3SummaryKpiStyle.strut(subtitleStyle),
                  )
                : Tooltip(
                    message: subtitleTooltip,
                    child: Text(
                      subtitle,
                      key: subtitleKey,
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                      strutStyle: M3SummaryKpiStyle.strut(subtitleStyle),
                    ),
                  ),
          ],
        ],
      ),
    );
    if (!useCardTooltip) return card;
    return Tooltip(
      message: cardTooltip!,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 8),
      preferBelow: true,
      constraints: const BoxConstraints(maxWidth: 360),
      child: card,
    );
  }
}

/// Next on-scale step under a text value (titleLarge 22 → titleMedium 16).
/// The original strut keeps the line box, so the card height does not change.
const double _kShrunkValueFontSize = 16.0;

Widget _kpiValue({
  required String value,
  required Key? valueKey,
  required TextStyle? style,
  required int maxLines,
  required bool shrinkToFit,
  required bool showTooltip,
}) {
  final Widget text = shrinkToFit
      ? _OneLineKpiValue(value: value, style: style, valueKey: valueKey)
      : Text(
          value,
          key: valueKey,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
          strutStyle: M3SummaryKpiStyle.strut(style),
        );
  if (!showTooltip) return text;
  return Tooltip(message: value, child: text);
}

/// Single-line value. When [style] does not fit the card, the font steps
/// down to [_kShrunkValueFontSize] and the rest is an ellipsis. Hover shows
/// the full string via the surrounding tooltip. The strut stays the role's,
/// so the card is the same height as a one-line sibling.
class _OneLineKpiValue extends StatelessWidget {
  const _OneLineKpiValue({
    required this.value,
    required this.style,
    required this.valueKey,
  });

  final String value;
  final TextStyle? style;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final role = style;
        var fitted = role;
        final size = role?.fontSize;
        final maxW = constraints.maxWidth;
        if (role != null &&
            size != null &&
            size > _kShrunkValueFontSize &&
            maxW.isFinite &&
            maxW > 0 &&
            _overflows(context, value, role, maxW)) {
          fitted = role.copyWith(fontSize: _kShrunkValueFontSize);
        }
        return Text(
          value,
          key: valueKey,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: fitted,
          strutStyle: M3SummaryKpiStyle.strut(role),
        );
      },
    );
  }

  static bool _overflows(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }
}

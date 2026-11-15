import 'package:flutter/material.dart';

import '../theme/m3_shape.dart';
import '../theme/m3_typography.dart';

/// One chip shape for every chip-like element on a page: the M3 filter-chip
/// container (8dp corner radius, 32dp minimum height, 8dp horizontal padding).
/// Colours stay by function (neutral / tonal / primary); only the shape,
/// height and padding are shared. [M3StatusTag] uses the same tokens.
abstract final class M3ChipStyle {
  static const BorderRadius radius = M3Shape.radiusSm;
  static const double minHeight = 32.0;
  static const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 8.0);

  /// In-chip label: same size/weight as Errors type/status short chips.
  static TextStyle? labelStyle(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontSize: M3FontSize.labelSmallPlus,
            fontWeight: FontWeight.w800,
          );

  /// Caption under a short chip (type / status description). Matches the
  /// page-header subtitle role ([bodyMedium] + onSurfaceVariant) so recent
  /// chip+description strips are not smaller than Sell-Out / header copy.
  static TextStyle? captionStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
}

/// Static (non-interactive) chip container with [M3ChipStyle] geometry.
class M3ChipSurface extends StatelessWidget {
  const M3ChipSurface({
    super.key,
    required this.color,
    required this.child,
    this.borderColor,
    this.borderWidth = 1.0,
  });

  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: M3ChipStyle.radius,
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!, width: borderWidth),
      ),
      textStyle: DefaultTextStyle.of(context).style,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: M3ChipStyle.minHeight),
        child: Padding(
          padding: M3ChipStyle.padding,
          child: Center(widthFactor: 1.0, heightFactor: 1.0, child: child),
        ),
      ),
    );
  }
}

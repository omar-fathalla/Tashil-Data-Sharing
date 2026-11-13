import 'package:flutter/material.dart';

import 'm3_chip_surface.dart';
import '../theme/m3_status_colors.dart';

/// Compact status / category tag using theme roles (no raw hex in features).
///
/// Neutral = outlined chip look (surfaceContainerLowest + outlineVariant
/// border, onSurfaceVariant text, ≈ 9.4:1); info = secondaryContainer (the
/// one highlighted item); error = errorContainer.
class M3StatusTag extends StatelessWidget {
  const M3StatusTag({
    super.key,
    required this.label,
    this.tone = M3StatusTone.neutral,
    this.color,
    this.onColor,
    this.icon,
  });

  final String label;
  final M3StatusTone tone;
  final Color? color;
  final Color? onColor;

  /// Optional leading icon (18dp) so status is not conveyed by colour alone.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = M3StatusColors.of(context);
    final (Color bg, Color fg, Color? border) = switch (tone) {
      M3StatusTone.success => (
          status.successContainer,
          status.onSuccessContainer,
          null
        ),
      M3StatusTone.warning => (
          status.warningContainer,
          status.onWarningContainer,
          null
        ),
      M3StatusTone.error => (cs.errorContainer, cs.onErrorContainer, null),
      M3StatusTone.info => (
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          null
        ),
      M3StatusTone.neutral => (
          cs.surfaceContainerLowest,
          cs.onSurfaceVariant,
          cs.outlineVariant
        ),
    };
    final useBorder = border != null && color == null;
    return Material(
      color: color ?? bg,
      shape: RoundedRectangleBorder(
        borderRadius: M3ChipStyle.radius,
        side: useBorder ? BorderSide(color: border) : BorderSide.none,
      ),
      // Shared chip geometry (8dp radius, 32dp min height); centred content.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: M3ChipStyle.minHeight),
        child: Padding(
          padding: M3ChipStyle.padding,
          child: Center(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: _content(theme, onColor ?? fg),
          ),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, Color fg) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(color: fg),
    );
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18.0, color: fg),
        const SizedBox(width: 4.0),
        Flexible(child: text),
      ],
    );
  }
}

enum M3StatusTone { success, warning, error, info, neutral }

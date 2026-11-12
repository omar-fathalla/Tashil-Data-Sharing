import 'package:flutter/material.dart';

import '../theme/m3_shape.dart';
import '../theme/m3_status_colors.dart';

/// Compact status / category tag using theme roles (no raw hex in features).
class M3StatusTag extends StatelessWidget {
  const M3StatusTag({
    super.key,
    required this.label,
    this.tone = M3StatusTone.neutral,
    this.color,
    this.onColor,
  });

  final String label;
  final M3StatusTone tone;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = M3StatusColors.of(context);
    final (bg, fg) = switch (tone) {
      M3StatusTone.success => (status.successContainer, status.onSuccessContainer),
      M3StatusTone.warning => (status.warningContainer, status.onWarningContainer),
      M3StatusTone.error => (cs.errorContainer, cs.onErrorContainer),
      M3StatusTone.info => (status.infoContainer, status.onInfoContainer),
      M3StatusTone.neutral => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color ?? bg,
        borderRadius: M3Shape.radiusSm,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: onColor ?? fg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

enum M3StatusTone { success, warning, error, info, neutral }

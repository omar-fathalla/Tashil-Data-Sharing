import 'package:flutter/material.dart';

import '../../../../core/theme/m3_status_colors.dart';
import '../../../../core/widgets/m3_chip_surface.dart';
import '../../domain/target_achievement_status.dart';

/// Compact status pill: icon + Arabic label for the Targets redesign.
class TargetStatusPill extends StatelessWidget {
  const TargetStatusPill({
    super.key,
    required this.status,
    this.compact = false,
  });

  final TargetAchievementStatus status;
  final bool compact;

  /// Short table-safe status words so «63.6% · أقل» fits at 1280 without
  /// ellipsis; full [status.labelAr] stays on the tooltip.
  static String compactStatusWord(TargetAchievementKind kind) {
    switch (kind) {
      case TargetAchievementKind.achieved:
        return 'محقق';
      case TargetAchievementKind.near:
        return 'قريب';
      case TargetAchievementKind.below:
        return 'أقل';
      case TargetAchievementKind.noData:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accents = M3StatusColors.of(context).accents;
    final Color color;
    final IconData icon;
    switch (status.kind) {
      case TargetAchievementKind.achieved:
        color = accents.positive;
        icon = Icons.check_circle_rounded;
      case TargetAchievementKind.near:
        color = accents.caution;
        icon = Icons.timelapse_rounded;
      case TargetAchievementKind.below:
        color = cs.error;
        icon = Icons.warning_amber_rounded;
      case TargetAchievementKind.noData:
        color = cs.onSurfaceVariant;
        icon = Icons.hourglass_empty_rounded;
    }
    // Table cells keep a short «—» when there are no sales; detail cards
    // can pass a richer label via [status.labelAr] when pct is null but
    // kind is not noData (unused today).
    final String label;
    final String? tip;
    if (status.kind == TargetAchievementKind.noData) {
      label = '—';
      tip = status.labelAr;
    } else if (status.pct == null) {
      label = status.labelAr;
      tip = null;
    } else if (compact) {
      label = '${status.pct!.toStringAsFixed(1)}% · ${compactStatusWord(status.kind)}';
      tip = status.labelAr;
    } else {
      label = '${status.pct!.toStringAsFixed(1)}% · ${status.labelAr}';
      tip = null;
    }
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
          fontSize: compact ? 11 : null,
        );
    final chip = M3ChipSurface(
      color: color.withOpacity(0.12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: color),
          SizedBox(width: compact ? 4 : 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
        ],
      ),
    );
    if (tip == null || tip == label) return chip;
    return Tooltip(message: tip, child: chip);
  }
}

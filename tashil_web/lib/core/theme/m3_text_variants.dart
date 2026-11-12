import 'package:flutter/painting.dart';

import 'm3_typography.dart';

/// Named, colourless text variants for dense dashboard components.
///
/// Prefer `Theme.of(context).textTheme` roles. Heavy (w800) variants are
/// deprecated — use w500/w600 (emphasized) only.
abstract final class M3TextVariants {
  // 11.0 — labelSmall
  @Deprecated('use textTheme.labelSmall with FontWeight.w600')
  static const TextStyle microHeavy =
      TextStyle(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w600);

  // 11.5 — dense table header / cell label (maps toward labelSmall)
  @Deprecated('use textTheme.labelSmall')
  static const TextStyle denseLabel =
      TextStyle(fontSize: M3FontSize.labelSmall);
  @Deprecated('use textTheme.labelSmall with FontWeight.w600')
  static const TextStyle denseLabelSemi =
      TextStyle(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w600);
  @Deprecated('use textTheme.labelSmall with FontWeight.w600')
  static const TextStyle denseLabelBold =
      TextStyle(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w600);
  @Deprecated('use textTheme.labelSmall with FontWeight.w600')
  static const TextStyle denseLabelHeavy =
      TextStyle(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w600);

  // 12.0 — bodySmall table cell
  static const TextStyle cell = TextStyle(fontSize: M3FontSize.bodySmall);
  static const TextStyle cellSemi =
      TextStyle(fontSize: M3FontSize.bodySmall, fontWeight: FontWeight.w600);
  @Deprecated('use cellSemi (w600)')
  static const TextStyle cellHeavy =
      TextStyle(fontSize: M3FontSize.bodySmall, fontWeight: FontWeight.w600);

  // Emphasised cell / chip → labelLarge 14
  @Deprecated('use textTheme.labelLarge')
  static const TextStyle cellPlusBold =
      TextStyle(fontSize: M3FontSize.bodyMedium, fontWeight: FontWeight.w600);
  @Deprecated('use textTheme.labelLarge')
  static const TextStyle cellPlusHeavy =
      TextStyle(fontSize: M3FontSize.bodyMedium, fontWeight: FontWeight.w600);

  // Compact label → titleSmall / labelLarge 14
  @Deprecated('use textTheme.labelLarge')
  static const TextStyle compactLabel =
      TextStyle(fontSize: M3FontSize.bodyMedium);
  @Deprecated('use textTheme.labelLarge with FontWeight.w600')
  static const TextStyle compactLabelBold =
      TextStyle(fontSize: M3FontSize.bodyMedium, fontWeight: FontWeight.w600);
  @Deprecated('use textTheme.labelLarge with FontWeight.w600')
  static const TextStyle compactLabelHeavy =
      TextStyle(fontSize: M3FontSize.bodyMedium, fontWeight: FontWeight.w600);

  @Deprecated('use textTheme.titleSmall')
  static const TextStyle titleCompactBold =
      TextStyle(fontSize: M3FontSize.bodyMedium, fontWeight: FontWeight.w600);
  @Deprecated('use textTheme.titleSmall')
  static const TextStyle titleDenseBold =
      TextStyle(fontSize: M3FontSize.bodyMedium, fontWeight: FontWeight.w600);
}

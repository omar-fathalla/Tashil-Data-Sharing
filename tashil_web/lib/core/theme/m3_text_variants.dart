import 'package:flutter/painting.dart';

import 'm3_typography.dart';

/// Named, colourless text variants for dense dashboard components (table
/// headers/cells, buttons, chips, tabs, tooltips, dropdown items, inputs).
///
/// Each variant carries only size + weight, so it merges onto the host
/// component's own default style and keeps that component's colour, font
/// family, letter spacing and height. Sizes follow the M3 type scale
/// (labelSmall 11 / bodySmall 12) plus the dense intermediate steps.
/// Add a colour at the call site with `.copyWith(color: …)` when needed.
abstract final class M3TextVariants {
  // 11.0 — labelSmall
  static const TextStyle microHeavy =
      TextStyle(fontSize: M3FontSize.labelSmall, fontWeight: FontWeight.w800);

  // 11.5 — dense table header / cell label
  static const TextStyle denseLabel =
      TextStyle(fontSize: M3FontSize.labelSmallPlus);
  static const TextStyle denseLabelSemi =
      TextStyle(fontSize: M3FontSize.labelSmallPlus, fontWeight: FontWeight.w600);
  static const TextStyle denseLabelBold =
      TextStyle(fontSize: M3FontSize.labelSmallPlus, fontWeight: FontWeight.w700);
  static const TextStyle denseLabelHeavy =
      TextStyle(fontSize: M3FontSize.labelSmallPlus, fontWeight: FontWeight.w800);

  // 12.0 — bodySmall table cell
  static const TextStyle cell = TextStyle(fontSize: M3FontSize.bodySmall);
  static const TextStyle cellSemi =
      TextStyle(fontSize: M3FontSize.bodySmall, fontWeight: FontWeight.w600);
  static const TextStyle cellHeavy =
      TextStyle(fontSize: M3FontSize.bodySmall, fontWeight: FontWeight.w800);

  // 12.5 — emphasised cell / chip
  static const TextStyle cellPlusBold =
      TextStyle(fontSize: M3FontSize.bodySmallPlus, fontWeight: FontWeight.w700);
  static const TextStyle cellPlusHeavy =
      TextStyle(fontSize: M3FontSize.bodySmallPlus, fontWeight: FontWeight.w800);

  // 13.0 — compact label (dropdown items, buttons, inputs)
  static const TextStyle compactLabel =
      TextStyle(fontSize: M3FontSize.labelMediumPlus);
  static const TextStyle compactLabelBold =
      TextStyle(fontSize: M3FontSize.labelMediumPlus, fontWeight: FontWeight.w700);
  static const TextStyle compactLabelHeavy =
      TextStyle(fontSize: M3FontSize.labelMediumPlus, fontWeight: FontWeight.w800);

  // 13.5 / 14.5 — compact titles
  static const TextStyle titleCompactBold =
      TextStyle(fontSize: M3FontSize.bodyCompact, fontWeight: FontWeight.w700);
  static const TextStyle titleDenseBold =
      TextStyle(fontSize: M3FontSize.bodyMediumPlus, fontWeight: FontWeight.w700);
}

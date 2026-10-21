import 'package:flutter/widgets.dart';

/// Mandatory Material Design 3 (M3) 8dp Baseline Spacing Scale.
/// Strictly enforces multiples of 8 (with 4dp for micro-alignments).
class M3Spacing {
  M3Spacing._();

  /// 4.0dp - Micro alignment (badges, icon offsets, compact labels)
  static const double xxs = 4.0;

  /// 8.0dp - Tight spacing (compact list items, chip margins)
  static const double xs = 8.0;

  /// 16.0dp - Standard card padding, compact grid gutter
  static const double sm = 16.0;

  /// 24.0dp - Section padding, medium/expanded gutter, dialog interior
  static const double md = 24.0;

  /// 32.0dp - Large container padding, hero margins
  static const double lg = 32.0;

  /// 40.0dp - Prominent desktop spacing
  static const double xl = 40.0;

  /// 48.0dp - Minimum accessible touch target, large hero padding
  static const double xxl = 48.0;

  /// 64.0dp - Extra-large display outer margins
  static const double xxxl = 64.0;

  // Convenient EdgeInsets
  static const EdgeInsets pXs = EdgeInsets.all(xs);
  static const EdgeInsets pSm = EdgeInsets.all(sm);
  static const EdgeInsets pMd = EdgeInsets.all(md);
  static const EdgeInsets pLg = EdgeInsets.all(lg);

  static const EdgeInsets pHSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets pHMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets pHLg = EdgeInsets.symmetric(horizontal: lg);

  static const EdgeInsets pVSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets pVMd = EdgeInsets.symmetric(vertical: md);

  // Convenient Gap / SizedBox widgets
  static const SizedBox gapXXS = SizedBox(width: xxs, height: xxs);
  static const SizedBox gapXS = SizedBox(width: xs, height: xs);
  static const SizedBox gapSM = SizedBox(width: sm, height: sm);
  static const SizedBox gapMD = SizedBox(width: md, height: md);
  static const SizedBox gapLG = SizedBox(width: lg, height: lg);
  static const SizedBox gapXL = SizedBox(width: xl, height: xl);

  static const SizedBox hGapXS = SizedBox(width: xs);
  static const SizedBox hGapSM = SizedBox(width: sm);
  static const SizedBox hGapMD = SizedBox(width: md);
}

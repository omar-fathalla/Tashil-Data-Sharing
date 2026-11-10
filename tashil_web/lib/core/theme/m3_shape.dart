import 'package:flutter/material.dart';

/// Material Design 3 shape scale (corner radius tokens).
///
/// Use these instead of ad-hoc `BorderRadius.circular(n)` values.
class M3Shape {
  M3Shape._();

  /// 0dp - None
  static const double none = 0.0;

  /// 4dp - Extra small (badges, tooltips, snackbars)
  static const double xs = 4.0;

  /// 8dp - Small (chips, menus items, small containers)
  static const double sm = 8.0;

  /// 12dp - Medium (cards, text fields, menus)
  static const double md = 12.0;

  /// 16dp - Large (large cards, navigation drawer, side sheets)
  static const double lg = 16.0;

  /// 20dp - Large increased
  static const double largeIncreased = 20.0;

  /// 28dp - Extra large (dialogs, bottom sheets, date pickers)
  static const double xl = 28.0;

  /// 32dp - Extra large increased
  static const double extraLargeIncreased = 32.0;

  /// 48dp - Extra extra large
  static const double extraExtraLarge = 48.0;

  /// 999dp - Full (pill buttons, FABs, segmented buttons, indicators)
  static const double full = 999.0;

  static const BorderRadius radiusXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius radiusLargeIncreased =
      BorderRadius.all(Radius.circular(largeIncreased));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius radiusExtraLargeIncreased =
      BorderRadius.all(Radius.circular(extraLargeIncreased));
  static const BorderRadius radiusExtraExtraLarge =
      BorderRadius.all(Radius.circular(extraExtraLarge));
  static const BorderRadius radiusFull = BorderRadius.all(Radius.circular(full));

  static const RoundedRectangleBorder shapeXs =
      RoundedRectangleBorder(borderRadius: radiusXs);
  static const RoundedRectangleBorder shapeSm =
      RoundedRectangleBorder(borderRadius: radiusSm);
  static const RoundedRectangleBorder shapeMd =
      RoundedRectangleBorder(borderRadius: radiusMd);
  static const RoundedRectangleBorder shapeLg =
      RoundedRectangleBorder(borderRadius: radiusLg);
  static const RoundedRectangleBorder shapeXl =
      RoundedRectangleBorder(borderRadius: radiusXl);
}

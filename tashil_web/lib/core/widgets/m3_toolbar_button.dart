import 'package:flutter/material.dart';

import '../theme/m3_shape.dart';

/// One geometry for every 40dp control (filter buttons, toolbar / page-action
/// buttons such as Export, Print, Upload, sort toggles, segmented buttons):
/// 40dp tall, full-round [StadiumBorder] corners (F1, owner decision: one
/// shape on every page, matching the app theme's button family) and 18dp
/// icons. Chips keep their 8dp [M3ChipStyle.radius]. Colour roles
/// (filled / tonal / outlined) stay per button.
abstract final class M3ToolbarButton {
  static const double height = 40.0;
  static const double iconSize = 18.0;
  static const OutlinedBorder shape = StadiumBorder();

  /// Corner radius for hand-built 40dp controls (InkWell + decoration) so
  /// they match [shape].
  static const BorderRadius radius = M3Shape.radiusFull;

  static const ButtonStyle style = ButtonStyle(
    shape: WidgetStatePropertyAll(shape),
    minimumSize: WidgetStatePropertyAll(Size(0.0, height)),
    maximumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    iconSize: WidgetStatePropertyAll(iconSize),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16.0)),
  );
}

/// Applies [M3ToolbarButton.style] to every Filled / Outlined / Elevated /
/// Text button below it, so a whole page shares one button shape without
/// per-call `styleFrom` overrides.
class M3ToolbarButtonTheme extends StatelessWidget {
  const M3ToolbarButtonTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const s = M3ToolbarButton.style;
    return Theme(
      data: t.copyWith(
        filledButtonTheme:
            FilledButtonThemeData(style: s.merge(t.filledButtonTheme.style)),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: s.merge(t.outlinedButtonTheme.style)),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: s.merge(t.elevatedButtonTheme.style)),
        textButtonTheme:
            TextButtonThemeData(style: s.merge(t.textButtonTheme.style)),
      ),
      child: child,
    );
  }
}

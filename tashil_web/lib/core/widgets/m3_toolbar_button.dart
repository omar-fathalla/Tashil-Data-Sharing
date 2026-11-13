import 'package:flutter/material.dart';

import 'm3_chip_surface.dart';

/// One geometry for toolbar / page-action buttons (filter bars, Export,
/// Print, Upload, sort toggles): 40dp tall, 8dp corners — the same
/// [M3ChipStyle.radius] the dashboard's [M3MenuFilter] buttons use — and
/// 18dp icons. Colour roles (filled / tonal / outlined) stay per button.
abstract final class M3ToolbarButton {
  static const double height = 40.0;
  static const double iconSize = 18.0;
  static const OutlinedBorder shape =
      RoundedRectangleBorder(borderRadius: M3ChipStyle.radius);

  static const ButtonStyle style = ButtonStyle(
    shape: WidgetStatePropertyAll(shape),
    minimumSize: WidgetStatePropertyAll(Size(0.0, height)),
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

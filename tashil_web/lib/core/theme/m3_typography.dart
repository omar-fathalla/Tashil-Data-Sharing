import 'package:flutter/material.dart';

/// Font-size tokens aligned to the Material 3 type scale.
///
/// Prefer `Theme.of(context).textTheme.<role>` for new code. Out-of-scale
/// "Plus"/micro helpers remain only for gradual migration and are deprecated.
abstract final class M3FontSize {
  @Deprecated('use textTheme.labelSmall (11)')
  static const double micro = 9.0;
  @Deprecated('use textTheme.labelSmall (11)')
  static const double microPlus = 9.5;
  @Deprecated('use textTheme.labelSmall (11)')
  static const double tiny = 10.0;
  @Deprecated('use textTheme.labelSmall (11)')
  static const double tinyPlus = 10.5;

  static const double labelSmall = 11.0;
  @Deprecated('use textTheme.labelSmall (11) or labelMedium (12)')
  static const double labelSmallPlus = 11.5;
  static const double bodySmall = 12.0;
  @Deprecated('use textTheme.bodySmall (12) or labelLarge (14)')
  static const double bodySmallPlus = 12.5;
  @Deprecated('use textTheme.labelLarge / titleSmall (14)')
  static const double labelMediumPlus = 13.0;
  @Deprecated('use textTheme.bodyMedium (14)')
  static const double bodyCompact = 13.5;
  static const double bodyMedium = 14.0;
  @Deprecated('use textTheme.bodyMedium (14) or bodyLarge (16)')
  static const double bodyMediumPlus = 14.5;
  @Deprecated('use textTheme.bodyLarge (16)')
  static const double bodyMediumLarge = 15.0;
  @Deprecated('use textTheme.bodyLarge (16)')
  static const double bodyMediumLargePlus = 15.5;
  static const double bodyLarge = 16.0;
  @Deprecated('use textTheme.titleLarge (22) or titleMedium (16)')
  static const double titleMediumPlus = 18.0;
  static const double headlineSmall = 24.0;
  static const double headlineMedium = 28.0;
  @Deprecated('use textTheme.displayLarge (57)')
  static const double displayHero = 68.0;
}

/// Bundled CanvasKit fallback for glyphs Cairo does not ship.
///
/// Flutter web (CanvasKit) will not use the browser's system fonts, so ▲ ▼
/// (U+25B2 / U+25BC) painted as .notdef tofu on Compare and chart callouts
/// until this family is registered in pubspec and applied as
/// [fontFamilyFallback]. U+2066…U+2069 are in the same font as zero-advance
/// glyphs so LRI/PDI isolates never paint a box.
abstract final class AppFontFallback {
  static const symbolFamily = 'NotoSansSymbols2';
  static const families = <String>[symbolFamily];

  static TextStyle applyStyle(TextStyle style) {
    final existing = style.fontFamilyFallback ?? const <String>[];
    if (existing.contains(symbolFamily)) return style;
    return style.copyWith(
      fontFamilyFallback: [...existing, symbolFamily],
    );
  }

  static TextTheme apply(TextTheme theme) {
    TextStyle? f(TextStyle? s) => s == null ? null : applyStyle(s);
    return theme.copyWith(
      displayLarge: f(theme.displayLarge),
      displayMedium: f(theme.displayMedium),
      displaySmall: f(theme.displaySmall),
      headlineLarge: f(theme.headlineLarge),
      headlineMedium: f(theme.headlineMedium),
      headlineSmall: f(theme.headlineSmall),
      titleLarge: f(theme.titleLarge),
      titleMedium: f(theme.titleMedium),
      titleSmall: f(theme.titleSmall),
      bodyLarge: f(theme.bodyLarge),
      bodyMedium: f(theme.bodyMedium),
      bodySmall: f(theme.bodySmall),
      labelLarge: f(theme.labelLarge),
      labelMedium: f(theme.labelMedium),
      labelSmall: f(theme.labelSmall),
    );
  }
}

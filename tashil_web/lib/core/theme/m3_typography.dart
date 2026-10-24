/// Font-size tokens for the app's dense data UI.
///
/// The M3 type-scale sizes (labelSmall 11, bodySmall 12, bodyMedium 14,
/// bodyLarge 16, headlineSmall 24, headlineMedium 28) match
/// `Theme.of(context).textTheme`. The "Plus"/intermediate steps keep the
/// existing dense dashboards pixel-identical. Use these instead of raw
/// numeric `fontSize` literals; prefer a full `textTheme` style for new code.
abstract final class M3FontSize {
  static const double micro = 9.0;
  static const double microPlus = 9.5;
  static const double tiny = 10.0;
  static const double tinyPlus = 10.5;
  static const double labelSmall = 11.0;
  static const double labelSmallPlus = 11.5;
  static const double bodySmall = 12.0;
  static const double bodySmallPlus = 12.5;
  static const double labelMediumPlus = 13.0;
  static const double bodyCompact = 13.5;
  static const double bodyMedium = 14.0;
  static const double bodyMediumPlus = 14.5;
  static const double bodyMediumLarge = 15.0;
  static const double bodyMediumLargePlus = 15.5;
  static const double bodyLarge = 16.0;
  static const double titleMediumPlus = 18.0;
  static const double headlineSmall = 24.0;
  static const double headlineMedium = 28.0;
  static const double displayHero = 68.0;
}

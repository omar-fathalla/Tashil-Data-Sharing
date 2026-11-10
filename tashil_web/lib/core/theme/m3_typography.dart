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

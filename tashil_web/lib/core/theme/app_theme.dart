import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'm3_color_roles.dart';
import 'm3_motion.dart';

/// AppTheme builds the official Google Material Design 3 (M3) theme
/// using single-seed dynamic color palette generation, M3 Motion & Transitions,
/// and Cairo Arabic typography.
class AppTheme {
  AppTheme._();

  /// Builds light ThemeData derived programmatically from a single seed color.
  static ThemeData light({Color seedColor = TenantBrandSeeds.adecoSeed}) {
    final isBlue = TenantBrandSeeds.isDefaultBlueSeed(seedColor);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: isBlue ? const Color(0xFF0B57D0) : seedColor,
      brightness: Brightness.light,
    );
    final colorScheme = isBlue
        ? baseScheme.copyWith(primary: const Color(0xFF1565C0))
        : baseScheme;

    return _buildTheme(colorScheme);
  }

  /// Builds dark ThemeData derived programmatically from a single seed color.
  static ThemeData dark({Color seedColor = TenantBrandSeeds.adecoSeed}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    // Generate Cairo Arabic typography hierarchy
    TextTheme baseTextTheme;
    try {
      baseTextTheme = GoogleFonts.cairoTextTheme();
    } catch (_) {
      // Offline / test environment fallback
      baseTextTheme = const TextTheme();
    }

    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: 40.0,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
        letterSpacing: -0.5,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: 32.0,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 24.0,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 20.0,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 18.0,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 15.0,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 15.0,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 13.0,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurfaceVariant,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
      ),
    );

    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14.0),
      side: BorderSide(
        color: colorScheme.outlineVariant.withOpacity(0.5),
        width: 1.0,
      ),
    );

    final menuStyle = MenuStyle(
      backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerHigh),
      surfaceTintColor: WidgetStateProperty.all(colorScheme.surfaceTint),
      elevation: WidgetStateProperty.all(3.0),
      shadowColor: WidgetStateProperty.all(colorScheme.shadow.withOpacity(0.18)),
      shape: WidgetStateProperty.all(menuShape),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      fontFamily: 'Cairo',
      pageTransitionsTheme: M3Motion.pageTransitionsTheme,
      focusColor: Colors.transparent,
      hoverColor: colorScheme.surfaceContainerHighest.withOpacity(0.2),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,

      // M3 Card Theme (Container Low surface, 16dp rounded corners)
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4), width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),

      // M3 Input Field Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
        ),
      ),

      // M3 Popup Menu Theme (with M3 Motion easing & duration)
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 3.0,
        shadowColor: colorScheme.shadow.withOpacity(0.18),
        shape: menuShape,
        textStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        position: PopupMenuPosition.under,
        menuPadding: const EdgeInsets.symmetric(vertical: 8.0),
      ),

      // M3 Button Family Themes with M3 Motion Duration
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
        ),
      ),

      // M3 MenuAnchor & MenuItemButton Theme
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSecondaryContainer;
            }
            return colorScheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.surfaceContainerHighest;
            }
            return Colors.transparent;
          }),
        ),
      ),

      // M3 DropdownMenu Theme
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        menuStyle: menuStyle,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
          ),
        ),
      ),

      // M3 Segmented Button Theme
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            const StadiumBorder(),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge,
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: colorScheme.outlineVariant),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
        ),
      ),

      // M3 Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.bold,
        ),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      ),

      // M3 Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 6.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
      ),

      // M3 Navigation Drawer / Sidebar Theme
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),

      // M3 Navigation Rail Theme
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // M3 Navigation Bar Theme
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            );
          }
          return textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // M3 App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

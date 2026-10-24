import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'm3_color_roles.dart';
import 'm3_motion.dart';
import 'm3_shape.dart';
import 'm3_spacing.dart';
import 'm3_status_colors.dart';

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

    // Full M3 type scale (sizes per M3 spec, tuned for Cairo/Arabic legibility).
    TextStyle? t(TextStyle? base, double size, FontWeight w, Color c,
            {double? ls, double? h}) =>
        base?.copyWith(
          fontSize: size,
          fontWeight: w,
          color: c,
          letterSpacing: ls,
          height: h,
        );
    final onS = colorScheme.onSurface;
    final onSV = colorScheme.onSurfaceVariant;
    final textTheme = baseTextTheme.copyWith(
      displayLarge: t(baseTextTheme.displayLarge, 40.0, FontWeight.w700, onS, ls: -0.5),
      displayMedium: t(baseTextTheme.displayMedium, 32.0, FontWeight.w700, onS),
      displaySmall: t(baseTextTheme.displaySmall, 28.0, FontWeight.w700, onS),
      headlineLarge: t(baseTextTheme.headlineLarge, 26.0, FontWeight.w600, onS),
      headlineMedium: t(baseTextTheme.headlineMedium, 24.0, FontWeight.w600, onS),
      headlineSmall: t(baseTextTheme.headlineSmall, 20.0, FontWeight.w600, onS),
      titleLarge: t(baseTextTheme.titleLarge, 18.0, FontWeight.w600, onS),
      titleMedium: t(baseTextTheme.titleMedium, 15.0, FontWeight.w500, onS),
      titleSmall: t(baseTextTheme.titleSmall, 13.0, FontWeight.w500, onSV),
      bodyLarge: t(baseTextTheme.bodyLarge, 15.0, FontWeight.w400, onS),
      bodyMedium: t(baseTextTheme.bodyMedium, 13.0, FontWeight.w400, onSV),
      bodySmall: t(baseTextTheme.bodySmall, 12.0, FontWeight.w400, onSV),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11.0,
        fontWeight: FontWeight.w500,
      ),
    );

    final menuShape = RoundedRectangleBorder(
      borderRadius: M3Shape.radiusMd,
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
          borderRadius: M3Shape.radiusMd,
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),

      // M3 Input Field Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: M3Spacing.sm, vertical: 12.0),
        border: OutlineInputBorder(
          borderRadius: M3Shape.radiusSm,
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: M3Shape.radiusSm,
          borderSide: BorderSide(color: colorScheme.outline, width: 1.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: M3Shape.radiusSm,
          borderSide: BorderSide(color: colorScheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: M3Shape.radiusSm,
          borderSide: BorderSide(color: colorScheme.error, width: 2.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: M3Shape.radiusSm,
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
          minimumSize: WidgetStateProperty.all(const Size(64.0, 40.0)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: M3Spacing.md, vertical: 10.0),
          ),
          iconSize: WidgetStateProperty.all(18.0),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
          minimumSize: WidgetStateProperty.all(const Size(64.0, 40.0)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: M3Spacing.md, vertical: 10.0),
          ),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? colorScheme.onSurface.withOpacity(0.12)
                : colorScheme.outline,
          )),
          iconSize: WidgetStateProperty.all(18.0),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
          minimumSize: WidgetStateProperty.all(const Size(64.0, 40.0)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: M3Spacing.md, vertical: 10.0),
          ),
          iconSize: WidgetStateProperty.all(18.0),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
        ),
      ),

      // M3 MenuAnchor & MenuItemButton Theme
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: M3Shape.radiusSm),
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
          filled: false,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          border: OutlineInputBorder(
            borderRadius: M3Shape.radiusSm,
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: M3Shape.radiusSm,
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: M3Shape.radiusSm,
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
        shape: const RoundedRectangleBorder(borderRadius: M3Shape.radiusSm),
      ),

      // M3 Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 6.0,
        shape: const RoundedRectangleBorder(
          borderRadius: M3Shape.radiusXl,
        ),
      ),

      // M3 Navigation Drawer / Sidebar Theme
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),

      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelLarge?.copyWith(
              color: colorScheme.onSecondaryContainer,
            );
          }
          return textTheme.labelLarge?.copyWith(color: onSV);
        }),
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

      extensions: <ThemeExtension<dynamic>>[
        M3StatusColors.fromScheme(colorScheme),
      ],

      // M3 Icon Button Theme
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
        ),
      ),

      // M3 FAB Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3.0,
        shape: M3Shape.shapeLg,
      ),

      // M3 SnackBar Theme
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
        shape: M3Shape.shapeXs,
        elevation: 3.0,
        showCloseIcon: false,
      ),

      // M3 Banner Theme
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: onS),
        padding: const EdgeInsetsDirectional.only(
            start: M3Spacing.sm, top: M3Spacing.xxs, end: M3Spacing.xs),
        elevation: 1.0,
        dividerColor: colorScheme.outlineVariant,
      ),

      // M3 Data Table Theme
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainer),
        headingTextStyle: textTheme.labelLarge?.copyWith(color: onS),
        dataTextStyle: textTheme.bodyMedium?.copyWith(color: onS),
        dividerThickness: 1.0,
        headingRowHeight: 48.0,
        dataRowMinHeight: 44.0,
        dataRowMaxHeight: 52.0,
        horizontalMargin: M3Spacing.sm,
        columnSpacing: M3Spacing.md,
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.secondaryContainer.withOpacity(0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return colorScheme.surfaceContainerHighest.withOpacity(0.4);
          }
          return null;
        }),
      ),

      // M3 Divider / ListTile / Tooltip / Progress / Badge
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1.0,
        space: 1.0,
      ),
      listTileTheme: ListTileThemeData(
        shape: M3Shape.shapeSm,
        iconColor: onSV,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium,
        contentPadding:
            const EdgeInsetsDirectional.symmetric(horizontal: M3Spacing.sm),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: M3Shape.radiusXs,
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.error,
        textColor: colorScheme.onError,
      ),

      // M3 Date Picker Theme
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: M3Shape.shapeXl,
        headerHeadlineStyle: textTheme.headlineSmall,
        rangePickerBackgroundColor: colorScheme.surfaceContainerHigh,
        rangeSelectionBackgroundColor: colorScheme.secondaryContainer,
      ),

      // M3 Bottom Sheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(M3Shape.xl)),
        ),
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

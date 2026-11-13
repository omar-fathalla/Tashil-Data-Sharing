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
  /// M3 default tonal-spot variant: calm neutrals; primary reserved for the
  /// main action, the selected destination and focus. Brand #35A211 stays the seed.
  static ThemeData light({Color seedColor = TenantBrandSeeds.brandGreen}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return _buildTheme(colorScheme);
  }

  /// Builds dark ThemeData derived programmatically from a single seed color.
  static ThemeData dark({Color seedColor = TenantBrandSeeds.brandGreen}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
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

    // Official M3 type scale (size/weight). Cairo font + line-height only tuned.
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
      displayLarge: t(baseTextTheme.displayLarge, 57.0, FontWeight.w400, onS, h: 64 / 57),
      displayMedium: t(baseTextTheme.displayMedium, 45.0, FontWeight.w400, onS, h: 52 / 45),
      displaySmall: t(baseTextTheme.displaySmall, 36.0, FontWeight.w400, onS, h: 44 / 36),
      headlineLarge: t(baseTextTheme.headlineLarge, 32.0, FontWeight.w400, onS, h: 40 / 32),
      headlineMedium: t(baseTextTheme.headlineMedium, 28.0, FontWeight.w400, onS, h: 36 / 28),
      headlineSmall: t(baseTextTheme.headlineSmall, 24.0, FontWeight.w400, onS, h: 32 / 24),
      titleLarge: t(baseTextTheme.titleLarge, 22.0, FontWeight.w400, onS, h: 28 / 22),
      titleMedium: t(baseTextTheme.titleMedium, 16.0, FontWeight.w500, onS, h: 24 / 16),
      titleSmall: t(baseTextTheme.titleSmall, 14.0, FontWeight.w500, onSV, h: 20 / 14),
      bodyLarge: t(baseTextTheme.bodyLarge, 16.0, FontWeight.w400, onS, h: 24 / 16),
      bodyMedium: t(baseTextTheme.bodyMedium, 14.0, FontWeight.w400, onSV, h: 20 / 14),
      bodySmall: t(baseTextTheme.bodySmall, 12.0, FontWeight.w400, onSV, h: 16 / 12),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 20 / 14,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11.0,
        fontWeight: FontWeight.w500,
        height: 16 / 11,
      ),
    );

    // Visible 3dp focus ring (secondary ≈ 6:1 on surface) shared by the button
    // family, segmented buttons and tappable surfaces.
    WidgetStateProperty<BorderSide?> sideWithFocus(BorderSide? normal) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colorScheme.secondary, width: 3.0);
          }
          if (states.contains(WidgetState.disabled) && normal != null) {
            return BorderSide(
                color: colorScheme.onSurface.withValues(alpha: 0.12));
          }
          return normal;
        });

    final menuShape = RoundedRectangleBorder(
      borderRadius: M3Shape.radiusMd,
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        width: 1.0,
      ),
    );

    final menuStyle = MenuStyle(
      backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerHigh),
      surfaceTintColor: WidgetStateProperty.all(colorScheme.surfaceTint),
      elevation: WidgetStateProperty.all(3.0),
      shadowColor: WidgetStateProperty.all(colorScheme.shadow.withValues(alpha: 0.18)),
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
      // Desktop browsers otherwise pick VisualDensity.compact and shrink 40→32dp buttons.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // Restore M3 default state layers (hover/focus/pressed). Do not zero them out.

      // M3 outlined card: surface + 1dp outlineVariant
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: M3Shape.radiusMd,
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),

      // M3 Input Field Theme — outlined, ~56dp with vertical 16 padding
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: M3Spacing.sm, vertical: 16.0),
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
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
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
            const EdgeInsets.symmetric(horizontal: M3Spacing.sm, vertical: 10.0),
          ),
          iconSize: WidgetStateProperty.all(20.0),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
          side: sideWithFocus(null),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
          minimumSize: WidgetStateProperty.all(const Size(64.0, 40.0)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: M3Spacing.sm, vertical: 10.0),
          ),
          side: sideWithFocus(BorderSide(color: colorScheme.outline)),
          iconSize: WidgetStateProperty.all(20.0),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          animationDuration: M3Motion.short4,
          shape: WidgetStateProperty.all(const StadiumBorder()),
          minimumSize: WidgetStateProperty.all(const Size(64.0, 40.0)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: M3Spacing.sm, vertical: 10.0),
          ),
          iconSize: WidgetStateProperty.all(20.0),
          textStyle: WidgetStateProperty.all(textTheme.labelLarge),
          side: sideWithFocus(null),
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
          fontWeight: FontWeight.w500,
        ),
        menuStyle: menuStyle,
        inputDecorationTheme: InputDecorationTheme(
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 16.0),
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

      // M3 Segmented Button Theme — selected = secondaryContainer (no elevation)
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            const StadiumBorder(),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge,
          ),
          side: sideWithFocus(BorderSide(color: colorScheme.outline)),
          // Width: SegmentedButton does not forward minimumSize to segments,
          // so the ≥ 112dp segment width comes from M3SegmentLabel.
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: M3Spacing.s12)),
          iconSize: const WidgetStatePropertyAll(18.0),
          elevation: WidgetStateProperty.all(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSecondaryContainer;
            }
            return colorScheme.onSurface;
          }),
        ),
      ),

      // M3 Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
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
          color: colorScheme.secondary,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // M3 Navigation Bar Theme — selected label = secondary (no bold)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelMedium?.copyWith(
              color: colorScheme.secondary,
              fontWeight: FontWeight.w500,
            );
          }
          return textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // M3 TabBar Theme (secondary indicator style for page sections)
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        dividerColor: colorScheme.outlineVariant,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: colorScheme.primary,
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
        headingTextStyle: textTheme.titleSmall?.copyWith(color: onS),
        dataTextStyle: textTheme.bodyMedium?.copyWith(color: onS),
        dividerThickness: 1.0,
        headingRowHeight: 48.0,
        dataRowMinHeight: 48.0,
        dataRowMaxHeight: 56.0,
        horizontalMargin: M3Spacing.sm,
        columnSpacing: M3Spacing.md,
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.secondaryContainer.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
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

      // M3 App Bar Theme — prefer surfaceContainer tint over shadow when scrolled
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_color_roles.dart';
import 'package:tashil_web/core/theme/m3_motion.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('M3 Theme Specification Tests', () {
    testWidgets('Strict M3 Enabling: useMaterial3 is true', (WidgetTester tester) async {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);

      final darkTheme = AppTheme.dark();
      expect(darkTheme.useMaterial3, isTrue);
    });

    testWidgets('Single Seed Generation for Adeco Brand Green #35A211', (WidgetTester tester) async {
      final theme = AppTheme.light(seedColor: TenantBrandSeeds.adecoSeed);
      expect(TenantBrandSeeds.brandGreen, const Color(0xFF35A211));
      expect(TenantBrandSeeds.adecoSeed, TenantBrandSeeds.brandGreen);
      expect(TenantBrandSeeds.adminSeed, TenantBrandSeeds.brandGreen);
      // tonalSpot from #35A211: calm neutrals, primary #426834 (not forced blue).
      expect(theme.colorScheme.primary.toARGB32() & 0x00FFFFFF, isNot(0x001565C0));
      expect(theme.colorScheme.primary, const Color(0xFF426834));
      expect(theme.colorScheme.secondaryContainer, const Color(0xFFD8E7CC));
      expect(theme.colorScheme.surface, const Color(0xFFF8FAF0));
      expect(theme.colorScheme.surfaceContainerLow, isNotNull);
      expect(theme.colorScheme.surfaceContainer, isNotNull);
      expect(theme.colorScheme.surfaceContainerHigh, isNotNull);
      expect(theme.colorScheme.surfaceContainerHighest, isNotNull);
    });

    test('Tenant Seed Resolution', () {
      expect(TenantBrandSeeds.getSeedForTenant('adeco'), TenantBrandSeeds.brandGreen);
      expect(TenantBrandSeeds.getSeedForTenant('admin'), TenantBrandSeeds.brandGreen);
      expect(TenantBrandSeeds.parseHexColor('#1565C0'), TenantBrandSeeds.brandGreen);
      expect(TenantBrandSeeds.getSeedForTenant('unilever'), TenantBrandSeeds.unileverSeed);
      expect(TenantBrandSeeds.getSeedForTenant('pepsi'), TenantBrandSeeds.pepsiSeed);
    });

    test('8dp Baseline Spacing Scale Consistency', () {
      expect(M3Spacing.s2, 2.0);
      expect(M3Spacing.xxs, 4.0);
      expect(M3Spacing.xs, 8.0);
      expect(M3Spacing.s12, 12.0);
      expect(M3Spacing.sm, 16.0);
      expect(M3Spacing.md, 24.0);
      expect(M3Spacing.lg, 32.0);
      expect(M3Spacing.xl, 40.0);
      expect(M3Spacing.xxl, 48.0);
      expect(M3Spacing.xxxl, 64.0);

      // Verify all non-micro spacings are strict multiples of 8
      for (final s in [M3Spacing.xs, M3Spacing.sm, M3Spacing.md, M3Spacing.lg, M3Spacing.xl, M3Spacing.xxl, M3Spacing.xxxl]) {
        expect(s % 8.0, 0.0);
      }
    });

    test('M3 Motion Duration and Easing Tokens', () {
      expect(M3Motion.short1, const Duration(milliseconds: 50));
      expect(M3Motion.short4, const Duration(milliseconds: 200));
      expect(M3Motion.medium1, const Duration(milliseconds: 250));
      expect(M3Motion.medium2, const Duration(milliseconds: 300));
      expect(M3Motion.long1, const Duration(milliseconds: 450));
      expect(M3Motion.extraLong4, const Duration(milliseconds: 1000));

      expect(M3Motion.standard.transform(0.5), greaterThan(0.5));
      expect(M3Motion.emphasizedDecelerate.transform(0.5), greaterThan(0.5));
    });

    testWidgets('M3 PageTransitionsTheme and Menu/Dropdown Component Themes', (WidgetTester tester) async {
      final theme = AppTheme.light();
      expect(theme.pageTransitionsTheme.builders[TargetPlatform.macOS], isA<M3SharedAxisPageTransitionsBuilder>());
      expect(theme.pageTransitionsTheme.builders[TargetPlatform.android], isA<M3SharedAxisPageTransitionsBuilder>());
      expect(theme.popupMenuTheme.color, equals(theme.colorScheme.surfaceContainerHigh));
      expect(theme.menuTheme.style, isNotNull);
      expect(theme.dropdownMenuTheme.menuStyle, isNotNull);
      expect(theme.navigationRailTheme.indicatorColor, equals(theme.colorScheme.secondaryContainer));
      expect(theme.navigationBarTheme.indicatorColor, equals(theme.colorScheme.secondaryContainer));
      expect(theme.filledButtonTheme.style?.animationDuration, equals(M3Motion.short4));
      expect(theme.outlinedButtonTheme.style?.animationDuration, equals(M3Motion.short4));
      expect(theme.textButtonTheme.style?.animationDuration, equals(M3Motion.short4));
      expect(M3Motion.menuAnimationStyle.duration, equals(M3Motion.medium1));
      expect(M3Motion.menuAnimationStyle.reverseDuration, equals(M3Motion.short3));
      expect(M3Motion.dialogAnimationStyle.duration, equals(M3Motion.medium2));
    });
    test('M3 Shape scale tokens', () {
      expect(M3Shape.xs, 4.0);
      expect(M3Shape.sm, 8.0);
      expect(M3Shape.md, 12.0);
      expect(M3Shape.lg, 16.0);
      expect(M3Shape.largeIncreased, 20.0);
      expect(M3Shape.xl, 28.0);
      expect(M3Shape.extraLargeIncreased, 32.0);
      expect(M3Shape.extraExtraLarge, 48.0);
      expect(M3Shape.full, 999.0);
    });

    testWidgets('Official type scale + restored state layers + segmented secondary', (tester) async {
      final theme = AppTheme.light();
      expect(theme.textTheme.displayLarge?.fontSize, 57.0);
      expect(theme.textTheme.headlineLarge?.fontSize, 32.0);
      expect(theme.textTheme.titleLarge?.fontSize, 22.0);
      expect(theme.textTheme.bodyLarge?.fontSize, 16.0);
      expect(theme.textTheme.bodyMedium?.fontSize, 14.0);
      expect(theme.visualDensity, VisualDensity.standard);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.focusColor, isNot(Colors.transparent));
      expect(theme.splashColor, isNot(Colors.transparent));
      expect(theme.dataTableTheme.dataRowMinHeight, 48.0);
      expect(theme.tabBarTheme.labelColor, theme.colorScheme.primary);
      expect(
        theme.navigationBarTheme.labelTextStyle
            ?.resolve({WidgetState.selected})
            ?.color,
        theme.colorScheme.secondary,
      );
      final selectedBg = theme.segmentedButtonTheme.style?.backgroundColor
          ?.resolve({WidgetState.selected});
      expect(selectedBg, theme.colorScheme.secondaryContainer);
    });

    testWidgets('Status/chart ThemeExtension and full component themes', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final ext = theme.extension<M3StatusColors>();
        expect(ext, isNotNull);
        expect(ext!.chartPalette.length, greaterThanOrEqualTo(8));
        expect(ext.chart(0), theme.colorScheme.primary);
        expect(ext.chart(8), ext.chart(0));
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.inputDecorationTheme.filled, isFalse);
        expect(theme.dataTableTheme.headingRowColor, isNotNull);
        expect(theme.iconButtonTheme.style, isNotNull);
        expect(theme.datePickerTheme.shape, M3Shape.shapeXl);
        expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.textTheme.bodySmall, isNotNull);
        expect(theme.textTheme.labelSmall, isNotNull);
      }
      final ext = AppTheme.light().extension<M3StatusColors>()!;
      final mid = ext.lerp(AppTheme.dark().extension<M3StatusColors>(), 0.5);
      expect(mid.chartPalette.length, ext.chartPalette.length);
    });
  });
}

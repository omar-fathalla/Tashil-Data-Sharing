import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_color_roles.dart';
import 'package:tashil_web/core/theme/m3_motion.dart';
import 'package:tashil_web/core/theme/m3_spacing.dart';

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

    testWidgets('Single Seed Generation for Adeco Brand', (WidgetTester tester) async {
      final theme = AppTheme.light(seedColor: TenantBrandSeeds.adecoSeed);
      expect(theme.colorScheme.primary, isNotNull);
      expect(theme.colorScheme.surfaceContainerLow, isNotNull);
      expect(theme.colorScheme.surfaceContainer, isNotNull);
      expect(theme.colorScheme.surfaceContainerHigh, isNotNull);
      expect(theme.colorScheme.surfaceContainerHighest, isNotNull);
    });

    test('Tenant Seed Resolution', () {
      expect(TenantBrandSeeds.getSeedForTenant('adeco'), TenantBrandSeeds.adecoSeed);
      expect(TenantBrandSeeds.getSeedForTenant('unilever'), TenantBrandSeeds.unileverSeed);
      expect(TenantBrandSeeds.getSeedForTenant('pepsi'), TenantBrandSeeds.pepsiSeed);
    });

    test('8dp Baseline Spacing Scale Consistency', () {
      expect(M3Spacing.xxs, 4.0);
      expect(M3Spacing.xs, 8.0);
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
  });
}

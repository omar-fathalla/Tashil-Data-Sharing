import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/layout/window_size_classes.dart';

void main() {
  group('M3 Window Size Classes & Metrics Engine Tests', () {
    test('Compact Window Class (< 600dp)', () {
      final metrics = M3Layout.fromDimensions(450.0, 800.0);
      expect(metrics.sizeClass, M3WindowSizeClass.compact);
      expect(metrics.isCompact, isTrue);
      expect(metrics.isDesktop, isFalse);
      expect(metrics.columns, 4);
      expect(metrics.margin, 16.0);
      expect(metrics.gutter, 16.0);
      expect(metrics.navigationType, M3NavigationType.bottomBarOrDrawer);
    });

    test('Medium Window Class (600 - 839dp)', () {
      final metrics = M3Layout.fromDimensions(720.0, 900.0);
      expect(metrics.sizeClass, M3WindowSizeClass.medium);
      expect(metrics.isMedium, isTrue);
      expect(metrics.isDesktop, isFalse);
      expect(metrics.columns, 8);
      expect(metrics.margin, 24.0);
      expect(metrics.gutter, 24.0);
      expect(metrics.navigationType, M3NavigationType.rail);
    });

    test('Expanded Window Class (840 - 1199dp)', () {
      final metrics = M3Layout.fromDimensions(1024.0, 768.0);
      expect(metrics.sizeClass, M3WindowSizeClass.expanded);
      expect(metrics.isExpanded, isTrue);
      expect(metrics.isDesktop, isTrue);
      expect(metrics.columns, 12);
      expect(metrics.margin, 24.0);
      expect(metrics.navigationType, M3NavigationType.permanentSidebar);
    });

    test('Large Desktop Window Class (1200 - 1599dp)', () {
      final metrics = M3Layout.fromDimensions(1440.0, 900.0);
      expect(metrics.sizeClass, M3WindowSizeClass.large);
      expect(metrics.isLarge, isTrue);
      expect(metrics.isDesktop, isTrue);
      expect(metrics.columns, 12);
      expect(metrics.margin, 32.0);
      expect(metrics.navigationType, M3NavigationType.permanentSidebar);
    });

    test('Extra Large Ultra-wide Window Class (>= 1600dp)', () {
      final metrics = M3Layout.fromDimensions(1920.0, 1080.0);
      expect(metrics.sizeClass, M3WindowSizeClass.extraLarge);
      expect(metrics.isExtraLarge, isTrue);
      expect(metrics.isDesktop, isTrue);
      expect(metrics.columns, 12);
      expect(metrics.margin, 64.0);
      expect(metrics.navigationType, M3NavigationType.permanentSidebar);
    });
  });
}

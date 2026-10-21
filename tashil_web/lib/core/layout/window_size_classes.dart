import 'package:flutter/widgets.dart';

/// The 5 official Material Design 3 Window Size Classes.
/// Ref: https://m3.material.io/foundations/layout/applying-layout/window-size-classes
enum M3WindowSizeClass {
  /// Compact: < 600dp (Smartphones portrait, folded foldables)
  compact,

  /// Medium: 600 - 839dp (Small tablets, unfolded foldables, landscape phones)
  medium,

  /// Expanded: 840 - 1199dp (Laptops, large tablets landscape)
  expanded,

  /// Large: 1200 - 1599dp (Desktop monitors)
  large,

  /// Extra Large: >= 1600dp (Ultra-wide displays, 4K monitors)
  extraLarge,
}

/// Canonical navigation type corresponding to the M3 window size.
enum M3NavigationType {
  /// Compact (< 600dp): Bottom Navigation Bar or Modal Drawer
  bottomBarOrDrawer,

  /// Medium (600 - 839dp): Slim Navigation Rail (72-76dp)
  rail,

  /// Expanded / Large / Extra Large (>= 840dp): Permanent Navigation Sidebar
  permanentSidebar,
}

/// Layout metrics calculated per window size class.
class M3LayoutMetrics {
  final M3WindowSizeClass sizeClass;
  final double width;
  final double height;
  final int columns;
  final double margin;
  final double gutter;
  final M3NavigationType navigationType;

  const M3LayoutMetrics({
    required this.sizeClass,
    required this.width,
    required this.height,
    required this.columns,
    required this.margin,
    required this.gutter,
    required this.navigationType,
  });

  bool get isCompact => sizeClass == M3WindowSizeClass.compact;
  bool get isMedium => sizeClass == M3WindowSizeClass.medium;
  bool get isExpanded => sizeClass == M3WindowSizeClass.expanded;
  bool get isLarge => sizeClass == M3WindowSizeClass.large;
  bool get isExtraLarge => sizeClass == M3WindowSizeClass.extraLarge;

  /// True for laptop and desktop viewport widths (>= 840dp).
  bool get isDesktop => isExpanded || isLarge || isExtraLarge;
}

/// Engine computing M3 layout metrics from MediaQuery or BoxConstraints.
class M3Layout {
  M3Layout._();

  /// Resolves metrics from ambient BuildContext.
  static M3LayoutMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return fromDimensions(size.width, size.height);
  }

  /// Resolves metrics from LayoutBuilder BoxConstraints.
  static M3LayoutMetrics fromConstraints(BoxConstraints constraints) {
    return fromDimensions(constraints.maxWidth, constraints.maxHeight);
  }

  /// Resolves metrics from width and height.
  static M3LayoutMetrics fromDimensions(double width, double height) {
    final M3WindowSizeClass sizeClass;
    final int columns;
    final double margin;
    final double gutter;
    final M3NavigationType navType;

    if (width < 600.0) {
      sizeClass = M3WindowSizeClass.compact;
      columns = 4;
      margin = 16.0;
      gutter = 16.0;
      navType = M3NavigationType.bottomBarOrDrawer;
    } else if (width < 840.0) {
      sizeClass = M3WindowSizeClass.medium;
      columns = 8;
      margin = 24.0;
      gutter = 24.0;
      navType = M3NavigationType.rail;
    } else if (width < 1200.0) {
      sizeClass = M3WindowSizeClass.expanded;
      columns = 12;
      margin = 24.0;
      gutter = 24.0;
      navType = M3NavigationType.permanentSidebar;
    } else if (width < 1600.0) {
      sizeClass = M3WindowSizeClass.large;
      columns = 12;
      margin = 32.0;
      gutter = 24.0;
      navType = M3NavigationType.permanentSidebar;
    } else {
      sizeClass = M3WindowSizeClass.extraLarge;
      columns = 12;
      margin = 64.0;
      gutter = 24.0;
      navType = M3NavigationType.permanentSidebar;
    }

    return M3LayoutMetrics(
      sizeClass: sizeClass,
      width: width,
      height: height,
      columns: columns,
      margin: margin,
      gutter: gutter,
      navigationType: navType,
    );
  }
}

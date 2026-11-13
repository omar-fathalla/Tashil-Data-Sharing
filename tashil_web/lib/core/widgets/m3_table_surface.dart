import 'package:flutter/material.dart';

/// One container role for every table / data card on a page, so tables do
/// not alternate between white and cream: M3 `surfaceContainerLow` (the
/// same role as the KPI cards and filter bars).
abstract final class M3TableSurface {
  static Color color(ColorScheme cs) => cs.surfaceContainerLow;
}

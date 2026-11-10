import 'package:flutter/material.dart';

/// Fixed semantic colours used by status chips, badges and KPI deltas.
///
/// These are tenant-independent "identity" colours (the same role as
/// [M3StatusColors]' chain colours). Theme-reactive status colours live in
/// `M3StatusColors.of(context)`; prefer those in new code. Centralising the
/// literals here removes raw `Color(0x..)` from feature code.
abstract final class M3Palette {
  // Status (strong)
  /// Text-safe success green (≥4.5:1 on white); was #15803D borderline on containers.
  static const Color success = Color(0xFF166534);
  static const Color emerald = Color(0xFF047857);
  static const Color emeraldDeep = Color(0xFF065F46);
  static const Color warning = Color(0xFFB45309);
  static const Color warningAccent = Color(0xFF92400E);
  static const Color amber = Color(0xFFB45309);
  static const Color amberDeep = Color(0xFF92400E);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerAccent = Color(0xFFD93025);
  static const Color rose = Color(0xFFE11D48);
  static const Color info = Color(0xFF0284C7);
  static const Color sky = Color(0xFF38BDF8);
  static const Color blue = Color(0xFF2563EB);
  static const Color indigo = Color(0xFF4F46E5);
  static const Color violet = Color(0xFF7C3AED);
  static const Color teal = Color(0xFF0F766E);
  static const Color neutral = Color(0xFF6B7280);

  // Status surfaces (container / on-container pairs)
  static const Color successSurface = Color(0xFFE6F4EA);
  static const Color onSuccessSurface = Color(0xFF0D652D);
  static const Color warningSurface = Color(0xFFFEF7E0);
  static const Color onWarningSurface = Color(0xFFB06000);
  static const Color onWarningSurfaceDeep = Color(0xFF8A4B00);
  static const Color dangerSurface = Color(0xFFFCE8E6);
  static const Color onDangerSurface = Color(0xFFA50E0E);
  static const Color infoSurface = Color(0xFFE8F0FE);
  static const Color onInfoSurface = Color(0xFF1967D2);
}

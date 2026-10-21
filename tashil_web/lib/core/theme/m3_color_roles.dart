import 'package:flutter/material.dart';

/// Extension providing direct access to Material Design 3 Surface Container Tiers.
extension M3ColorRolesExtension on ColorScheme {
  /// Base surface for the canvas/scaffold background
  Color get scaffoldSurface => surface;

  /// Surface Container Low: standard background for Bento Grid KPI cards
  Color get surfaceContainerLowRole => surfaceContainerLow;

  /// Surface Container: navigation sidebar / drawer background
  Color get surfaceContainerRole => surfaceContainer;

  /// Surface Container High: elevated cards, active metric highlights, and dialogs
  Color get surfaceContainerHighRole => surfaceContainerHigh;

  /// Surface Container Highest: text fields, search inputs, unselected button tracks
  Color get surfaceContainerHighestRole => surfaceContainerHighest;
}

/// Tenant branding seed color definitions.
class TenantBrandSeeds {
  TenantBrandSeeds._();

  /// Official Google Material Design 3 Standard Contrast Primary Blue (#1565C0)
  static const Color m3DefaultBlue = Color(0xFF1565C0);

  /// Super Admin Platform - Material 3 Blue
  static const Color adminSeed = Color(0xFF1565C0);

  /// Adeco (أديكو للصناعات المتطورة) - Material 3 Standard Contrast Blue
  static const Color adecoSeed = Color(0xFF1565C0);

  /// Unilever (يونيليفر مشرق) - Dynamic Teal
  static const Color unileverSeed = Color(0xFF0D9488);

  /// PepsiCo (بيبسي كولا مصر) - Vibrant Crimson Red
  static const Color pepsiSeed = Color(0xFFB91C1C);

  /// In-memory cache for provisioned tenant colors
  static final Map<String, Color> _dynamicSeeds = {};

  static bool isDefaultBlueSeed(Color color) {
    final v = color.toARGB32();
    return v == 0xFF1565C0 || v == 0xFF0B57D0 || v == 0xFF1E3A8A;
  }

  /// Registers a custom brand color for a provisioned tenant
  static void registerTenantSeed(String slug, Color color) {
    final cleanSlug = slug.toLowerCase().replaceAll('tenant-', '');
    if (cleanSlug == 'adeco' ||
        cleanSlug == 'admin' ||
        cleanSlug == 'system' ||
        isDefaultBlueSeed(color)) {
      _dynamicSeeds[cleanSlug] = m3DefaultBlue;
      return;
    }
    _dynamicSeeds[cleanSlug] = color;
  }

  /// Parses a hex color string like '#1E3A8A' or '1E3A8A' into a Flutter Color
  static Color? parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var cleaned = hex.replaceAll('#', '').trim().toUpperCase();
    if (cleaned == '1E3A8A' || cleaned == '0B57D0' || cleaned == '1565C0') {
      return m3DefaultBlue;
    }
    if (cleaned.length == 6) {
      cleaned = 'FF$cleaned';
    }
    final int? val = int.tryParse(cleaned, radix: 16);
    if (val != null) {
      return Color(val);
    }
    return null;
  }

  static Color getSeedForTenant(String tenantCode, [String? hexOverride]) {
    final code = tenantCode.toLowerCase().replaceAll('tenant-', '');
    if (code == 'adeco' ||
        code == 'admin' ||
        code == 'system' ||
        code == 'superadmin' ||
        code == 'company' ||
        code == 'portal') {
      return m3DefaultBlue;
    }

    if (hexOverride != null && hexOverride.isNotEmpty) {
      final parsed = parseHexColor(hexOverride);
      if (parsed != null) return parsed;
    }

    if (_dynamicSeeds.containsKey(code)) {
      return _dynamicSeeds[code]!;
    }

    switch (code) {
      case 'unilever':
        return unileverSeed;
      case 'pepsi':
      case 'pepsico':
        return pepsiSeed;
      case 'adeco':
      default:
        return adecoSeed;
    }
  }
}

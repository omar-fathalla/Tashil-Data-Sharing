import 'package:flutter/material.dart';

/// Semantic status + chart palette as a Material 3 [ThemeExtension].
///
/// Read with `M3StatusColors.of(context)`. Values are derived from the
/// active seed so they harmonise with the tenant [ColorScheme].
@immutable
class M3StatusColors extends ThemeExtension<M3StatusColors> {
  const M3StatusColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.chartPalette,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  /// Ordered categorical palette for charts (series 0..n).
  final List<Color> chartPalette;

  static const Color _successSeed = Color(0xFF2E7D32);
  static const Color _warningSeed = Color(0xFFF9A825);
  static const Color _infoSeed = Color(0xFF0277BD);

  static const List<Color> _chartSeeds = [
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFFF57C00),
    Color(0xFF8E24AA),
    Color(0xFFC62828),
    Color(0xFF6D4C41),
    Color(0xFF3949AB),
    Color(0xFF7CB342),
  ];

  /// Builds the extension for a given [ColorScheme] (light or dark).
  factory M3StatusColors.fromScheme(ColorScheme scheme) {
    final b = scheme.brightness;
    ColorScheme s(Color seed) =>
        ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final ok = s(_successSeed);
    final warn = s(_warningSeed);
    final info = s(_infoSeed);
    return M3StatusColors(
      success: ok.primary,
      onSuccess: ok.onPrimary,
      successContainer: ok.primaryContainer,
      onSuccessContainer: ok.onPrimaryContainer,
      warning: warn.primary,
      onWarning: warn.onPrimary,
      warningContainer: warn.primaryContainer,
      onWarningContainer: warn.onPrimaryContainer,
      info: info.primary,
      onInfo: info.onPrimary,
      infoContainer: info.primaryContainer,
      onInfoContainer: info.onPrimaryContainer,
      chartPalette: [
        scheme.primary,
        ..._chartSeeds.skip(1).map((c) => b == Brightness.dark
            ? Color.lerp(c, Colors.white, 0.3)!
            : c),
      ],
    );
  }

  /// Returns the extension from the theme, or derives one on the fly.
  static M3StatusColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<M3StatusColors>() ??
        M3StatusColors.fromScheme(theme.colorScheme);
  }

  /// Chart colour for series [index] (wraps around).
  Color chart(int index) => chartPalette[index % chartPalette.length];

  @override
  M3StatusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    List<Color>? chartPalette,
  }) {
    return M3StatusColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      chartPalette: chartPalette ?? this.chartPalette,
    );
  }

  @override
  M3StatusColors lerp(ThemeExtension<M3StatusColors>? other, double t) {
    if (other is! M3StatusColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return M3StatusColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      chartPalette: [
        for (var i = 0; i < chartPalette.length; i++)
          l(chartPalette[i],
              other.chartPalette[i % other.chartPalette.length]),
      ],
    );
  }
}

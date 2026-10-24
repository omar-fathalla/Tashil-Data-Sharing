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
    this.accents = M3AccentRoles.light,
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

  /// Dashboard accent roles (see [M3AccentRoles]).
  final M3AccentRoles accents;

  /// Fixed categorical colours for retailer chains (identity colours that
  /// must stay stable across light/dark and tenants).
  static const Color chainFathalla = Color(0xFF10B981);
  static const Color chainGomla = Color(0xFFF59E0B);
  static const Color chainBeetElGomla = Color(0xFF7C3AED);
  static const Color chainCarrefour = Color(0xFF2563EB);
  static const Color chainSpinneys = Color(0xFFE11D48);
  static const Color chainSeoudi = Color(0xFF0891B2);
  static const Color chainMetro = Color(0xFFD946EF);
  static const Color chainKazyon = Color(0xFFDC2626);

  /// Ordered chain palette (used for unknown chains / fallback indexes).
  static const List<Color> chainPalette = [
    chainFathalla,
    chainGomla,
    chainBeetElGomla,
    chainCarrefour,
    chainSpinneys,
    chainSeoudi,
    chainMetro,
    chainKazyon,
  ];

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
    M3AccentRoles? accents,
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
      accents: accents ?? this.accents,
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
      accents: accents.lerp(other.accents, t),
    );
  }
}

/// Dashboard accent roles (Sell-In / Sell-Out / Targets). Light values are
/// identical to the Material swatches the screens used before
/// (e.g. [positive] == Colors.green.shade700), so the look is unchanged.
@immutable
class M3AccentRoles {
  const M3AccentRoles({this.positive = const Color(0xFF388E3C), this.positiveStrong = const Color(0xFF2E7D32), this.teal = const Color(0xFF00796B), this.tealStrong = const Color(0xFF00695C), this.tealDeep = const Color(0xFF004D40), this.tealSurface = const Color(0xFFE0F2F1), this.indigo = const Color(0xFF303F9F), this.caution = const Color(0xFFEF6C00), this.cautionStrong = const Color(0xFFE65100), this.cautionSurface = const Color(0xFFFFE0B2), this.alert = const Color(0xFFE64A19), this.alertStrong = const Color(0xFFD84315), this.highlight = const Color(0xFFFF6F00), this.highlightBorder = const Color(0xFFFFA000), this.highlightSurface = const Color(0xFFFFECB3), this.purple = const Color(0xFF7B1FA2), this.purpleStrong = const Color(0xFF6A1B9A), this.negative = const Color(0xFFD32F2F), this.neutral = const Color(0xFF455A64), this.tealBase = const Color(0xFF009688), this.redBase = const Color(0xFFF44336), this.orangeBase = const Color(0xFFFF9800), this.competitor = const Color(0xFF90A4AE), this.competitorStrong = const Color(0xFF607D8B), this.competitorSurface = const Color(0xFFCFD8DC)});

  final Color positive;
  final Color positiveStrong;
  final Color teal;
  final Color tealStrong;
  final Color tealDeep;
  final Color tealSurface;
  final Color indigo;
  final Color caution;
  final Color cautionStrong;
  final Color cautionSurface;
  final Color alert;
  final Color alertStrong;
  final Color highlight;
  final Color highlightBorder;
  final Color highlightSurface;
  final Color purple;
  final Color purpleStrong;
  final Color negative;
  final Color neutral;

  /// == Colors.teal (base [500] swatch).
  final Color tealBase;
  /// == Colors.red (base [500] swatch).
  final Color redBase;
  /// == Colors.orange (base [500] swatch).
  final Color orangeBase;
  /// Neutral grey for competitor series in market-share charts.
  final Color competitor;
  final Color competitorStrong;
  final Color competitorSurface;

  static const M3AccentRoles light = M3AccentRoles();

  M3AccentRoles lerp(M3AccentRoles o, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return M3AccentRoles(
      tealBase: l(tealBase, o.tealBase),
      redBase: l(redBase, o.redBase),
      orangeBase: l(orangeBase, o.orangeBase),
      competitor: l(competitor, o.competitor),
      competitorStrong: l(competitorStrong, o.competitorStrong),
      competitorSurface: l(competitorSurface, o.competitorSurface),
      positive: l(positive, o.positive),
      positiveStrong: l(positiveStrong, o.positiveStrong),
      teal: l(teal, o.teal),
      tealStrong: l(tealStrong, o.tealStrong),
      tealDeep: l(tealDeep, o.tealDeep),
      tealSurface: l(tealSurface, o.tealSurface),
      indigo: l(indigo, o.indigo),
      caution: l(caution, o.caution),
      cautionStrong: l(cautionStrong, o.cautionStrong),
      cautionSurface: l(cautionSurface, o.cautionSurface),
      alert: l(alert, o.alert),
      alertStrong: l(alertStrong, o.alertStrong),
      highlight: l(highlight, o.highlight),
      highlightBorder: l(highlightBorder, o.highlightBorder),
      highlightSurface: l(highlightSurface, o.highlightSurface),
      purple: l(purple, o.purple),
      purpleStrong: l(purpleStrong, o.purpleStrong),
      negative: l(negative, o.negative),
      neutral: l(neutral, o.neutral),
    );
  }
}

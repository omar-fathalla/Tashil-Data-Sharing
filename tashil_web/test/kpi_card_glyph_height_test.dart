import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';

import 'support/real_fonts.dart';

// v137 live review: Compare KPI cards were 141px vs Sell-Out 138px at
// 1280x800. The Compare value/detail lines carry ▲ / ▼, which Cairo has no
// glyph for, so the browser draws them with a fallback font whose ascent /
// descent split differs; mixed runs made the line taller. The shared card
// now forces a strut per text role, so any fallback glyph keeps the line
// height of the role and every card stays 138px.
TextTheme _withFallback(TextTheme t, List<String> fb) {
  TextStyle? f(TextStyle? s) => s?.copyWith(
      fontFamilyFallback: [...?s.fontFamilyFallback, ...fb]);
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

Future<double> _cardHeight(WidgetTester tester, String value, String detail,
    {List<String>? fallback}) async {
  final theme = AppTheme.light();
  final t = fallback == null
      ? theme
      : theme.copyWith(textTheme: _withFallback(theme.textTheme, fallback));
  await tester.pumpWidget(MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: t,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(
          children: [SizedBox(
            width: 232,
            child: M3SummaryKpiCard(
              key: const ValueKey('card'),
              title: 'حركة الأسعار 2026',
              value: value,
              subtitle: detail,
              icon: Icons.show_chart_rounded,
              color: Colors.teal,
            ),
          )],
        ),
      ),
    ),
  ));
  await tester.pump();
  return tester.getSize(find.byKey(const ValueKey('card'))).height;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    await loadRealCairoFont();
    // ▲ ▼ are covered by the bundled NotoSansSymbols2 fallback that
    // loadRealCairoFont / AppTheme now register (OFL-NotoSansSymbols2.txt).
  });

  testWidgets('arrow glyphs (▲ ▼) do not change the KPI card height',
      (tester) async {
    final plain = await _cardHeight(tester, '302 صنف', 'سنة 2026');
    final arrows = await _cardHeight(
        tester, '▲243 ▼46', '▲ زاد · ▼ نزل · يناير - أكتوبر');
    // The arrows drawn by the symbol fallback font (taller descent share
    // than Cairo), as on the live web build.
    final withFallback = await _cardHeight(
        tester, '▲243 ▼46', '▲ زاد · ▼ نزل · يناير - أكتوبر',
        fallback: const ['NotoSansSymbols2']);
    expect(arrows, plain);
    expect(withFallback, plain);
    expect(plain, 138.0);
    for (final key in ['card']) {
      final texts = tester.widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(Text)));
      final value = texts.firstWhere((t) => t.data == '▲243 ▼46');
      expect(value.strutStyle?.forceStrutHeight, isTrue);
    }
  });
}

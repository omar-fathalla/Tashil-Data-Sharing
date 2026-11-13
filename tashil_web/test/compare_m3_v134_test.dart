// v134: Compare gets the Sell-Out / Sell-In M3 treatment. At 1280 and 1024
// content width: no overflow in the selected-SKU spotlight (short movement
// chip + month detail underneath), KPI titles/details never clipped, Arabic
// counted nouns, full search placeholder, 8dp chips, long names up to 3 lines.
// Real Cairo font; all names and prices are made-up fixtures.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_search_field.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/compare_fixture.dart';
import 'support/real_fonts.dart';

Future<List<FlutterErrorDetails>> _pump(WidgetTester tester, double width,
    {Widget? page}) async {
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final errors = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed')) errors.add(d);
  };
  addTearDown(() => FlutterError.onError = old);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: page ??
            CompetitorComparisonScreen(
              apiClient:
                  ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
              repository: CompareFakeRepo(),
            ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  FlutterError.onError = old;
  return errors;
}

RenderParagraph _para(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderParagraph>(
        find.descendant(of: f, matching: find.byType(RichText)).first);

bool _clipped(WidgetTester tester, Finder f) {
  final p = tester.renderObject(f);
  final para = p is RenderParagraph ? p : _para(tester, f);
  return para.didExceedMaxLines;
}


class _KpiMetrics {
  _KpiMetrics(this.size, this.padding, this.iconSize, this.fonts, this.weights);
  final Size size;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final List<double?> fonts; // title, value, subtitle
  final List<FontWeight?> weights;
  @override
  String toString() => 'size=$size padding=$padding icon=$iconSize fonts=$fonts weights=$weights';
}

_KpiMetrics _kpi(WidgetTester tester, Finder card) {
  final texts = find.descendant(of: card, matching: find.byType(Text));
  final styles = [
    for (final e in texts.evaluate())
      (find
              .descendant(
                  of: find.byWidget(e.widget), matching: find.byType(RichText))
              .evaluate()
              .first
              .widget as RichText)
          .text
          .style,
  ];
  return _KpiMetrics(
    tester.getSize(card),
    tester.widget<Container>(find.descendant(of: card, matching: find.byType(Container)).first).padding,
    tester.widget<Icon>(find.descendant(of: card, matching: find.byType(Icon)).first).size,
    [for (final st in styles) st?.fontSize],
    [for (final st in styles) st?.fontWeight],
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in const [1280.0, 1024.0]) {
    group('compare @$width', () {
      testWidgets('spotlight: short movement chip + detail, no overflow',
          (tester) async {
        final errors = await _pump(tester, width);
        expect(errors, isEmpty,
            reason: errors.map((e) => e.exceptionAsString()).join('\n'));
        final chip = find.byKey(const ValueKey('compare_movement_chip'));
        expect(chip, findsOneWidget);
        expect(find.descendant(of: chip, matching: find.text('ارتفاع السعر')),
            findsOneWidget);
        final detail = find.byKey(const ValueKey('compare_movement_detail'));
        expect(detail, findsOneWidget);
        expect(_clipped(tester, detail), isFalse);
        // Status chips use the shared 8dp chip surface and Arabic plurals.
        expect(find.text('أنت أرخص من منافس واحد'), findsOneWidget);
        expect(find.text('أنت أغلى من منافس واحد'), findsOneWidget);
        expect(find.byType(M3ChipSurface), findsWidgets);
      });

      testWidgets('KPI titles/details never clipped, counted nouns',
          (tester) async {
        await _pump(tester, width);
        final titles = find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            ((w.key as ValueKey<String>).value.startsWith('compare_kpi_title_') ||
                (w.key as ValueKey<String>).value.startsWith('compare_kpi_subtitle_')));
        expect(titles, findsNWidgets(8));
        for (final e in titles.evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          expect(p.didExceedMaxLines, isFalse, reason: '${e.widget.key}');
        }
        expect(find.text('3 أصناف'), findsWidgets);
        expect(find.text('3 صنف'), findsNothing);
      });

      testWidgets('search placeholder shown in full', (tester) async {
        await _pump(tester, width);
        final field = find.byKey(const ValueKey('compare_search_field'));
        expect(field, findsOneWidget);
        expect(
            find.ancestor(of: field, matching: find.byType(M3SearchFieldWidth)),
            findsOneWidget);
        final hint = find.descendant(
            of: field,
            matching: find.text('ابحث باسم الصنف، الباركود، أو المنافس...'));
        final p = tester.renderObject<RenderParagraph>(
            find.descendant(of: hint, matching: find.byType(RichText)).first);
        expect(p.didExceedMaxLines, isFalse);
        final fieldW = tester.getSize(field).width;
        expect(fieldW, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity)));
      });

      testWidgets('long competitor names wrap up to 3 lines, not cut',
          (tester) async {
        await _pump(tester, width);
        final long = find.text(compareLongCompetitorName);
        expect(long, findsWidgets);
        for (final e in long.evaluate()) {
          final t = e.widget as Text;
          expect(t.maxLines == null || t.maxLines! >= 3, isTrue,
              reason: 'maxLines ${t.maxLines}');
          final p = e.renderObject! as RenderParagraph;
          expect(p.didExceedMaxLines, isFalse);
        }
      });
    });
  }
  // Symmetry with the Sell-Out reference KPI card (t437u).
  for (final width in const [1280.0, 1024.0]) {
    testWidgets('KPI cards match the Sell-Out reference @$width',
        (tester) async {
      await _pump(tester, width, page: SellOutExplorerScreen(apiClient: ApiClient()));
      await tester.pumpAndSettle();
      final ref = _kpi(tester, find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')));
      await _pump(tester, width);
      final cards = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('compare_kpi_card_'));
      expect(cards, findsNWidgets(4));
      for (final e in cards.evaluate()) {
        final m = _kpi(tester, find.byWidget(e.widget));
        final why = 'compare ${e.widget.key}: $m\nsell-out: $ref';
        expect(m.padding, ref.padding, reason: why);
        expect(m.iconSize, ref.iconSize, reason: why);
        expect(m.fonts, ref.fonts, reason: why);
        expect(m.weights, ref.weights, reason: why);
        expect(m.size.width, closeTo(ref.size.width, 0.5), reason: why);
        expect(m.size.height, closeTo(ref.size.height, 0.5), reason: why);
      }
    });
  }
}

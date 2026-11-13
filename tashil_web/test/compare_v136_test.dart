// Compare follow-up: live-scale KPI symmetry, chart callout collisions,
// per-month competitor detail (exact month only), suggestions surfaces.
// Real Cairo font; all names and prices are made-up fixtures.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/theme/m3_shape.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/widgets/competitor_suggestions_review.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/screens/competitor_comparison_screen.dart';
import 'package:tashil_web/features/competitor_comparison/presentation/utils/chart_callout_layout.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart';

import 'support/compare_fixture.dart';
import 'support/real_fonts.dart';

Future<void> _pump(WidgetTester tester, double width, Widget page) async {
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        textDirection: TextDirection.rtl, child: Scaffold(body: page)),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Widget _compare(List<OwnSkuCompetitiveGroupModel> groups) =>
    CompetitorComparisonScreen(
      apiClient: ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false),
      repository: CompareFakeRepo(groups),
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealCairoFont);
  setUp(AppCache.clear);

  for (final width in const [1280.0, 1024.0]) {
    testWidgets('live-scale KPI values stay one line; cards = Sell-Out @$width',
        (tester) async {
      await _pump(tester, width, SellOutExplorerScreen(apiClient: ApiClient()));
      await tester.pumpAndSettle();
      final ref =
          tester.getSize(find.byKey(const ValueKey('kpi_card_Net Sales (EGP)')));
      await _pump(tester, width, _compare(compareLiveScaleGroups()));
      final cards = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('compare_kpi_card_'));
      expect(cards, findsNWidgets(4));
      expect(find.text('▲243 ▼46'), findsOneWidget);
      expect(find.text('302 صنف'), findsWidgets);
      for (final e in cards.evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, closeTo(ref.height, 0.5),
            reason: '${e.widget.key} $size vs Sell-Out $ref');
        for (final t in find
            .descendant(of: find.byWidget(e.widget), matching: find.byType(Text))
            .evaluate()) {
          final p = find
              .descendant(
                  of: find.byWidget(t.widget), matching: find.byType(RichText))
              .evaluate()
              .first
              .renderObject! as RenderParagraph;
          expect(p.didExceedMaxLines, isFalse, reason: '${(t.widget as Text).data}');
        }
      }
    });
  }

  group('chart callouts', () {
    test('crossing lines: callouts never overlap each other or a point', () {
      // Two series that cross between month 4 and 6 (Oxi-like case).
      final own = [97.0, 95.0, 97.0, 119.0, 136.0, 174.0, 194.0, 239.0];
      final comp = [183.0, 184.0, 184.0, 184.0, 176.0, 176.0, 175.0, 175.0];
      double y(double p) => 300 - p; // simple price->y mapping
      double x(int i) => 60.0 + i * 48.0;
      const box = Size(46, 18);
      final markers = <Rect>[
        for (var i = 0; i < own.length; i++) ...[
          Rect.fromCircle(center: Offset(x(i), y(own[i])), radius: 7),
          Rect.fromCircle(center: Offset(x(i), y(comp[i])), radius: 6),
        ],
      ];
      final requests = [
        for (var i = 0; i < own.length; i++)
          CalloutRequest(
              anchor: Offset(x(i), y(own[i])),
              size: box,
              preferredDy: y(own[i]) <= y(comp[i]) ? -17 : 17),
        for (var i = 0; i < comp.length; i++)
          CalloutRequest(
              anchor: Offset(x(i), y(comp[i])),
              size: box,
              preferredDy: y(comp[i]) >= y(own[i]) ? 16 : -16),
      ];
      final rects = layoutCallouts(requests,
          bounds: const Rect.fromLTWH(0, 0, 600, 300), markers: markers);
      final shown = rects.whereType<Rect>().toList();
      for (var a = 0; a < shown.length; a++) {
        for (var b = a + 1; b < shown.length; b++) {
          expect(shown[a].overlaps(shown[b]), isFalse,
              reason: '${shown[a]} vs ${shown[b]}');
        }
        for (final m in markers) {
          expect(shown[a].overlaps(m), isFalse);
        }
      }
      // Own callouts (priority) are all shown.
      expect(rects.take(own.length).every((r) => r != null), isTrue);
      // Most competitor callouts still shown.
      expect(rects.skip(own.length).whereType<Rect>().length,
          greaterThanOrEqualTo(6));
    });

    test('competitor series aligns by month, gaps stay null', () {
      final g = compareGappyCompetitorGroups().first;
      final aligned =
          alignSeriesToMonths(g.monthlyPrices, g.competitors.first.monthlyPrices);
      expect(aligned.length, 10);
      expect(aligned.take(4).every((p) => p == null), isTrue);
      expect(aligned[4]!.monthNum, 5);
      expect(aligned[9]!.monthNum, 10);
    });
  });

  testWidgets('month cards show that month\'s competitor price, or «no price»',
      (tester) async {
    await _pump(tester, 1280, _compare(compareGappyCompetitorGroups()));
    for (var m = 1; m <= 4; m++) {
      expect(find.byKey(ValueKey('compare_month_no_comp_2026_$m')),
          findsOneWidget,
          reason: 'month $m has no competitor price');
      expect(find.byKey(ValueKey('compare_month_comp_2026_$m')), findsNothing);
    }
    for (var m = 5; m <= 10; m++) {
      final block = find.byKey(ValueKey('compare_month_comp_2026_$m'));
      expect(block, findsOneWidget);
      final price = (260.0 - 10 * m).toStringAsFixed(2);
      expect(
          find.descendant(of: block, matching: find.text('$price ج.م')),
          findsOneWidget,
          reason: 'month $m shows its own competitor price');
    }
  });
  testWidgets('suggestions tab uses the shared card surfaces, no pill wrapper',
      (tester) async {
    Map<String, dynamic> sug(String id, String comp) => {
          'id': id,
          'own_barcode': 'OWN1',
          'own_sku_name': 'صنف تجريبي',
          'own_category': 'منظفات',
          'competitor_barcode': comp,
          'competitor_sku_name': 'منافس $comp',
          'competitor_brand': 'Brand',
          'competitor_supplier': 'مورد',
          'category': 'منظفات',
          'retailer_chain': 'fathalla',
          'reason_ar': 'نفس الفئة',
          'confidence': 0.8,
          'rank': 1,
          'status': 'pending',
          'own_unit_price': 100.0,
          'competitor_unit_price': 90.0,
          'own_units': 10,
          'competitor_units': 8,
        };
    final store = [sug('s1', 'C1'), sug('s2', 'C2')];
    final client = MockClient((req) async => http.Response.bytes(
          utf8.encode(req.method == 'GET'
              ? jsonEncode({'suggestions': store, 'count': store.length})
              : '{}'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: CompetitorSuggestionsReview(
                apiClient: ApiClient(
                    tenantId: 'tenant-adeco', allowMockFallback: false),
                chain: 'fathalla',
                year: 2026,
                isOwner: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final cs = Theme.of(tester.element(find.byType(CompetitorSuggestionsReview)))
          .colorScheme;
      final card =
          tester.widget<Card>(find.byKey(const ValueKey('suggestion-group-OWN1')));
      expect(card.color, cs.surfaceContainerLow);
      // Nested suggestion rows: surface (not white surfaceContainerLowest).
      final lowest = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == cs.surfaceContainerLowest);
      expect(lowest, findsNothing);
      // Approve/Reject sit directly on the row: no extra rounded pill wrapper.
      final pill = find.ancestor(
          of: find.text('موافقة').first,
          matching: find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius == M3Shape.radiusXl));
      expect(pill, findsNothing);
      // 8dp between consecutive suggestion rows.
      final a = tester.getRect(find.ancestor(
          of: find.text('منافس C1'),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == cs.surface)).first);
      final b = tester.getRect(find.ancestor(
          of: find.text('منافس C2'),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == cs.surface)).first);
      expect(b.top - a.bottom, closeTo(8.0, 0.5));
    }, () => client);
  });
}

// v6 dashboard consistency: equal KPI heights, equal Pareto/category
// heights, one section-title style, standard 24dp section gaps and one chip
// shape (8dp radius, 32dp) across header filters, count tags and legends.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_summary_kpi_card.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/widgets/m3_section_title.dart';
import 'package:tashil_web/core/widgets/m3_status_tag.dart';
import 'package:tashil_web/core/widgets/m3_tonal_surface.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/screens/executive_screen.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/sellout_trend_chart.dart';

import 'support/real_fonts.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(body: ExecutiveScreen(apiClient: ApiClient())),
  ));
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  for (final width in [1440.0, 1024.0]) {
    testWidgets('all KPI cards share one height @${width.toInt()}',
        (tester) async {
      await _pump(tester, width);
      final cards = find.byType(M3SummaryKpiCard);
      expect(cards, findsNWidgets(4));
      final heights = cards
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)).height)
          .toList();
      for (final h in heights) {
        expect(h, moreOrLessEquals(heights.first, epsilon: 0.5),
            reason: 'KPI heights $heights');
        expect(h, closeTo(138.0, 2.0), reason: 'vs Sell-Out 138: $heights');
      }
    });
  }

  testWidgets(
      'Pareto and category-contribution cards stretch to one height '
      '@1440, 24dp apart', (tester) async {
    await _pump(tester, 1440);
    final cat =
        _rect(tester, find.byKey(const ValueKey('category_contribution_card')));
    final pareto =
        _rect(tester, find.byKey(const ValueKey('pareto_80_20_card')));
    expect(pareto.height, moreOrLessEquals(cat.height, epsilon: 0.5));
    expect(pareto.top, moreOrLessEquals(cat.top, epsilon: 0.5));
    final gap = cat.left > pareto.left
        ? cat.left - pareto.right
        : pareto.left - cat.right;
    expect(gap, moreOrLessEquals(24.0, epsilon: 0.5));
  });

  testWidgets('one section-title style (titleMedium w500) everywhere',
      (tester) async {
    await _pump(tester, 1440);
    const titles = [
      'المخزون حسب الصنف',
      'مساهمة الفئات',
      'الأصناف الأعلى مبيعًا (80/20)',
      'الحصة السوقية مقارنة بالمنافسين',
      'حصة كل سلسلة من المبيعات',
    ];
    for (final t in titles) {
      final f = find.descendant(
          of: find.byType(M3SectionTitle), matching: find.text(t));
      expect(f, findsOneWidget, reason: '"$t" is not an M3SectionTitle');
    }
    final expected = AppTheme.light().textTheme.titleMedium!;
    for (final e in find.byType(M3SectionTitle).evaluate()) {
      final p = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byWidget(e.widget), matching: find.byType(RichText)));
      final s = p.text.style!;
      expect(s.fontSize, expected.fontSize);
      expect(s.fontWeight, FontWeight.w500, reason: p.text.toPlainText());
    }
    // No heavier 16sp title left anywhere on the dashboard.
    for (final ro in tester.allRenderObjects.whereType<RenderParagraph>()) {
      final s = ro.text.style;
      if (s?.fontSize == 16.0) {
        expect(
            s!.fontWeight == FontWeight.w600 || s.fontWeight == FontWeight.w700,
            isFalse,
            reason: 'heavy 16sp title: ${ro.text.toPlainText()}');
      }
    }
  });

  testWidgets('trend chart follows row B with the standard 24dp gap',
      (tester) async {
    await _pump(tester, 1440);
    final rowB = _rect(tester, find.byKey(const ValueKey('exec_row_b')));
    final trend = _rect(tester, find.byType(SelloutTrendChart));
    expect(trend.top - rowB.bottom, moreOrLessEquals(24.0, epsilon: 0.5));
  });

  testWidgets('one chip shape: 8dp radius, 32dp, no ad-hoc chips',
      (tester) async {
    await _pump(tester, 1440);
    final chips = [
      ...find.byType(M3ChipSurface).evaluate(),
      ...find.byType(M3StatusTag).evaluate(),
    ];
    expect(chips.length, greaterThan(20));
    for (final e in chips) {
      final f = find.byWidget(e.widget);
      final material = tester.widget<Material>(
          find.descendant(of: f, matching: find.byType(Material)).first);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, M3ChipStyle.radius);
      final h = tester.getSize(f).height;
      final twoLine = find
          .descendant(of: f, matching: find.byType(Column))
          .evaluate()
          .isNotEmpty;
      if (twoLine) {
        expect(h, greaterThanOrEqualTo(M3ChipStyle.minHeight));
      } else {
        expect(h, moreOrLessEquals(M3ChipStyle.minHeight, epsilon: 0.5),
            reason: 'chip height');
      }
    }
    // Any remaining static tonal surface with text must be a container
    // (≥ 40dp), not a hand-made chip of another size/radius.
    for (final e in find.byType(M3TonalSurface).evaluate()) {
      final w = e.widget as M3TonalSurface;
      if (w.onTap != null) continue;
      final f = find.byWidget(w);
      if (find
          .descendant(of: f, matching: find.byType(Text))
          .evaluate()
          .isEmpty) {
        continue;
      }
      expect(tester.getSize(f).height, greaterThanOrEqualTo(40.0),
          reason:
              'ad-hoc chip: ${find.descendant(of: f, matching: find.byType(Text)).evaluate().map((t) => (t.widget as Text).data).join(' | ')}');
    }
    // Header filters are 40dp full-round controls (F1), not 8dp chips.
    var checked = 0;
    for (final k in [
      'executive_month_dropdown',
      'executive_year_dropdown',
      'executive_chain_dropdown',
    ]) {
      final key = find.byKey(ValueKey(k));
      if (key.evaluate().isEmpty) continue;
      final btn = find.descendant(
          of: key,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          matchRoot: true);
      final style = tester.widget<ButtonStyleButton>(btn.first).style!;
      final shape = style.shape!.resolve(<WidgetState>{});
      expect(shape, isA<StadiumBorder>(), reason: k);
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(2));
  });
}

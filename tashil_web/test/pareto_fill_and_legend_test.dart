// v7: the Pareto card fills its stretched height with extra SKU rows (no
// large blank area) and the category legend shows each label once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_fill_layout.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';

import 'support/real_fonts.dart';

// Test-only fixture names (not client data).
List<CategoryContributionModel> _categories(int n) => [
      for (var i = 0; i < n; i++)
        CategoryContributionModel(
          category: 'فئة تجريبية ${i + 1}',
          totalRevenue: 1000000.0 - i * 50000,
          totalUnits: 9000 - i * 300,
          sharePct: 10.0 - i * 0.5,
          skuCount: 12 + i,
          marketTotalRevenue: 5000000,
          tenantCategorySharePct: 20.0 - i,
        ),
    ];

List<ParetoSkuItemModel> _skus(int n) => [
      for (var i = 0; i < n; i++)
        ParetoSkuItemModel(
          barcode: '000${1000 + i}',
          itemCode: 'T-${i + 1}',
          skuName: 'صنف تجريبي رقم ${i + 1}',
          category: 'فئة تجريبية ${(i % 4) + 1}',
          totalRevenue: 500000.0 - i * 10000,
          totalUnits: 4000 - i * 50,
          revenueSharePct: 5.0 - i * 0.1,
          cumulativeSharePct: 5.0 * (i + 1),
          isTop80Contributor: i < 16,
        ),
    ];

Future<void> _pump(WidgetTester tester, {required int categories}) async {
  tester.view.physicalSize = const Size(1440, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: ParetoCategorySection(
            categories: _categories(categories),
            paretoSkus: _skus(30),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

RenderM3FillRows _rows(WidgetTester tester) =>
    tester.renderObject<RenderM3FillRows>(
        find.byKey(const ValueKey('pareto_sku_rows')));

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  testWidgets('tall category card: Pareto shows extra rows, no blank area',
      (tester) async {
    await _pump(tester, categories: 12);
    final cat = tester
        .getRect(find.byKey(const ValueKey('category_contribution_card')));
    final pareto =
        tester.getRect(find.byKey(const ValueKey('pareto_80_20_card')));
    expect(pareto.height, moreOrLessEquals(cat.height, epsilon: 0.5));
    final rows = _rows(tester);
    expect(rows.visibleCount, greaterThan(10));
    // Blank space under the last row is less than one more row (+24dp pad).
    final rowsRect =
        tester.getRect(find.byKey(const ValueKey('pareto_sku_rows')));
    final oneRow = rows.size.height / rows.visibleCount;
    expect(pareto.bottom - rowsRect.bottom, lessThan(oneRow + 24.0 + 1.0));
    // Hidden rows are not rendered as hittable / visible text.
    expect(find.text('صنف تجريبي رقم 30').hitTestable(), findsNothing);
    expect(find.text('صنف تجريبي رقم 1').hitTestable(), findsOneWidget);
  });

  testWidgets('short category card: Pareto keeps its 10 rows and sets height',
      (tester) async {
    await _pump(tester, categories: 2);
    expect(_rows(tester).visibleCount, 10);
    final cat = tester
        .getRect(find.byKey(const ValueKey('category_contribution_card')));
    final pareto =
        tester.getRect(find.byKey(const ValueKey('pareto_80_20_card')));
    expect(pareto.height, moreOrLessEquals(cat.height, epsilon: 0.5));
  });

  testWidgets('category legend shows each label once', (tester) async {
    await _pump(tester, categories: 4);
    final card = find.byKey(const ValueKey('category_metric_legend'));
    for (final label in const ['حصتنا السوقية %', '% من مبيعاتنا']) {
      expect(
          find.descendant(of: card, matching: find.text(label)), findsOneWidget,
          reason: label);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/arabic_plural.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_section.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/pareto_category_skus.dart';

const _category = 'فئة الاختبار';

ParetoSkuItemModel _sku({
  required String barcode,
  required String name,
  required double revenue,
  String category = _category,
  bool top80 = false,
}) {
  return ParetoSkuItemModel(
    barcode: barcode,
    skuName: name,
    category: category,
    totalRevenue: revenue,
    totalUnits: revenue.round(),
    revenueSharePct: 0,
    cumulativeSharePct: 0,
    isTop80Contributor: top80,
  );
}

/// 29 distinct barcodes. The first barcode is sent twice under two names
/// (the payload has 30 rows). Revenues put only the head inside 80%.
List<ParetoSkuItemModel> _categorySkus() {
  return [
    _sku(barcode: 'B01', name: 'صنف رقم 1', revenue: 800, top80: true),
    _sku(barcode: 'B01', name: 'اسم مكرر', revenue: 200, top80: true),
    for (var i = 2; i <= 29; i++)
      _sku(
        barcode: 'B${i.toString().padLeft(2, '0')}',
        name: 'صنف رقم $i',
        revenue: 1,
      ),
    _sku(
      barcode: 'OTHER',
      name: 'صنف خارج الفئة',
      revenue: 99999,
      category: 'فئة أخرى',
      top80: true,
    ),
  ];
}

void main() {
  test('category rollup keeps every barcode and shares sum to 100%', () {
    final rows = skusForCategory(
      paretoSkus: _categorySkus(),
      category: _category,
    );

    expect(rows, hasLength(29));
    expect(rows.map((s) => s.barcode).toSet(), hasLength(29));
    expect(rows.first.barcode, 'B01');
    expect(rows.first.skuName, 'صنف رقم 1');
    expect(rows.first.totalRevenue, 1000);
    expect(rows.any((s) => s.skuName == 'اسم مكرر'), isFalse);
    expect(rows.any((s) => s.skuName == 'صنف خارج الفئة'), isFalse);
    expect(rows.last.skuName, 'صنف رقم 29');
    expect(rows.last.cumulativeSharePct, 100);
    expect(rows.where((s) => !s.isTop80Contributor).length, greaterThan(0));
    expect(rows.where((s) => s.isTop80Contributor).length, greaterThan(0));

    for (var i = 1; i < rows.length; i++) {
      expect(
        rows[i - 1].totalRevenue,
        greaterThanOrEqualTo(rows[i].totalRevenue),
      );
    }

    final shown = rows
        .map((s) => double.parse(s.revenueSharePct.toStringAsFixed(1)))
        .fold<double>(0, (sum, share) => sum + share);
    expect(shown, closeTo(100, 0.001));
  });

  test(
    'empty barcode falls back to the SKU name, same as the category card',
    () {
      final rows = skusForCategory(
        paretoSkus: [
          _sku(barcode: '', name: 'بدون باركود أ', revenue: 30),
          _sku(barcode: '', name: 'بدون باركود ب', revenue: 70),
          _sku(barcode: '', name: 'بدون باركود أ', revenue: 10),
        ],
        category: _category,
      );
      expect(rows, hasLength(2));
      expect(rows.first.skuName, 'بدون باركود ب');
      expect(rows.last.skuName, 'بدون باركود أ');
      expect(rows.last.totalRevenue, 40);
      final shown = rows
          .map((s) => double.parse(s.revenueSharePct.toStringAsFixed(1)))
          .fold<double>(0, (sum, share) => sum + share);
      expect(shown, closeTo(100, 0.001));
    },
  );

  testWidgets(
    'selecting a category renders every SKU, including past the 80% line',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: ParetoCategorySection(
                  categories: [
                    CategoryContributionModel(
                      category: _category,
                      totalRevenue: 1028,
                      totalUnits: 1028,
                      sharePct: 100,
                      skuCount: 29,
                    ),
                  ],
                  paretoSkus: _categorySkus(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('أصناف المبيعات'), findsOneWidget);
      expect(find.textContaining('80/20'), findsNothing);
      expect(find.textContaining('تحقق 80'), findsNothing);

      await tester.tap(find.text(_category));
      await tester.pumpAndSettle();

      expect(find.textContaining('80/20'), findsNothing);
      expect(find.textContaining('تحقق 80'), findsNothing);
      expect(
        find.text('كل أصناف $_category · ${countSku(29)}'),
        findsOneWidget,
      );
      expect(find.textContaining('$_category · ${countSku(29)}'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pareto_cat_sku_count_$_category')),
          matching: find.text('29'),
        ),
        findsOneWidget,
      );

      for (var i = 1; i <= 29; i++) {
        expect(find.text('صنف رقم $i'), findsOneWidget, reason: 'صنف رقم $i');
      }
      expect(find.text('اسم مكرر'), findsNothing);
      expect(find.text('صنف خارج الفئة'), findsNothing);
      expect(find.text('تصنيف A'), findsWidgets);
      expect(find.text('تصنيف B/C'), findsWidgets);

      final shares = find
          .descendant(
            of: find.byKey(const ValueKey('pareto_80_20_card')),
            matching: find.textContaining('الحصة '),
          )
          .evaluate()
          .map((element) {
        final text = (element.widget as Text).data!;
        return double.parse(
          RegExp(r'الحصة (\d+(?:\.\d+)?)%').firstMatch(text)!.group(1)!,
        );
      }).toList();
      expect(shares, hasLength(29));
      expect(
        shares.fold<double>(0, (sum, share) => sum + share),
        closeTo(100, 0.05),
      );
      expect(find.textContaining('التراكمي 100.0%'), findsOneWidget);

      // «عرض الكل» clears the category, same action as the category card.
      expect(find.text('عرض الكل'), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('pareto_80_20_card')),
          matching: find.text('عرض الكل'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('كل أصناف $_category · ${countSku(29)}'), findsNothing);
      expect(find.text('مرتبة حسب المبيعات'), findsOneWidget);
    },
  );
}

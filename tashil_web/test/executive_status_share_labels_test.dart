import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/widgets/m3_chip_surface.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/market_share_section.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('roundSharePercents / skuSegmentPercents', () {
    test('three shares always sum to 100', () {
      final cases = <List<double>>[
        [0.2, 0.3, 0.5],
        [1 / 3, 1 / 3, 1 / 3],
        [0.01, 0.02, 0.97],
        [0.004, 0.006, 0.99],
        [0.5, 0.5, 0.0],
        [0.123, 0.456, 0.421],
      ];
      for (final shares in cases) {
        final pct = roundSharePercents(shares);
        expect(pct.length, 3);
        expect(pct.fold<int>(0, (a, b) => a + b), 100,
            reason: 'shares=$shares → $pct');
      }
    });

    test('green self % matches SKU revenue / market total (rounded)', () {
      // SKU 150 of market 1000 → 15%; own category 400 → own-other 25%;
      // competitors 60%.
      final pct = skuSegmentPercents(
        skuRevenue: 150,
        ownCategoryRevenue: 400,
        marketTotalRevenue: 1000,
      );
      expect(pct.self, 15);
      expect(pct.ownOther, 25);
      expect(pct.competitors, 60);
      expect(pct.self + pct.ownOther + pct.competitors, 100);
    });

    test('zero market yields zeros', () {
      final pct = skuSegmentPercents(
        skuRevenue: 10,
        ownCategoryRevenue: 20,
        marketTotalRevenue: 0,
      );
      expect(pct, (self: 0, ownOther: 0, competitors: 0));
    });
  });

  group('المخزون حسب الصنف — الحالة', () {
    CPFRDashboardModel stockCpfr() => CPFRDashboardModel.fromJson({
          'monthly_reconciliation': const [],
          'inventory_and_po_items': [
            {
              'barcode': '1',
              'item_code': 'A1',
              'sku_name': 'Optimal SKU',
              'sell_in_units': 900,
              'sell_out_units': 820,
              'estimated_stock_units': 80,
              'sell_through_pct': 91.1,
              'stock_status': 'optimal',
            },
            {
              'barcode': '2',
              'item_code': 'A2',
              'sku_name': 'Overstock SKU',
              'sell_in_units': 700,
              'sell_out_units': 300,
              'estimated_stock_units': 400,
              'sell_through_pct': 42.9,
              'stock_status': 'overstock',
            },
            {
              'barcode': '3',
              'item_code': 'A3',
              'sku_name': 'Urgent SKU',
              'sell_in_units': 200,
              'sell_out_units': 195,
              'estimated_stock_units': 5,
              'sell_through_pct': 97.5,
              'stock_status': 'urgent_replenishment',
            },
          ],
        });

    Future<void> pumpStock(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: MarketShareSection(
                kpis: ExecutiveKPIsModel.fromJson(const {}),
                cpfr: stockCpfr(),
                cpfrLoading: false,
                cpfrError: null,
                periodMonths: const {1, 2, 3, 4},
                year: 2026,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('urgent status keeps description only — no تموين chip',
        (tester) async {
      await pumpStock(tester);
      final table = find.byKey(const ValueKey('stock_per_sku_table'));
      expect(table, findsOneWidget);

      expect(find.descendant(of: table, matching: find.text('تموين')),
          findsNothing);
      expect(
        find.descendant(of: table, matching: find.text('يحتاج إعادة توريد')),
        findsOneWidget,
      );

      // Other statuses still use short chip + description.
      expect(find.descendant(of: table, matching: find.text('سليم')),
          findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('مخزون متوازن')),
          findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('زائد')),
          findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('مخزون زائد')),
          findsOneWidget);

      final chips = find.descendant(
        of: find.descendant(of: table, matching: find.byType(Table)),
        matching: find.byType(M3ChipSurface),
      );
      // Only سليم + زائد chips; urgent has no chip surface.
      expect(chips, findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('الحصة حسب الصنف — always-visible %', () {
    ExecutiveKPIsModel narrowSelfFixture() {
      // Self is 3% of market → segment too narrow for in-bar label at typical
      // card widths; own-other 27%; competitors 70%.
      return ExecutiveKPIsModel.fromJson({
        'category_contributions': [
          {
            'category': 'Oils',
            'total_revenue': 300.0,
            'total_units': 10,
            'share_pct': 30.0,
            'sku_count': 2,
            'market_total_revenue': 1000.0,
            'tenant_category_share_pct': 30.0,
            'tenant_rank': 1,
            'supplier_count': 5,
            'top_competitors': [
              {'name': 'Rival', 'revenue': 400.0, 'share_pct': 40.0},
            ],
          },
        ],
        'pareto_skus': [
          {
            'barcode': 'sku-narrow',
            'sku_name': 'Narrow Green SKU',
            'category': 'Oils',
            'total_revenue': 30.0,
            'total_units': 2,
            'revenue_share_pct': 3.0,
            'cumulative_share_pct': 3.0,
            'is_top_80_contributor': true,
          },
        ],
      });
    }

    Future<void> pumpShare(
      WidgetTester tester,
      ExecutiveKPIsModel kpis, {
      double width = 1280,
    }) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: MarketShareSection(
                kpis: kpis,
                cpfr: null,
                cpfrLoading: false,
                cpfrError: null,
                periodMonths: const {1, 2, 3, 4},
                year: 2026,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('narrow green self % is visible via outside callout',
        (tester) async {
      await pumpShare(tester, narrowSelfFixture());
      expect(tester.takeException(), isNull);

      final expected = skuSegmentPercents(
        skuRevenue: 30,
        ownCategoryRevenue: 300,
        marketTotalRevenue: 1000,
      );
      expect(expected.self, 3);
      expect(expected.ownOther, 27);
      expect(expected.competitors, 70);
      expect(expected.self + expected.ownOther + expected.competitors, 100);

      final card = find.byKey(const ValueKey('share_per_sku_card'));
      expect(card, findsOneWidget);

      // Green self is too narrow for an in-bar label → outside callout.
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('sku_share_pct_self_out')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('3%')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('27%')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('70%')),
        findsWidgets,
      );

      // Every non-zero segment label is present (in or out).
      for (final key in [
        'sku_share_pct_self_out',
        'sku_share_pct_own_other_in',
        'sku_share_pct_competitors_in',
      ]) {
        expect(
          find.descendant(of: card, matching: find.byKey(ValueKey(key))),
          findsOneWidget,
          reason: key,
        );
      }
    });

    testWidgets('wide segments keep in-bar labels that sum to 100',
        (tester) async {
      final kpis = ExecutiveKPIsModel.fromJson({
        'category_contributions': [
          {
            'category': 'Oils',
            'total_revenue': 600.0,
            'total_units': 10,
            'share_pct': 60.0,
            'sku_count': 2,
            'market_total_revenue': 1000.0,
            'tenant_category_share_pct': 60.0,
            'tenant_rank': 1,
            'supplier_count': 4,
            'top_competitors': const [],
          },
        ],
        'pareto_skus': [
          {
            'barcode': 'sku-wide',
            'sku_name': 'Wide Green SKU',
            'category': 'Oils',
            'total_revenue': 400.0,
            'total_units': 4,
            'revenue_share_pct': 40.0,
            'cumulative_share_pct': 40.0,
            'is_top_80_contributor': true,
          },
        ],
      });
      await pumpShare(tester, kpis, width: 1440);
      expect(tester.takeException(), isNull);

      final expected = skuSegmentPercents(
        skuRevenue: 400,
        ownCategoryRevenue: 600,
        marketTotalRevenue: 1000,
      );
      expect(expected.self + expected.ownOther + expected.competitors, 100);

      final card = find.byKey(const ValueKey('share_per_sku_card'));
      for (final label in [
        '${expected.self}%',
        '${expected.ownOther}%',
        '${expected.competitors}%',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsWidgets,
          reason: label,
        );
      }
      // No outside callouts when every segment is wide enough.
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('sku_share_pct_self_out')),
        ),
        findsNothing,
      );
    });
  });
}

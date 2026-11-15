// v123: YoY shows "—" + 'لا توجد بيانات للعام السابق' when there is no
// last-year data, Sell-Out compares the same months / shifted date range.
// Harness copied from v6: Sell-In v5: long backend status labels wrap inside the monthly chip, scroll
// hints hide when a table fits, stock secondary details wrap to 3 lines.
// Based on v4: monthly table fits 1030dp with realistic (made-up) large
// numbers, stock table main columns fit, and the uploaded-files 'الإجراءات'
// header is centred over the pinned actions column (Sell-In + Sell-Out).
// Fixture helpers copied from the v3 test.
// Based on the v2 fixture: Sell-In v2: Arabic row labels (no raw 'Barcode' / 'current_list'), Arabic
// semantics labels, semantic status chips in the shared 8dp chip shape,
// Sell-Out v1 table density, and wide tables whose main columns fit 1030dp
// (1280 minus the sidebar) with a pinned key column.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/data/sell_out_explorer_repository.dart';
import 'package:tashil_web/features/executive_dashboard/presentation/widgets/bento_kpi_grid.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/trade_marketing/domain/trade_marketing_models.dart';

import 'support/real_fonts.dart';

const _viewport = 1280.0 - 250.0;

final _records = [
  for (var i = 0; i < 40; i++)
    {
      'record_id': 'r$i',
      'batch_id': 'b',
      'source_filename': 'in26a.xlsx',
      'tenant_id': 'tenant-adeco',
      'retailer_chain': 'fathalla',
      'year': 2026,
      'month_num': 10,
      'month_ar': 'أكتوبر',
      'governorate': 'مدينة السادس من أكتوبر - الحي المتميز الجديد',
      'item_code': '10${i}55',
      'barcode': '62230000${i}1234',
      'brand': 'فيبا',
      'sub_category': 'منظفات الأرضيات والأسطح متعددة الاستخدام',
      'item_name': i == 0
          ? 'فيبا 4 كجم منظف متعدد الأغراض ليمون برائحة منعشة جدا للأرضيات والمطابخ والحمامات عبوة توفير'
          : 'كلوريل $i كجم',
      'sales_rep': 'مندوب المبيعات محمد عبد الرحمن',
      'units_per_carton': 12,
      'net_qty_cases': 120.0 + i,
      'net_value_egp': 182500.0 + i * 41230,
      'gross_value_incl_vat_egp': (182500.0 + i * 41230) * 1.14,
      'vat_amount_egp': (182500.0 + i * 41230) * 0.14,
      'weight_tons': 1.25,
      'official_carton_excl_vat_egp': 1651234.5,
      'actual_case_price_excl_egp': 1520987.25,
      'effective_discount_pct': i.isEven ? 0.0 : 7.9,
      'pricing_wave_status': i == 3 ? 'some_internal_key' : 'current_list',
    },
];

final _cpfr = <String, Object>{
  'matched_yoy_available': false,
  'matched_yoy_value_growth_pct': 0.0,
  'matched_yoy_units_growth_pct': 0.0,
  'monthly_reconciliation': [
    for (var m = 1; m <= 10; m++)
      {
        'year': 2026,
        'month_num': m,
        'has_actual_sell_out': true,
        'sell_in_units': 140000 + m * 913,
        'sell_out_units': 130000 + m * 791,
        'opening_stock_cases': 123456.0 + m,
        'opening_stock_value_egp': 187654321.5 + m * 1000,
        'sell_in_cases': 65432.0 + m,
        'sell_in_value_egp': 98765432.1 + m * 1000,
        'sell_in_gross_incl_vat_egp': 112592592.6 + m * 1000,
        'sell_out_est_cases': 54321.0 + m,
        'sell_out_value_egp': 87654321.9 + m * 1000,
        'sell_out_factory_cost_excl_vat_egp': 71234567.8,
        'sell_out_factory_cost_incl_vat_egp': 81207407.3,
        'chain_gross_margin_egp': 12345678.9,
        'chain_gross_margin_pct': 14.1,
        'prev_year_sell_out_value_egp': 70000000.0,
        'yoy_sell_out_growth_pct': m.isEven ? -12.3 : 25.4,
        'closing_stock_cases': 134567.0 + m,
        'closing_stock_value_egp': 198765432.1 + m * 1000,
        'sell_through_rate_pct': 47.3,
        'stock_health_status': [
          'drawdown',
          'balanced',
          'accumulation',
          'awaiting_sell_out',
          'awaiting_sell_in'
        ][m % 5],
        'stock_health_label_ar': [
          'سحب عالٍ يفوق توريد الشهر (تصريف من الرصيد السابق - يحتاج تعويض)',
          'معدل تصريف صحي ورصيد متبقي آمن',
          'تراكم مخزني بالفرع (التوريد أعلى من السحب - راقب الرصيد المتبقي)',
          'توريد مضاف للمخزن (بانتظار رفع شيت كاشير السلسلة Sell-Out للشهر)',
          'سحب فعلي مسجل (بانتظار رفع شيت التوريد Sell-In للشهر)',
        ][m % 5],
      },
  ],
  'inventory_and_po_items': [
    for (var i = 0; i < 3; i++)
      {
        'barcode': 'b$i',
        'item_code': 'I$i',
        'sku_name': i == 0
            ? 'فيبا 4 كجم منظف متعدد الأغراض ليمون برائحة منعشة جدا للأرضيات'
            : 'كلوريل $i',
        'sell_in_units': 40000 - i * 2500,
        'sell_out_units': 30000 - i * 1500,
        'estimated_stock_units': 9000 - i * 500,
        'brand': 'فيبا',
        'governorate': 'مدينة السادس من أكتوبر - الحي المتميز الجديد',
        'official_carton_excl_vat_egp': 1651234.5,
        'stock_status': ['urgent_replenishment', 'overstock', 'optimal'][i],
        'stock_status_ar': ['طلب توريد عاجل', 'تكدس مخزني', 'رصيد آمن'][i],
        'suggested_po_cases': 12345 - i,
        'suggested_po_value_egp': 23456789.5,
        'sell_in_value_egp': 98765432.1,
        'sell_out_value_egp': 87654321.9,
        'retailer_margin_pct': 18.0,
        'suggested_po_gross_incl_vat_egp': 26740740.0,
      },
  ],
};

MockClient _client() => MockClient((req) async {
      Object? body;
      if (req.url.path.endsWith('/api/v1/analytics/sell-in-records')) {
        body = {
          'records': _records,
          'total_count': _records.length,
          'total_value_egp': 1.0,
          'total_cases': 1.0,
          'total_weight_tons': 1.0,
          'total_expected_egp': 0.0,
        };
      } else if (req.url.path.endsWith('/api/v1/analytics/cpfr')) {
        body = _cpfr;
      } else if (req.url.path.endsWith('/api/v1/ingest/archive')) {
        body = {
          'tenant_id': 'tenant-adeco',
          'total_count': 2,
          'files': [
            for (final f in ['in26a.xlsx', 'in26b.xlsx'])
              {
                'id': 'arch_$f',
                'file_type': 'sell_in',
                'file_name': f,
                'retail_chain': 'fathalla',
                'target_year': '2026',
                'rows_ingested': 4321,
                'total_cases': 6543.0,
                'total_weight_tons': 123.4,
                'total_revenue': 9876543.2,
                'uploaded_at': '2026-11-13T10:00:00Z',
              },
          ],
        };
      }
      if (body == null) return http.Response('not found', 404);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _pump(WidgetTester tester,
    {int tab = 0, double width = _viewport}) async {
  tester.view.physicalSize = Size(width, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          body: SellInExplorerScreen(
              apiClient: ApiClient(tenantId: 'tenant-adeco'))),
    ),
  ));
  await tester.pumpAndSettle();
  if (tab == 1) {
    await tester
        .tap(find.textContaining(RegExp('^المخزون وإعادة الطلب')).first);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  test('E1. ExecutiveKPIsModel reads yoy_available (default true)', () {
    final base = {'total_revenue': 1.0, 'revenue_yoy_pct': 0.0};
    expect(
        ExecutiveKPIsModel.fromJson({...base, 'yoy_available': false})
            .yoyAvailable,
        isFalse);
    expect(
        ExecutiveKPIsModel.fromJson({...base, 'yoy_available': true})
            .yoyAvailable,
        isTrue);
    expect(ExecutiveKPIsModel.fromJson(base).yoyAvailable, isTrue);
    final rt = ExecutiveKPIsModel.fromJson(
        ExecutiveKPIsModel.fromJson({...base, 'yoy_available': false})
            .toJson());
    expect(rt.yoyAvailable, isFalse, reason: 'cached JSON keeps the flag');
  });

  test('E2. CPFR + Trade Marketing models expose the no-last-year state', () {
    expect(
        CPFRDashboardModel.fromJson({'matched_yoy_available': false})
            .matchedYoyAvailable,
        isFalse);
    expect(
        CPFRDashboardModel.fromJson({'matched_yoy_available': true})
            .matchedYoyAvailable,
        isTrue);
    // Older payload without the flag: 0% means not available.
    expect(CPFRDashboardModel.fromJson(const {}).matchedYoyAvailable, isFalse);
    expect(
        CPFRDashboardModel.fromJson({'matched_yoy_value_growth_pct': 12.5})
            .matchedYoyAvailable,
        isTrue);
    MonthlyChainRoiSummary roi(double ly) => MonthlyChainRoiSummary(
        year: 2026,
        month: 2,
        chainName: 'X',
        marketingSpendEgp: 10,
        activitiesCount: 1,
        expenses: const [],
        currentMonthSalesEgp: 100,
        previousMonthSalesEgp: 90,
        lastYearSameMonthSalesEgp: ly,
        currentMonthSellInEgp: 0);
    expect(roi(0).hasYoY, isFalse);
    expect(roi(80).hasYoY, isTrue);
  });

  test('E3. shiftDateByYears keeps the same day last year', () {
    expect(shiftDateByYears('2026-03-15', -1), '2025-03-15');
    expect(shiftDateByYears('2024-02-29', -1), '2023-02-28');
    expect(shiftDateByYears(null, -1), isNull);
    expect(shiftDateByYears('', -1), isNull);
  });

  testWidgets('E4. dashboard cards show "—" when there is no last-year data',
      (tester) async {
    ExecutiveKPIsModel kpis(bool yoy) => ExecutiveKPIsModel(
        totalRevenue: 1000,
        revenueGrowthPct: 0,
        revenueYoyPct: 0,
        revenueMomPct: 0,
        totalUnitsSold: 10,
        unitsGrowthPct: 0,
        unitsYoyPct: 0,
        unitsMomPct: 0,
        yoyAvailable: yoy,
        activeStoresCount: 1,
        oosRatePct: 0,
        totalOOSIncidents: 0,
        estimatedLostRevenue: 0,
        currency: 'EGP',
        reportingPeriod: 'ALL',
        chainShares: const [],
        dailyTrends: const []);
    Future<void> pump(bool yoy) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: BentoKpiGrid(kpis: kpis(yoy)))))));
      await tester.pumpAndSettle();
    }

    await pump(false);
    expect(
        find.textContaining('لا توجد بيانات للعام السابق'), findsNWidgets(2));
    expect(find.textContaining('مقارنة بالعام السابق'), findsNothing);
    await pump(true);
    expect(find.textContaining('لا توجد بيانات للعام السابق'), findsNothing);
    expect(find.textContaining('مقارنة بالعام السابق'), findsNWidgets(2));
  });

  testWidgets('E5. Sell-In YoY card shows "—" without last-year data',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, tab: 1);
      expect(tester.takeException(), isNull);
      expect(find.text('لا توجد بيانات للعام السابق'), findsOneWidget);
      expect(find.textContaining('بالقيمة'), findsNothing,
          reason: 'no fake "+0.0% بالقيمة" value');
    }, _client);
  });

  test('E6. Sell-Out last-year matrix: same months + shifted date range',
      () async {
    final seen = <Uri>[];
    final client = MockClient((req) async {
      seen.add(req.url);
      if (req.url.path.endsWith('/store-matrix')) {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{"records":[],"total_count":0}', 200,
          headers: {'content-type': 'application/json'});
    });
    await http.runWithClient(() async {
      final repo =
          SellOutExplorerRepository(ApiClient(tenantId: 'tenant-adeco'));
      await repo.load(const SellOutExplorerQuery(
          year: 2026,
          matrixYear: 2026,
          compYear: 2025,
          startDate: '2026-03-01',
          endDate: '2026-03-31'));
      await repo.load(const SellOutExplorerQuery(
          year: 2026, matrixYear: 2026, compYear: 2025));
      await repo.load(const SellOutExplorerQuery(
          year: 2026, month: 4, matrixYear: 2026, compYear: 2025));
    }, () => client);
    final prev = seen
        .where((u) =>
            u.path.endsWith('/store-matrix') &&
            u.queryParameters['year'] == '2025')
        .toList();
    expect(prev.length, 3, reason: seen.join('\n'));
    expect(prev[0].queryParameters['start_date'], '2025-03-01');
    expect(prev[0].queryParameters['end_date'], '2025-03-31');
    expect(prev[1].queryParameters['same_months_as'], '2026');
    expect(prev[1].queryParameters.containsKey('start_date'), isFalse);
    expect(prev[2].queryParameters['month'], '4');
    expect(prev[2].queryParameters.containsKey('same_months_as'), isFalse,
        reason: 'a picked month already compares the same month');

    // With no month/range: current-year YoY matrix is also trimmed to months
    // present last year (intersection). Display current matrix stays untrimmed.
    final cur2026 = seen
        .where((u) =>
            u.path.endsWith('/store-matrix') &&
            u.queryParameters['year'] == '2026')
        .toList();
    final noMonthLoad = cur2026
        .where((u) =>
            !u.queryParameters.containsKey('month') &&
            !u.queryParameters.containsKey('start_date'))
        .toList();
    expect(
      noMonthLoad.where((u) => u.queryParameters['same_months_as'] == '2025'),
      isNotEmpty,
      reason: 'YoY current must request same_months_as=compYear',
    );
    expect(
      noMonthLoad.where((u) => !u.queryParameters.containsKey('same_months_as')),
      isNotEmpty,
      reason: 'displayed current totals stay full-period (no same_months_as)',
    );
  });

  test('E7. like-for-like YoY: 2026 Jan–Oct vs 2025 Jan–Apr → ~+26.1% / +15.6%',
      () {
    // Owner fixture numbers (own-brand). Displayed full 2026 would be ~127.14M
    // and a naive YoY vs 32.18M looks like +295%; growth must use Jan–Apr only.
    const curL4LRev = 40564794.35;
    const prevL4LRev = 32179040.57;
    const curL4LUnits = 551555.0;
    const prevL4LUnits = 476948.0;
    final revPct = likeForLikeYoyPct(curL4LRev, prevL4LRev)!;
    final unitsPct = likeForLikeYoyPct(curL4LUnits, prevL4LUnits)!;
    expect(revPct, closeTo(26.1, 0.05));
    expect(unitsPct, closeTo(15.6, 0.05));
    expect(likeForLikeYoyPct(127140000, 0), isNull);
    expect(sellOutNeedsYoyMonthIntersect(month: null), isTrue);
    expect(sellOutNeedsYoyMonthIntersect(month: 4), isFalse);
    expect(
        sellOutNeedsYoyMonthIntersect(
            startDate: '2026-03-01', endDate: '2026-03-31'),
        isFalse);
  });
}

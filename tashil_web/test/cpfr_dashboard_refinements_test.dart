import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/cpfr_replenishment/presentation/screens/cpfr_dashboard_screen.dart';

class MockCPFRApiClient extends Fake implements ApiClient {
  @override
  Future<List<RetailChainModel>> getRetailChains({String? targetTenant}) async {
    return [
      RetailChainModel(
        chainId: 'chain_fathalla',
        code: 'fathalla',
        displayName: 'أسواق فتح الله (Fathalla Market)',
        tenantId: 'tenant-adeco',
      ),
      RetailChainModel(
        chainId: 'chain_beet',
        code: 'beet-elgomla',
        displayName: 'بيت الجملة (Beet El Gomla)',
        tenantId: 'tenant-adeco',
      ),
      RetailChainModel(
        chainId: 'chain_gomla',
        code: 'gomla',
        displayName: 'جملة ماركت (Gomla Market)',
        tenantId: 'tenant-adeco',
      ),
      RetailChainModel(
        chainId: 'chain_wakala',
        code: 'chain-1080314',
        displayName: 'الوكالة (El Wakala)',
        tenantId: 'tenant-adeco',
      ),
    ];
  }

  @override
  Future<CPFRDashboardModel> fetchCPFRDashboard({
    String chain = 'all',
    String sector = 'all',
    String region = 'all',
    String brand = 'all',
    String rep = 'all',
    String stockStatus = 'all',
    int leadTimeDays = 4,
    int safetyStockDays = 7,
    int? year,
    bool allowLocalFallback = true,
  }) async {
    return CPFRDashboardModel.fromJson({
      'tenant_id': 'tenant-adeco',
      'retailer_chain': chain,
      'source_filename': 'CPFR_MultiChain_Sell_In_Reconciliation.xlsx',
      'total_records': 120,
      'active_skus_count': 15,
      'active_reps_count': 4,
      'sales_manager_name': 'إدارة المبيعات',
      'ka_officer_name': 'إدارة السلاسل',
      'jan_2026_sell_in_egp': 18042301.94,
      'jan_2026_sell_out_egp': 16562833.37,
      'jan_2026_gap_egp': 1479468.57,
      'jan_2026_sell_through_pct': 91.8,
      'ytd_2026_sell_in_egp': 18042301.94,
      'ytd_2026_sell_in_cases': 28059.0,
      'ytd_2026_weight_tons': 331.3,
      'ytd_2026_expected_egp': 19120000.0,
      'oct_w1w2_actual_egp': 0.0,
      'oct_w1w2_actual_cases': 0.0,
      'oct_projected_month_end_egp': 0.0,
      'oct_projected_cases': 0.0,
      'mt_revenue_egp': 18042301.94,
      'mt_share_pct': 100.0,
      'cc_revenue_egp': 0.0,
      'cc_share_pct': 0.0,
      'total_estimated_stock_cases': 3200.0,
      'total_estimated_stock_egp': 2100000.0,
      'total_suggested_po_cases': 4500,
      'total_suggested_po_egp': 2900000.0,
      'total_suggested_po_tons': 54.0,
      'urgent_replenishment_count': 2,
      'overstock_alert_count': 3,
      'lead_time_days': 4,
      'safety_stock_days': 7,
      'monthly_reconciliation': [
        {
          'year': 2026,
          'month_num': 1,
          'month_en': 'Jan',
          'month_ar': 'يناير',
          'period_status': 'مغلق (Full Month)',
          'active_skus_count': 15,
          'sell_in_cases': 28059.2,
          'sell_in_value_egp': 18042302.0,
          'sell_out_units': 336000,
          'sell_out_value_egp': 16562833.0,
          'inventory_gap_egp': 1479469.0,
          'sell_through_rate_pct': 91.8,
          'weight_tons': 331.3,
          'expected_cases': 29500.0,
          'expected_value_egp': 19000000.0,
        },
      ],
      'inventory_and_po_items': [],
      'brand_forecasts': [],
      'region_performances': [],
      'sales_rep_scorecards': [],
      'promo_and_returns': {
        'regular_records_count': 100,
        'promo_records_count': 20,
        'return_records_count': 5,
        'regular_cases': 25000.0,
        'promo_cases': 3059.0,
        'total_return_cases': 120.0,
        'regular_value_egp': 16000000.0,
        'promo_value_egp': 2042301.94,
        'total_return_value_egp': 85000.0,
        'regular_tons': 290.0,
        'promo_tons': 41.3,
        'total_return_tons': 1.5,
        'promo_share_pct': 11.3,
        'return_rate_pct': 0.47,
      },
    });
  }
}

void main() {
  testWidgets(
      'CPFR Dashboard renders English tabs, refined KPI cards and template buttons',
      (tester) async {
    final mockClient = MockCPFRApiClient();

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CPFRDashboardScreen(apiClient: mockClient),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify English tab titles and 4th Arabic tab
    expect(find.text('1. Sell-In vs Sell-Out'), findsOneWidget);
    expect(find.text('2. Suggested PO & Replenishment'), findsOneWidget);
    expect(find.text('3. Demand Forecasting & Promos (EXP)'), findsOneWidget);
    expect(find.text('4. أداء فريق المبيعات وهيكل الحسابات'), findsOneWidget);

    // 2. Verify 4 KPI cards (Arabic-only titles, same as Sell-Out / Sell-In)
    expect(find.text('إجمالي التوريد للسلاسل'), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Sell-In')), findsOneWidget);

    expect(find.text('مبيعات الكاشير الفعلية'), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Sell-Out')), findsOneWidget);

    expect(find.text('معدل دوران المخزون'), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi_card_Sell-Through Rate')),
        findsOneWidget);

    expect(find.text('الفجوة المخزنية'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('kpi_card_Inventory Gap')), findsOneWidget);
    // English labels are keys only — they must not appear as a second title line.
    expect(find.text('Sell-Through Rate'), findsNothing);
    expect(find.text('Inventory Gap'), findsNothing);

    // 3. Verify concise Sell-In upload card header and English Demo buttons
    expect(find.text('بوابة رفع بيانات التوريد Sell-In'), findsOneWidget);
    expect(find.text('Demo Sell-In'), findsOneWidget);
    expect(find.text('Demo Sell-Out'), findsOneWidget);
    expect(find.text('رفع ملف Sell-In هنا'), findsOneWidget);

    // 4. Verify no 'تحديد السلسلة تلقائياً من الملف' in the screen
    expect(find.text('تحديد السلسلة تلقائياً من الملف (Multi-Chain)'),
        findsNothing);

    // 5. Monthly reconciliation uses the shared table container (no custom 1450 min-width).
    expect(find.byKey(const ValueKey('cpfr_reconciliation_table')),
        findsOneWidget);
    expect(find.byTooltip('تمرير الجدول للبداية'), findsNothing);
    expect(find.byTooltip('تمرير الجدول للنهاية'), findsNothing);
  });

  test(
      'ApiClient.fetchCPFRDashboard sanitizes non-ASCII headers and falls back cleanly without throwing',
      () async {
    final client = ApiClient();
    client.currentUser = TenantUserModel(
      userId: 'u_test',
      email: 'test@adeco.com',
      fullName: 'أحمد فتح الله',
      role: 'regional_supervisor',
      tenantId: 'tenant-adeco',
      active: true,
      assignedRegion: 'شرق الإسكندرية',
      assignedChain: 'أسواق فتح الله',
    );

    // Verify headers are strictly ASCII-safe (< 128) so BrowserClient window.fetch never throws TypeError
    for (final entry in client.requestHeaders.entries) {
      for (final unit in entry.value.codeUnits) {
        expect(unit <= 127, isTrue,
            reason: 'Header ${entry.key} contains non-ASCII codeUnit $unit');
      }
    }

    final dashboard = await client.fetchCPFRDashboard(chain: 'all');
    expect(dashboard.monthlyReconciliation, isNotEmpty);
    expect(dashboard.jan2026SellInEgp, greaterThan(0));
  });
}

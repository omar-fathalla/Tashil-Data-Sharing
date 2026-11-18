import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_breakdown_models.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_detail_page.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_management_panel.dart';

Map<String, dynamic> _item(
  String id,
  int year, {
  required double target,
  required double actual,
  required bool hasActuals,
  required double units,
  required double actualUnits,
  int month = 0,
}) =>
    {
      'id': id,
      'target_type': 'sell_out',
      'retailer_chain': 'fathalla',
      'chain_display_name': 'فتح الله',
      'year': year,
      'month': month,
      'month_label': month == 0 ? 'سنة $year' : 'شهر $month',
      'branch_name': 'كل الفروع',
      'category': 'كل الفئات',
      'target_revenue_egp': target,
      'actual_revenue_egp': actual,
      'variance_revenue_egp': actual - target,
      'achievement_rev_pct': target == 0 ? 0 : (actual / target * 1000).round() / 10,
      'target_units': units,
      'actual_units': actualUnits,
      'has_actuals': hasActuals,
      'status': hasActuals ? 'at_risk' : 'no_data',
      'status_ar': hasActuals ? 'أقل من المستهدف' : 'لا توجد مبيعات بعد',
      'monthly_phasing': [
        for (var m = 1; m <= 12; m++)
          {
            'year': year,
            'month': m,
            'month_label_ar': 'm$m',
            'month_label_en': 'm$m',
            'target_revenue_egp': target / 12,
            'target_units': units / 12,
            'actual_revenue_egp': m <= 3 && hasActuals ? actual / 3 : 0,
            'actual_units': m <= 3 && hasActuals ? actualUnits / 3 : 0,
            'achievement_pct': m <= 3 && hasActuals ? 100 : 0,
          },
      ],
    };

Map<String, dynamic> _breakdownJson() => {
      'target_id': 't26',
      'target_type': 'sell_out',
      'retailer_chain': 'fathalla',
      'chain_display_name': 'فتح الله',
      'year': 2026,
      'month': 0,
      'month_label': 'سنة 2026',
      'branch_scope': 'كل الفروع',
      'category_scope': 'كل الفئات',
      'target_revenue_egp': 150000000,
      'target_units': 250000,
      'baseline': {
        'kind': 'prior_year',
        'year': 2025,
        'months_covered': 12,
        'caption_ar': 'حسب حصة 2025',
      },
      'has_actuals': true,
      'actual_revenue_egp': 127135120,
      'actual_units': 1532854,
      'achievement_pct': 84.8,
      'gap_egp': -22864880,
      'branches': [
        {
          'branch_key': 'B',
          'branch_name': 'فرع الزمالك',
          'baseline_revenue_egp': 40000000,
          'share_pct': 40,
          'allocated_target_egp': 60000000,
          'actual_revenue_egp': 30000000,
          'actual_units': 400000,
          'achievement_pct': 50,
          'gap_egp': -30000000,
          'skus': [
            {
              'sku_key': '6224000000001',
              'sku_name': 'منتج أ',
              'share_pct': 100,
              'allocated_target_egp': 60000000,
              'actual_revenue_egp': 30000000,
              'actual_units': 400000,
              'achievement_pct': 50,
              'gap_egp': -30000000,
            },
          ],
        },
        {
          'branch_key': 'A',
          'branch_name': 'فرع المعادي',
          'baseline_revenue_egp': 60000000,
          'share_pct': 60,
          'allocated_target_egp': 90000000,
          'actual_revenue_egp': 97135120,
          'actual_units': 1132854,
          'achievement_pct': 107.9,
          'gap_egp': 7135120,
          'skus': [
            {
              'sku_key': '6224000000002',
              'sku_name': 'منتج ب',
              'share_pct': 100,
              'allocated_target_egp': 90000000,
              'actual_revenue_egp': 97135120,
              'actual_units': 1132854,
              'achievement_pct': 107.9,
              'gap_egp': 7135120,
            },
          ],
        },
      ],
    };

class _FakeRepo extends TargetRepository {
  _FakeRepo(this.items, this.breakdowns)
      : super(ApiClient(tenantId: 'tenant-detail', allowMockFallback: false));

  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> breakdowns;
  final breakdownRequests = <String>[];

  @override
  Future<Result<TargetsSummaryModel>> loadSummary({
    required String targetType,
    String? chain,
    int? year,
    bool forceRefresh = false,
  }) async {
    return Success(TargetsSummaryModel.fromJson({
      'target_type': targetType,
      'total_target_revenue_egp': 150000000,
      'total_actual_revenue_egp': 127135120,
      'items': items,
    }));
  }

  @override
  Future<Result<List<RetailChainModel>>> loadChains(
          {bool forceRefresh = false}) async =>
      const Success(<RetailChainModel>[]);

  @override
  Future<Result<TargetBreakdownModel>> loadBreakdown(
    String targetId, {
    bool forceRefresh = false,
  }) async {
    breakdownRequests.add(targetId);
    final json = breakdowns[targetId];
    if (json == null) {
      return const Failure(AppError.unknown('missing'));
    }
    return Success(TargetBreakdownModel.fromJson(json));
  }
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('toolbar hides upload/template; shows Add + Export only',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo([
      _item('t26', 2026,
          target: 150000000,
          actual: 127135120,
          hasActuals: true,
          units: 250000,
          actualUnits: 1532854),
    ], {
      't26': _breakdownJson(),
    });
    await tester.pumpWidget(_host(TargetManagementPanel(
      apiClient: ApiClient(tenantId: 'tenant-detail', allowMockFallback: false),
      targetType: 'sell_out',
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('إضافة مستهدف'), findsWidgets);
    expect(find.text('تصدير'), findsOneWidget);
    expect(find.text('رفع ملف المستهدفات'), findsNothing);
    expect(find.text('تنزيل القالب'), findsNothing);
  });

  testWidgets('detail page: breadcrumbs, monthly cards, month→branches',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final target = TargetComparisonModel.fromJson(_item('t26', 2026,
        target: 150000000,
        actual: 127135120,
        hasActuals: true,
        units: 250000,
        actualUnits: 1532854));
    final repo = _FakeRepo(const [], {'t26': _breakdownJson()});

    await tester.pumpWidget(_host(TargetDetailPage(
      repository: repo,
      target: target,
      onBack: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('target_detail_page')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_back')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_crumb_root')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_kpi_year')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_cumulative_chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_month_card_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_month_card_12')), findsOneWidget);

    expect(find.byKey(const ValueKey('target_detail_chart_x_axis')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_chart_y_axis')), findsOneWidget);
    // X = short Arabic months; Y = compact M ج.م values.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('target_detail_chart_x_axis')),
        matching: find.text('ينا'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('target_detail_chart_x_axis')),
        matching: find.text('ديس'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('target_detail_chart_y_axis')),
        matching: find.textContaining('M'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('target_detail_chart_y_axis')),
        matching: find.textContaining('ج.م'),
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('target_detail_month_card_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('target_detail_branches_tab')), findsOneWidget);
    expect(find.byKey(const ValueKey('target_detail_unlock_month')), findsOneWidget);
    // Lowest achievement first (فرع الزمالك 50% before فرع المعادي 107.9%).
    final zamalek = tester.getTopLeft(
        find.byKey(const ValueKey('target_detail_branch_row_B')));
    final maadi = tester.getTopLeft(
        find.byKey(const ValueKey('target_detail_branch_row_A')));
    expect(zamalek.dy, lessThan(maadi.dy));

    // SKU barcode under name is LTR-isolated in the branch panel.
    expect(find.textContaining('6224000000001'), findsWidgets);
  });

  testWidgets('branches SKU panel fits 1280 without h-scroll; الصنف header readable',
      (tester) async {
    // Live content width: 1280 − 250 sidebar − 48 page padding.
    const contentW = 1280.0 - 250.0 - 48.0;
    tester.view.physicalSize = const Size(contentW, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final target = TargetComparisonModel.fromJson(_item('t26', 2026,
        target: 150000000,
        actual: 127135120,
        hasActuals: true,
        units: 250000,
        actualUnits: 1532854));
    final repo = _FakeRepo(const [], {'t26': _breakdownJson()});

    await tester.pumpWidget(_host(TargetDetailPage(
      repository: repo,
      target: target,
      onBack: () {},
      initialTab: TargetDetailTab.branches,
    )));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('target_detail_branch_skus_panel'));
    expect(panel, findsOneWidget);
    final skuTable = find.byKey(const ValueKey('target_detail_branch_sku_table'));
    expect(skuTable, findsOneWidget);

    double hScroll() {
      var maxExtent = 0.0;
      for (final e in find
          .descendant(of: panel, matching: find.byType(Scrollable))
          .evaluate()) {
        final state = tester.state<ScrollableState>(
            find.byElementPredicate((x) => x == e));
        if (state.position.axis == Axis.horizontal &&
            state.position.hasContentDimensions &&
            state.position.maxScrollExtent > maxExtent) {
          maxExtent = state.position.maxScrollExtent;
        }
      }
      return maxExtent;
    }

    expect(hScroll(), lessThanOrEqualTo(2.0),
        reason: 'branch SKU panel must fit at ~1280 without h-scroll');
    // Compact layout is a flex Column (no TableScrollContainer h-scroll).
    expect(
      find.descendant(of: skuTable, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );

    final header = find.byKey(const ValueKey('target_detail_sku_header_name'));
    expect(header, findsOneWidget);
    expect(tester.widget<Text>(header).data, 'الصنف');
    final para = tester.renderObject<RenderParagraph>(header);
    expect(para.didExceedMaxLines, isFalse);
    expect(find.text('ال…'), findsNothing);
  });
}

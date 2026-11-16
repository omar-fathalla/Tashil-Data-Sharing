import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/target_table_format.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_management_panel.dart';

import 'support/real_fonts.dart';

/// Live Sell-Out content width: 1280 window − 250 sidebar − 24dp page
/// padding on each side.
const _liveTableWidth = 1280.0 - 250.0 - 48.0;

const _headers = [
  'السلسلة',
  'الفترة (Period)',
  'النطاق',
  'المستهدف',
  'المحقق (ج.م)',
  'الفرق (ج.م)',
  'الكمية (وحدة: فعلي / مستهدف)',
  'نسبة التحقيق %',
  'إجراءات',
];

Map<String, dynamic> _item({
  required String id,
  required int year,
  int month = 0,
  required String monthLabel,
  String branch = 'كل الفروع',
  String category = 'كل الفئات',
  String chain = 'فتح الله',
  required double target,
  required double actual,
  required double variance,
  required double achievement,
  required double units,
  required double actualUnits,
  required bool hasActuals,
  required String statusAr,
}) =>
    {
      'id': id,
      'target_type': 'sell_out',
      'retailer_chain': 'fathalla',
      'chain_display_name': chain,
      'year': year,
      'month': month,
      'month_label': monthLabel,
      'branch_name': branch,
      'category': category,
      'target_revenue_egp': target,
      'actual_revenue_egp': actual,
      'variance_revenue_egp': variance,
      'achievement_rev_pct': achievement,
      'target_units': units,
      'actual_units': actualUnits,
      'has_actuals': hasActuals,
      'status': hasActuals ? 'at_risk' : 'no_data',
      'status_ar': statusAr,
    };

class _FakeRepo extends TargetRepository {
  _FakeRepo(this.items)
      : super(ApiClient(
            tenantId: 'tenant-targets-table', allowMockFallback: false));

  final List<Map<String, dynamic>> items;

  @override
  Future<Result<TargetsSummaryModel>> loadSummary({
    required String targetType,
    String? chain,
    int? year,
    bool forceRefresh = false,
  }) async {
    final filtered =
        items.where((i) => year == null || i['year'] == year).toList();
    double sum(String k) => filtered.fold<double>(
        0, (a, i) => a + ((i[k] as num?)?.toDouble() ?? 0));
    return Success(TargetsSummaryModel.fromJson({
      'target_type': targetType,
      'total_target_revenue_egp': sum('target_revenue_egp'),
      'total_actual_revenue_egp': sum('actual_revenue_egp'),
      'total_variance_egp': sum('variance_revenue_egp'),
      'total_target_units': sum('target_units'),
      'total_actual_units': sum('actual_units'),
      'items': filtered,
    }));
  }

  @override
  Future<Result<List<RetailChainModel>>> loadChains(
          {bool forceRefresh = false}) async =>
      const Success(<RetailChainModel>[]);
}

double _hScroll(WidgetTester tester, Finder scope) {
  var maxExtent = 0.0;
  for (final e in find
      .descendant(of: scope, matching: find.byType(Scrollable))
      .evaluate()) {
    final state =
        tester.state<ScrollableState>(find.byElementPredicate((x) => x == e));
    if (state.position.axis == Axis.horizontal &&
        state.position.hasContentDimensions &&
        state.position.maxScrollExtent > maxExtent) {
      maxExtent = state.position.maxScrollExtent;
    }
  }
  return maxExtent;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealCairoFont();
  });

  final items = [
    _item(
      id: 't26',
      year: 2026,
      monthLabel: 'إجمالي سنة 2026 (كل الشهور)',
      target: 150000000,
      actual: 127135120,
      variance: -22864880,
      achievement: 84.756,
      units: 250000,
      actualUnits: 1532854,
      hasActuals: true,
      statusAr: 'أقل من المستهدف',
    ),
    _item(
      id: 't27',
      year: 2027,
      monthLabel: 'إجمالي سنة 2027 (كل الشهور)',
      target: 180000000,
      actual: 0,
      variance: 0,
      achievement: 0,
      units: 2273513,
      actualUnits: 0,
      hasActuals: false,
      statusAr: 'لا توجد مبيعات بعد',
    ),
    _item(
      id: 't-mar',
      year: 2026,
      month: 3,
      monthLabel: 'مارس 2026',
      branch: 'فرع المعادي',
      category: 'كل الفئات',
      target: 2500,
      actual: 1800,
      variance: -700,
      achievement: 72,
      units: 40,
      actualUnits: 12,
      hasActuals: true,
      statusAr: 'أقل من المستهدف',
    ),
    _item(
      id: 't-q',
      year: 2026,
      monthLabel: 'الربع الأول 2026',
      branch: 'كل الفروع',
      category: 'عصائر',
      target: 8000,
      actual: 7200,
      variance: -800,
      achievement: 90,
      units: 90,
      actualUnits: 80,
      hasActuals: true,
      statusAr: 'قريب من المستهدف',
    ),
    _item(
      id: 't-hi',
      year: 2026,
      month: 6,
      monthLabel: 'يونيو 2026',
      branch: 'فرع الزمالك',
      category: 'زيوت',
      target: 1000,
      actual: 1100,
      variance: 100,
      achievement: 110,
      units: 10,
      actualUnits: 11,
      hasActuals: true,
      statusAr: 'فوق المستهدف',
    ),
  ];

  testWidgets('targets table is compact and fits a 1280 desktop',
      (tester) async {
    tester.view.physicalSize = const Size(_liveTableWidth, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: TargetManagementPanel(
          apiClient: ApiClient(
            tenantId: 'tenant-targets-table',
            allowMockFallback: false,
          ),
          targetType: 'sell_out',
          repository: _FakeRepo(items),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final table = find.byKey(const ValueKey('targets_main_table'));
    expect(table, findsOneWidget);
    expect(
      Directionality.of(tester.element(table)),
      TextDirection.rtl,
    );
    expect(
      _hScroll(tester, table),
      lessThanOrEqualTo(2.0),
      reason: 'table must not scroll horizontally at ~1280',
    );
    expect(find.text('اسحب أو تحرك:'), findsNothing);
    expect(find.text('يمين'), findsNothing);
    expect(find.text('شمال'), findsNothing);

    for (final label in _headers) {
      final head = find.descendant(of: table, matching: find.text(label));
      expect(head, findsOneWidget, reason: label);
      final para = tester.renderObject<RenderParagraph>(head);
      expect(
        para.didExceedMaxLines,
        isFalse,
        reason: '$label w=${para.size.width.toStringAsFixed(1)} '
            'h=${para.size.height.toStringAsFixed(1)}',
      );
      expect(para.size.height, lessThanOrEqualTo(22.0), reason: label);
      final rect = tester.getRect(head);
      expect(rect.left, greaterThanOrEqualTo(-1.0), reason: label);
      expect(rect.right, lessThanOrEqualTo(_liveTableWidth + 1.0),
          reason: label);
    }
    expect(find.text('السلسلة (Chain)'), findsNothing);

    String cell(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    String tip(String key) => tester
        .widget<Tooltip>(find
            .ancestor(
                of: find.byKey(ValueKey(key)), matching: find.byType(Tooltip))
            .first)
        .message!;

    expect(cell('targets_period_t26'), '2026');
    expect(cell('targets_period_t27'), '2027');
    expect(tip('targets_period_t26'), 'إجمالي سنة 2026 (كل الشهور)');
    expect(find.textContaining('كل الشهور'), findsNothing);
    expect(find.textContaining('إجمالي سنة'), findsNothing);
    expect(cell('targets_period_t-mar'), 'مارس 2026');
    expect(cell('targets_period_t-q'), 'Q1 2026');
    expect(cell('targets_period_t-hi'), 'يونيو 2026');

    expect(cell('targets_scope_t26'), 'كل الفروع');
    expect(cell('targets_scope_t27'), 'كل الفروع');
    expect(find.textContaining('كل الفئات'), findsNothing);
    expect(find.text('كل الفروع • كل الفئات'), findsNothing);
    expect(cell('targets_scope_t-mar'), 'فرع المعادي');
    expect(cell('targets_scope_t-q'), 'عصائر');
    expect(cell('targets_scope_t-hi'), 'فرع الزمالك • زيوت');

    expect(
        cell('targets_target_money_t27'), TargetTableFormat.money(180000000));
    expect(tip('targets_target_money_t27'),
        TargetTableFormat.moneyExact(180000000));
    expect(
        cell('targets_actual_money_t26'), TargetTableFormat.money(127135120));
    expect(tip('targets_actual_money_t26'),
        TargetTableFormat.moneyExact(127135120));
    expect(cell('targets_gap_money_t26'), TargetTableFormat.money(-22864880));
    expect(
        tip('targets_gap_money_t26'), TargetTableFormat.moneyExact(-22864880));
    expect(
        cell('targets_qty_t26'),
        TargetTableFormat.quantity(
          actual: 1532854,
          target: 250000,
          unit: 'وحدة',
        ));
    expect(
        tip('targets_qty_t26'),
        TargetTableFormat.quantityExact(
          actual: 1532854,
          target: 250000,
          unit: 'وحدة',
        ));

    for (final key in [
      'targets_target_money_t27',
      'targets_actual_money_t26',
      'targets_gap_money_t26',
      'targets_qty_t26',
      'targets_period_t-mar',
      'targets_scope_t-mar',
    ]) {
      final para =
          tester.renderObject<RenderParagraph>(find.byKey(ValueKey(key)));
      expect(para.didExceedMaxLines, isFalse,
          reason: '$key w=${para.size.width}');
    }

    expect(cell('targets_achievement_t26'), '84.8%');
    expect(cell('targets_achievement_t-q'), '90.0%');
    expect(cell('targets_achievement_t-hi'), '110.0%');
    expect(cell('targets_achievement_t27'), '—');
    for (final id in ['t26', 't27', 't-mar', 't-q', 't-hi']) {
      expect(cell('targets_achievement_$id'), isNot(contains('مستهدف')));
    }

    final ctx = tester.element(find.byType(TargetManagementPanel));
    final scheme = Theme.of(ctx).colorScheme;
    final accents = M3StatusColors.of(ctx).accents;
    Color chipColor(String id) => tester
        .widget<Text>(find.byKey(ValueKey('targets_achievement_$id')))
        .style!
        .color!;
    expect(chipColor('t26'), scheme.error);
    expect(chipColor('t-q'), accents.caution);
    expect(chipColor('t-hi'), accents.positive);
    expect(chipColor('t27'), scheme.onSurfaceVariant);

    expect(
        find.byKey(const ValueKey('targets_actual_dash_t27')), findsOneWidget);
    expect(
        cell('targets_qty_t27'),
        TargetTableFormat.quantity(
          actual: null,
          target: 2273513,
          unit: 'وحدة',
        ));
    expect(find.text('لا توجد مبيعات بعد'), findsOneWidget);
    expect(find.text('0.0%'), findsNothing);
    expect(find.text('0 ج.م'), findsNothing);
  });
}

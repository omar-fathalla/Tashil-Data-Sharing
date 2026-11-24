import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/network/backend_http.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/sell_in_targets_export.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_management_panel.dart';

import 'support/real_fonts.dart';

/// Live Sell-In content width: 1280 window − 250 sidebar − 24dp page padding
/// on each side.
const _liveTableWidth = 1280.0 - 250.0 - 48.0;

Map<String, dynamic> _sku({
  required String code,
  required String name,
  required String brand,
  required double pieces,
  double? cases,
  double actualPieces = 0,
  double value = 0,
  double actualValue = 0,
  bool packSizeMissing = false,
  bool costMissing = false,
}) =>
    {
      'item_code': code,
      'sku_name': name,
      'brand': brand,
      'target_units': pieces,
      'target_pieces': pieces.round(),
      'actual_units': actualPieces,
      'actual_pieces': actualPieces.round(),
      'target_revenue_egp': value,
      'actual_revenue_egp': actualValue,
      if (cases != null) 'target_cases': cases,
      if (packSizeMissing) 'pack_size_missing': true,
      if (costMissing) 'cost_missing': true,
    };

Map<String, dynamic> _item({
  String id = 'derived_si_from_so1',
  String sourceId = 'so1',
  int month = 3,
  double pieces = 250000,
  double? cases = 10000,
  double actualPieces = 200000,
  double? actualCases = 8000,
  double value = 5000000,
  double actualValue = 4200000,
  bool hasActuals = true,
  bool excluded = false,
  int packMissing = 0,
  int costMissing = 0,
  List<Map<String, dynamic>>? skus,
}) =>
    {
      'id': id,
      'source_target_id': sourceId,
      'derived': true,
      'target_type': 'sell_in',
      'retailer_chain': 'fathalla',
      'chain_display_name': 'أسواق فتح الله',
      'year': 2026,
      'month': month,
      'month_label': 'مارس 2026',
      'branch_name': 'كل الفروع',
      'category': 'كل الفئات',
      'target_units': pieces,
      if (cases != null) 'target_cases': cases,
      'actual_units': actualPieces,
      if (actualCases != null) 'actual_cases': actualCases,
      'variance_units': actualPieces - pieces,
      'achievement_units_pct': pieces > 0 ? actualPieces / pieces * 100 : 0,
      'target_revenue_egp': value,
      'actual_revenue_egp': actualValue,
      'variance_revenue_egp': actualValue - value,
      'achievement_rev_pct': value > 0 ? actualValue / value * 100 : 0,
      'has_actuals': hasActuals,
      'status': 'at_risk',
      'status_ar': 'أقل من المستهدف',
      if (excluded) 'excluded_from_totals': true,
      if (excluded) 'excluded_reason': 'superseded_by_monthly',
      if (packMissing > 0) 'pack_size_missing_skus': packMissing,
      if (costMissing > 0) 'cost_missing_skus': costMissing,
      'branches': [
        {
          'branch_code': 'b1',
          'branch_name': 'فرع المعادي',
          'target_units': pieces,
          if (cases != null) 'target_cases': cases,
          'actual_units': actualPieces,
          'target_revenue_egp': value,
          'actual_revenue_egp': actualValue,
          'achievement_units_pct': pieces > 0 ? actualPieces / pieces * 100 : 0,
          'achievement_rev_pct': value > 0 ? actualValue / value * 100 : 0,
        },
      ],
      'chain_sku_totals': skus ??
          [
            _sku(
              code: 'FB-1',
              name: 'فيبا مناديل 100',
              brand: 'فيبا',
              pieces: 150000,
              cases: 6000,
              actualPieces: 120000,
              value: 3000000,
              actualValue: 2500000,
            ),
            _sku(
              code: 'XX-9',
              name: 'صنف بدون براند',
              brand: '',
              pieces: 100000,
              cases: 4000,
              actualPieces: 80000,
              value: 2000000,
              actualValue: 1700000,
            ),
          ],
    };

Map<String, dynamic> _branch({
  required String code,
  required String name,
  required List<Map<String, dynamic>> skus,
  bool unassigned = false,
}) {
  double sum(String k) =>
      skus.fold(0.0, (a, s) => a + ((s[k] as num?)?.toDouble() ?? 0));
  final tu = sum('target_units');
  final au = sum('actual_units');
  final tv = sum('target_revenue_egp');
  final av = sum('actual_revenue_egp');
  return {
    'branch_code': code,
    'branch_name': name,
    'target_units': tu,
    'actual_units': au,
    'target_revenue_egp': tv,
    'actual_revenue_egp': av,
    'achievement_units_pct': tu > 0 ? au / tu * 100 : 0,
    'achievement_rev_pct': tv > 0 ? av / tv * 100 : 0,
    if (unassigned) 'unassigned': true,
    'skus': skus,
  };
}

/// A 2026 annual target with two branches whose SKUs carry achievement (the
/// production «توزيع المستهدف» drill-down), one branch without Sell-In and
/// the «غير محدد الفرع» line (Sell-In rows that name no branch).
Map<String, dynamic> _branchItem() => {
      ..._item(month: 0, pieces: 1000, actualPieces: 600),
      'month_label': '',
      'branches': [
        _branch(code: 'fat_smouha', name: 'فرع فتح الله - سموحة', skus: [
          _sku(
              code: 'FB-2',
              name: 'فيبا صغير',
              brand: 'فيبا',
              pieces: 100,
              cases: 10,
              actualPieces: 50,
              value: 1000,
              actualValue: 500),
          _sku(
              code: 'FB-1',
              name: 'فيبا كبير',
              brand: 'فيبا',
              pieces: 400,
              cases: 40,
              actualPieces: 300,
              value: 4000,
              actualValue: 3000),
          _sku(
              code: 'DV-1',
              name: 'ديفا بدون عبوة',
              brand: 'ديفا',
              pieces: 200,
              actualPieces: 150,
              packSizeMissing: true,
              costMissing: true),
        ]),
        _branch(code: 'fat_tanta', name: 'فرع فتح الله - طنطا', skus: [
          _sku(
              code: 'FB-1',
              name: 'فيبا كبير',
              brand: 'فيبا',
              pieces: 300,
              cases: 30,
              actualPieces: 100,
              value: 3000,
              actualValue: 1000),
        ]),
        _branch(code: 'fat_nice', name: 'فرع فتح الله - نيس', skus: [
          _sku(code: 'FB-1', name: 'فيبا كبير', brand: 'فيبا', pieces: 50),
        ]),
        _branch(
            code: '__unassigned__',
            name: 'غير محدد الفرع',
            unassigned: true,
            skus: [
              _sku(
                  code: 'FB-1',
                  name: 'فيبا كبير',
                  brand: 'فيبا',
                  pieces: 0,
                  actualPieces: 80,
                  value: 0,
                  actualValue: 800),
            ]),
      ],
    };

Future<void> _openBranchDrillDown(WidgetTester tester) async {
  await tester
      .tap(find.byKey(const ValueKey('sellin_chain_derived_si_from_so1')));
  await tester.pumpAndSettle();
}

Future<void> _toggleBranch(WidgetTester tester, String code, String name) async {
  final row = find.byKey(ValueKey('sellin_branch_${code}_$name'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

String _cellText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!.replaceAll('\u2060', '');

Map<String, dynamic> _summaryJson(
  List<Map<String, dynamic>> items, {
  List<String> brands = const ['فيبا', 'ديفا', kNoBrandLabelAr],
  int sellOutCount = 1,
  double? targetCases = 10000,
  double? actualCases = 8000,
  int packMissing = 0,
  int costMissing = 0,
  int excluded = 0,
}) {
  double sum(String k) =>
      items.fold(0.0, (a, i) => a + ((i[k] as num?)?.toDouble() ?? 0));
  final tu = sum('target_units');
  final au = sum('actual_units');
  return {
    'target_type': 'sell_in',
    'derived': true,
    'quantity_unit': 'pieces',
    'total_target_units': tu,
    'total_actual_units': au,
    if (targetCases != null && items.isNotEmpty)
      'total_target_cases': targetCases,
    if (actualCases != null && items.isNotEmpty)
      'total_actual_cases': actualCases,
    'total_target_revenue_egp': sum('target_revenue_egp'),
    'total_actual_revenue_egp': sum('actual_revenue_egp'),
    'overall_achievement_pct': tu > 0 ? au / tu * 100 : 0,
    'overall_achievement_rev_pct': sum('target_revenue_egp') > 0
        ? sum('actual_revenue_egp') / sum('target_revenue_egp') * 100
        : 0,
    'available_brands': brands,
    'sell_out_targets_count': sellOutCount,
    'pack_size_missing_skus_count': packMissing,
    'cost_missing_skus_count': costMissing,
    'excluded_from_totals_count': excluded,
    'items': items,
  };
}

class _FakeRepo extends TargetRepository {
  _FakeRepo(this.respond)
      : super(ApiClient(
            tenantId: 'tenant-sellin-derived', allowMockFallback: false));

  final Map<String, dynamic> Function(List<String> brands) respond;
  final List<List<String>> brandCalls = [];

  @override
  Future<Result<TargetsSummaryModel>> loadDerivedSellInSummary({
    String? chain,
    int? year,
    List<String> brands = const [],
    bool forceRefresh = false,
  }) async {
    brandCalls.add([...brands]);
    return Success(TargetsSummaryModel.fromJson(respond(brands)));
  }

  @override
  Future<Result<List<RetailChainModel>>> loadChains(
          {bool forceRefresh = false}) async =>
      const Success(<RetailChainModel>[]);
}

Future<void> _pump(
  WidgetTester tester,
  TargetRepository repo, {
  VoidCallback? onOpen,
  double width = 1280.0 - 250.0,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: TargetManagementPanel(
          apiClient: ApiClient(
              tenantId: 'tenant-sellin-derived', allowMockFallback: false),
          targetType: 'sell_in',
          repository: repo,
          onOpenSellOutTargets: onOpen,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
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

  group('Sell-In targets tab (derived, read-only)', () {
    testWidgets('removes add / upload / template, keeps export + filters',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_item()]));
      await _pump(tester, repo);

      expect(find.text('إضافة مستهدف'), findsNothing);
      expect(find.text('رفع ملف المستهدفات'), findsNothing);
      expect(find.text('تنزيل القالب'), findsNothing);

      expect(find.text('تصدير'), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_year_filter')), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_chain_filter')), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_brand_filter')), findsOneWidget);
    });

    testWidgets('shows the derived badge and the edit Sell-Out button',
        (tester) async {
      var opened = 0;
      final repo = _FakeRepo((_) => _summaryJson([_item()]));
      await _pump(tester, repo, onOpen: () => opened++);

      expect(find.text('محسوب تلقائياً من مستهدف Sell-Out'), findsOneWidget);
      expect(find.text('تعديل مستهدف Sell-Out'), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('sellin_edit_sellout_targets')));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('table is read-only: no edit, delete or actions column',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_item()]));
      await _pump(tester, repo);

      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.text('إجراءات'), findsNothing);
      expect(find.text('تعديل المستهدف'), findsNothing);
      expect(find.text('حذف المستهدف'), findsNothing);
    });

    testWidgets('KPIs show quantity first (pieces and cases), then value',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_item()]));
      await _pump(tester, repo);

      final order = [
        'sellin_kpi_target_qty',
        'sellin_kpi_actual_qty',
        'sellin_kpi_achievement_qty',
        'sellin_kpi_value',
      ];
      final dx = [
        for (final k in order) tester.getTopLeft(find.byKey(ValueKey(k))).dx,
      ];
      expect(find.text('مستهدف التوريد (كمية)'), findsOneWidget);
      expect(find.text('250,000 قطعة'), findsOneWidget);
      expect(find.text('10,000 كرتونة'), findsOneWidget);
      expect(find.text('200,000 قطعة'), findsOneWidget);
      expect(find.text('8,000 كرتونة'), findsOneWidget);
      expect(find.text('80.0%'), findsNWidgets(2)); // KPI card + table row
      expect(find.text('القيمة (سعر التكلفة)'), findsOneWidget);
      final ascending = dx.first < dx.last;
      for (var i = 1; i < dx.length; i++) {
        expect(ascending ? dx[i] > dx[i - 1] : dx[i] < dx[i - 1], isTrue,
            reason: 'KPI ${order[i]} must follow ${order[i - 1]}');
      }
    });

    testWidgets('missing pack size shows pieces with cases as —',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson(
            [
              _item(
                cases: null,
                actualCases: null,
                packMissing: 2,
                skus: [
                  _sku(
                    code: 'NP-1',
                    name: 'صنف بدون عبوة',
                    brand: 'فيبا',
                    pieces: 250000,
                    actualPieces: 200000,
                    value: 5000000,
                    actualValue: 4200000,
                    packSizeMissing: true,
                  ),
                ],
              ),
            ],
            targetCases: null,
            actualCases: null,
            packMissing: 2,
          ));
      await _pump(tester, repo);

      expect(find.text('250,000 قطعة'), findsOneWidget);
      expect(find.text('— كرتونة'), findsWidgets);
      final casesCell = tester.widget<Text>(find
          .byKey(const ValueKey('sellin_target_cases_derived_si_from_so1')));
      expect(casesCell.data, '—');
      final piecesCell = tester.widget<Text>(find
          .byKey(const ValueKey('sellin_target_pieces_derived_si_from_so1')));
      expect(piecesCell.data!.replaceAll('\u2060', ''), '250K');
      expect(find.byKey(const ValueKey('sellin_notice_pack_size')),
          findsOneWidget);
    });

    testWidgets('12 columns fit the live width without horizontal scroll',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([
            _item(),
            _item(
              id: 'derived_si_from_so2',
              sourceId: 'so2',
              month: 0,
              excluded: true,
              pieces: 1530000,
              cases: 61200,
              actualPieces: 1532854,
              actualCases: 61300,
              value: 150000000,
              actualValue: 127135120,
            ),
          ], excluded: 1));
      await _pump(tester, repo, width: _liveTableWidth + 48.0);

      const headers = [
        'السلسلة',
        'الفترة',
        'النطاق',
        'مستهدف قطعة',
        'مستهدف كرتونة',
        'محقق قطعة',
        'فرق قطعة',
        'تحقيق الكمية',
        'مستهدف ج.م',
        'محقق ج.م',
        'فرق ج.م',
        'تحقيق القيمة',
      ];
      final table = find.byKey(const ValueKey('sellin_targets_main_table'));
      for (final h in headers) {
        expect(
            find.descendant(of: table, matching: find.text(h)), findsOneWidget,
            reason: 'header $h');
      }
      expect(_hScroll(tester, table), lessThan(2.0),
          reason: 'no horizontal scroll at the live 1280 shell width');
      expect(
          find.byKey(const ValueKey('sellin_notice_excluded')), findsOneWidget);
    });

    testWidgets('empty state offers «إنشاء مستهدف Sell-Out»', (tester) async {
      var opened = 0;
      final repo = _FakeRepo(
          (_) => _summaryJson(const [], brands: const [], sellOutCount: 0));
      await _pump(tester, repo, onOpen: () => opened++);

      expect(
          find.byKey(const ValueKey('sellin_targets_empty')), findsOneWidget);
      expect(find.text('إنشاء مستهدف Sell-Out'), findsOneWidget);
      expect(find.text('إضافة مستهدف'), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('sellin_create_sellout_target')));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets(
        'brand filter is multi-select, refreshes data, and offers «بدون براند»',
        (tester) async {
      final repo = _FakeRepo((brands) {
        if (brands.isEmpty) return _summaryJson([_item()]);
        if (brands.contains('ديفا')) {
          return _summaryJson(const [], sellOutCount: 1);
        }
        return _summaryJson([
          _item(
              pieces: 150000,
              cases: 6000,
              actualPieces: 120000,
              value: 3000000,
              actualValue: 2500000,
              skus: [
                _sku(
                    code: 'FB-1',
                    name: 'فيبا مناديل 100',
                    brand: 'فيبا',
                    pieces: 150000,
                    cases: 6000,
                    value: 3000000),
              ]),
        ]);
      });
      await _pump(tester, repo);
      expect(find.text('250,000 قطعة'), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('sellin_brand_filter_button')));
      await tester.pumpAndSettle();
      expect(find.text(kNoBrandLabelAr), findsOneWidget);
      expect(find.text('ديفا'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sellin_brand_option_فيبا')).first);
      await tester.pumpAndSettle();
      expect(repo.brandCalls.last, ['فيبا']);
      expect(find.text('150,000 قطعة'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sellin_brand_option_ديفا')).first);
      await tester.pumpAndSettle();
      expect(repo.brandCalls.last.toSet(), {'فيبا', 'ديفا'});
      // Nothing matches both: filtered-empty state with its own message.
      expect(find.byKey(const ValueKey('sellin_targets_empty_brand')),
          findsOneWidget);
      expect(find.text('إنشاء مستهدف Sell-Out'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sellin_clear_brand_filter')));
      await tester.pumpAndSettle();
      expect(repo.brandCalls.last, isEmpty);
      expect(find.text('250,000 قطعة'), findsOneWidget);
    });

    testWidgets(
        'selecting a row shows branches and SKUs with brand («بدون براند» for no brand)',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_item()]));
      await _pump(tester, repo);

      await tester
          .tap(find.byKey(const ValueKey('sellin_chain_derived_si_from_so1')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('sellin_targets_detail')), findsOneWidget);
      expect(find.text('فرع المعادي'), findsOneWidget);
      expect(find.text('فيبا'), findsOneWidget);
      expect(find.text(kNoBrandLabelAr), findsWidgets);
      expect(_hScroll(tester, find.byKey(const ValueKey('sellin_skus_table'))),
          lessThan(2.0));
    });

    testWidgets('branch rows show their achievement instead of «—»',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_branchItem()]));
      await _pump(tester, repo);
      await _openBranchDrillDown(tester);

      expect(find.text('الفروع (3)'), findsOneWidget);
      expect(_cellText(tester, 'sellin_branch_actual_fat_smouha'), '500');
      expect(_cellText(tester, 'sellin_branch_qty_pct_fat_smouha'), '71.4%');
      expect(_cellText(tester, 'sellin_branch_actual_value_fat_smouha'),
          isNot('—'));
      expect(_cellText(tester, 'sellin_branch_value_pct_fat_smouha'), '70.0%');
      expect(_cellText(tester, 'sellin_branch_qty_pct_fat_tanta'), '33.3%');
      // A branch with no Sell-In at all still reads «—».
      expect(_cellText(tester, 'sellin_branch_actual_fat_nice'), '—');
      expect(_cellText(tester, 'sellin_branch_qty_pct_fat_nice'), '—');
    });

    testWidgets(
        'Sell-In without a branch is its own «غير محدد الفرع» line, never distributed',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_branchItem()]));
      await _pump(tester, repo);
      await _openBranchDrillDown(tester);

      // Real branches only in the count; the line is last and flagged.
      expect(find.text('الفروع (3)'), findsOneWidget);
      final row = find.byKey(
          const ValueKey('sellin_branch___unassigned___غير محدد الفرع'));
      expect(row, findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_branch_unassigned_icon')),
          findsOneWidget);
      final ys = [
        for (final code in ['fat_smouha', 'fat_tanta', 'fat_nice', '__unassigned__'])
          tester
              .getTopLeft(find.byKey(ValueKey('sellin_branch_actual_$code')))
              .dy,
      ];
      expect(ys.last, greaterThan(ys.take(3).reduce((a, b) => a > b ? a : b)));
      expect(_cellText(tester, 'sellin_branch_actual___unassigned__'), '80');
      expect(_cellText(tester, 'sellin_branch_qty_pct___unassigned__'), '—');
      expect(_cellText(tester, 'sellin_branch_value_pct___unassigned__'), '—');
      // Branch actuals are only their own rows (no share of the 80 pieces).
      expect(_cellText(tester, 'sellin_branch_actual_fat_smouha'), '500');
      expect(_cellText(tester, 'sellin_branch_actual_fat_nice'), '—');
      expect(_cellText(tester, 'sellin_branches_hint'),
          contains('«غير محدد الفرع» ولا توزَّع على الفروع'));
      expect(find.textContaining('مجمع الإقليم موزعة'), findsNothing);

      await _toggleBranch(tester, '__unassigned__', 'غير محدد الفرع');
      expect(find.byKey(const ValueKey('sellin_branch_skus___unassigned__')),
          findsOneWidget);
      expect(find.text('أصناف غير محدد الفرع (1)'), findsOneWidget);
    });

    testWidgets(
        'tapping a branch expands its SKUs inline (largest target first) and collapses',
        (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_branchItem()]));
      await _pump(tester, repo);
      await _openBranchDrillDown(tester);

      expect(find.byKey(const ValueKey('sellin_branch_skus_fat_smouha')),
          findsNothing);
      await _toggleBranch(tester, 'fat_smouha', 'فرع فتح الله - سموحة');

      final section =
          find.byKey(const ValueKey('sellin_branch_skus_fat_smouha'));
      expect(section, findsOneWidget);
      expect(find.text('أصناف فرع فتح الله - سموحة (3)'), findsOneWidget);
      for (final h in [
        'الصنف',
        'العلامة التجارية',
        'مستهدف قطعة',
        'مستهدف كرتونة',
        'محقق قطعة',
        'تحقيق الكمية',
        'مستهدف ج.م',
        'محقق ج.م',
        'تحقيق القيمة',
      ]) {
        expect(find.descendant(of: section, matching: find.text(h)),
            findsOneWidget,
            reason: 'header $h');
      }
      final order = ['FB-1', 'DV-1', 'FB-2'];
      final ys = [
        for (final code in order)
          tester
              .getTopLeft(find.descendant(
                  of: section, matching: find.text(code)))
              .dy,
      ];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue,
          reason: 'SKUs sorted by target pieces desc: $ys');
      expect(
          find.descendant(of: section, matching: find.text('75.0%')),
          findsWidgets); // FB-1: 300 / 400
      // Missing pack size reads «—»; missing cost is flagged, not estimated.
      expect(
          find.byKey(const ValueKey(
              'sellin_branch_sku_fat_smouha_cost_missing_DV-1')),
          findsOneWidget);
      expect(
          _hScroll(tester,
              find.byKey(const ValueKey('sellin_branch_skus_table_fat_smouha'))),
          lessThan(2.0));
      // Only the tapped branch is expanded.
      expect(find.byKey(const ValueKey('sellin_branch_skus_fat_tanta')),
          findsNothing);

      await _toggleBranch(tester, 'fat_smouha', 'فرع فتح الله - سموحة');
      expect(section, findsNothing);
    });

    testWidgets('branch SKUs respect the brand filter', (tester) async {
      final repo = _FakeRepo((_) => _summaryJson([_branchItem()]));
      await _pump(tester, repo);
      await tester
          .tap(find.byKey(const ValueKey('sellin_brand_filter_button')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('sellin_brand_option_فيبا')).first);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await _openBranchDrillDown(tester);
      await _toggleBranch(tester, 'fat_smouha', 'فرع فتح الله - سموحة');

      final section =
          find.byKey(const ValueKey('sellin_branch_skus_fat_smouha'));
      expect(find.text('أصناف فرع فتح الله - سموحة (2)'), findsOneWidget);
      expect(find.descendant(of: section, matching: find.text('DV-1')),
          findsNothing);
    });

    testWidgets(
        'per-branch export holds only that branch; «تصدير كل الفروع» holds all',
        (tester) async {
      ExcelExportService.resetDownloadHistory();
      addTearDown(ExcelExportService.resetDownloadHistory);
      final repo = _FakeRepo((_) => _summaryJson([_branchItem()]));
      await _pump(tester, repo);
      await _openBranchDrillDown(tester);
      await _toggleBranch(tester, 'fat_tanta', 'فرع فتح الله - طنطا');

      final export =
          find.byKey(const ValueKey('sellin_branch_export_fat_tanta'));
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      final name = ExcelExportService.lastDownloadedFilename!;
      expect(name, contains('فرع_فتح_الله_-_طنطا'));
      expect(name, contains('2026'));
      final lines = ExcelExportService.lastDownloadedContent!
          .trim()
          .split('\n')
          .skip(1)
          .toList();
      expect(lines, hasLength(1));
      expect(lines.single, contains('فرع فتح الله - طنطا'));
      expect(lines.single, isNot(contains('سموحة')));

      final all = find.byKey(const ValueKey('sellin_branches_export_all'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(ExcelExportService.lastDownloadedFilename, contains('كل_الفروع'));
      final content = ExcelExportService.lastDownloadedContent!;
      expect(content, contains('سموحة'));
      expect(content, contains('طنطا'));
      expect(content, contains('نيس'));
      expect(content, contains('غير محدد الفرع'));
    });

    testWidgets('load failure shows a retry state, not an empty list',
        (tester) async {
      final repo = _FailingRepo();
      await _pump(tester, repo);
      expect(
          find.byKey(const ValueKey('sellin_targets_error')), findsOneWidget);
      expect(find.byKey(const ValueKey('sellin_targets_empty')), findsNothing);
    });

    testWidgets('a slow (20s) response still renders the targets (60s timeout)',
        (tester) async {
      expect(ApiClient.derivedSellInTargetsTimeout,
          const Duration(seconds: 60));
      addTearDown(BackendHttp.cache.clear);
      var sellInCalls = 0;
      final server = MockClient((req) async {
        if (req.url.queryParameters['target_type'] != 'sell_in') {
          return http.Response('[]', 200);
        }
        sellInCalls++;
        await Future<void>.delayed(const Duration(seconds: 20));
        return http.Response(jsonEncode(_summaryJson([_item()])), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      await http.runWithClient(() async {
        await _pump(tester, _NetworkRepo());
        await tester.pump(const Duration(seconds: 21));
        await tester.pumpAndSettle();
      }, () => server);

      expect(sellInCalls, 1);
      expect(find.byKey(const ValueKey('sellin_targets_error')), findsNothing);
      expect(find.text('تعذّر تحميل مستهدفات Sell-In.'), findsNothing);
      expect(find.text('250,000 قطعة'), findsOneWidget);
    });
  });

  group('SellInTargetsExport', () {
    test('has a Brand column and groups no-brand SKUs', () {
      final summary = TargetsSummaryModel.fromJson(_summaryJson([_item()]));
      final export = SellInTargetsExport.from(summary);
      final brandCol = export.headers.indexOf('العلامة التجارية (Brand)');
      expect(brandCol, greaterThanOrEqualTo(0));
      expect(export.rows.map((r) => r[brandCol]).toSet(),
          {'فيبا', kNoBrandLabelAr});
      // Quantity (pieces then cases) comes before value (EGP).
      expect(export.headers.indexOf('المستهدف (قطعة)'),
          lessThan(export.headers.indexOf('المستهدف (ج.م)')));
      expect(export.headers.indexOf('المستهدف (كرتونة)'),
          lessThan(export.headers.indexOf('المستهدف (ج.م)')));
    });

    test('respects the brand filter', () {
      final summary = TargetsSummaryModel.fromJson(_summaryJson([_item()]));
      final only = SellInTargetsExport.from(summary, brands: const ['فيبا']);
      final brandCol = only.headers.indexOf('العلامة التجارية (Brand)');
      expect(only.rows, hasLength(1));
      expect(only.rows.single[brandCol], 'فيبا');

      final noBrand =
          SellInTargetsExport.from(summary, brands: const [kNoBrandLabelAr]);
      expect(noBrand.rows, hasLength(1));
      expect(noBrand.rows.single[brandCol], kNoBrandLabelAr);
    });

    test('leaves cases and value blank when pack size / cost are missing', () {
      final summary = TargetsSummaryModel.fromJson(_summaryJson([
        _item(skus: [
          _sku(
            code: 'NP-1',
            name: 'صنف',
            brand: 'فيبا',
            pieces: 1000,
            packSizeMissing: true,
            costMissing: true,
          ),
        ]),
      ]));
      final export = SellInTargetsExport.from(summary);
      final row = export.rows.single;
      expect(row[export.headers.indexOf('المستهدف (قطعة)')], 1000);
      expect(row[export.headers.indexOf('المستهدف (كرتونة)')], '');
      expect(row[export.headers.indexOf('المستهدف (ج.م)')], '');
    });
  });

  group('SellInTargetsExport.branches', () {
    TargetComparisonModel item() =>
        TargetsSummaryModel.fromJson(_summaryJson([_branchItem()])).items.single;

    test('one branch: its SKUs with chain, year, month, branch and Brand', () {
      final t = item();
      final smouha = t.branches.first;
      final export = SellInTargetsExport.branches(t, [smouha]);
      final h = export.headers;
      for (final col in [
        'السلسلة',
        'السنة',
        'الشهر',
        'الفرع',
        'العلامة التجارية (Brand)',
        'كود الصنف',
        'الصنف',
        'المستهدف (قطعة)',
        'المستهدف (كرتونة)',
        'المحقق (قطعة)',
        'نسبة تحقيق الكمية %',
        'المستهدف (ج.م)',
        'المحقق (ج.م)',
        'نسبة تحقيق القيمة %',
      ]) {
        expect(h, contains(col));
      }
      expect(export.rows, hasLength(3));
      expect(export.rows.map((r) => r[h.indexOf('كود الصنف')]).toList(),
          ['FB-1', 'DV-1', 'FB-2']);
      final first = export.rows.first;
      expect(first[h.indexOf('السلسلة')], 'أسواق فتح الله');
      expect(first[h.indexOf('السنة')], 2026);
      expect(first[h.indexOf('الشهر')], 'سنوي');
      expect(first[h.indexOf('الفرع')], 'فرع فتح الله - سموحة');
      expect(first[h.indexOf('المحقق (قطعة)')], 300);
      expect(first[h.indexOf('نسبة تحقيق الكمية %')], 75.0);

      final dv = export.rows[1];
      expect(dv[h.indexOf('المستهدف (كرتونة)')], '—');
      expect(dv[h.indexOf('المستهدف (ج.م)')], '');
      expect(dv[h.indexOf('ملاحظات')], contains('بدون سعر تكلفة'));
    });

    test('brand filter and file names', () {
      final t = item();
      final only = SellInTargetsExport.branches(t, t.branches,
          brands: const ['ديفا']);
      expect(only.rows, hasLength(1));
      expect(SellInTargetsExport.branchFileName(t, branch: t.branches[1]),
          'tashil_sell_in_targets_fathalla_فرع_فتح_الله_-_طنطا_2026.csv');
      expect(SellInTargetsExport.branchFileName(t),
          'tashil_sell_in_targets_fathalla_كل_الفروع_2026.csv');
    });

    test('parses the «غير محدد الفرع» line and exports it without a code', () {
      final t = item();
      expect(t.branches.where((b) => b.unassigned).map((b) => b.branchName),
          ['غير محدد الفرع']);
      expect(t.branches.first.unassigned, isFalse);
      final export = SellInTargetsExport.branches(
          t, t.branches.where((b) => b.unassigned));
      final h = export.headers;
      final row = export.rows.single;
      expect(row[h.indexOf('الفرع')], 'غير محدد الفرع');
      expect(row[h.indexOf('كود الفرع')], '');
      expect(row[h.indexOf('المحقق (قطعة)')], 80);
      expect(row[h.indexOf('ملاحظات')], contains('بدون فرع محدد'));
    });
  });

  group('Derived Sell-In models', () {
    test('parse derived fields and keep older payloads working', () {
      final m = TargetsSummaryModel.fromJson(_summaryJson(
        [_item(packMissing: 1, costMissing: 2, excluded: true)],
        packMissing: 1,
        costMissing: 2,
        excluded: 1,
      ));
      expect(m.derived, isTrue);
      expect(m.totalTargetCases, 10000);
      expect(m.availableBrands, contains(kNoBrandLabelAr));
      expect(m.sellOutTargetsCount, 1);
      final item = m.items.single;
      expect(item.derived, isTrue);
      expect(item.sourceTargetId, 'so1');
      expect(item.excludedFromTotals, isTrue);
      expect(item.packSizeMissingSkus, 1);
      expect(item.costMissingSkus, 2);
      expect(item.branches.single.targetCases, 10000);

      final legacy = TargetsSummaryModel.fromJson(
          {'target_type': 'sell_out', 'items': <dynamic>[]});
      expect(legacy.derived, isFalse);
      expect(legacy.totalTargetCases, isNull);
      expect(legacy.availableBrands, isEmpty);
    });
  });
}

/// Loads Sell-In targets through the real [ApiClient] (HTTP served by a [MockClient]).
class _NetworkRepo extends TargetRepository {
  _NetworkRepo()
      : super(ApiClient(
            tenantId: 'tenant-sellin-derived-slow', allowMockFallback: false));

  @override
  Future<Result<List<RetailChainModel>>> loadChains(
          {bool forceRefresh = false}) async =>
      const Success(<RetailChainModel>[]);
}

class _FailingRepo extends TargetRepository {
  _FailingRepo()
      : super(ApiClient(
            tenantId: 'tenant-sellin-derived-fail', allowMockFallback: false));

  @override
  Future<Result<TargetsSummaryModel>> loadDerivedSellInSummary({
    String? chain,
    int? year,
    List<String> brands = const [],
    bool forceRefresh = false,
  }) async =>
      const Failure(AppError.network());

  @override
  Future<Result<List<RetailChainModel>>> loadChains(
          {bool forceRefresh = false}) async =>
      const Success(<RetailChainModel>[]);
}

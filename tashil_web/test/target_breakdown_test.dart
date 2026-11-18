import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/result.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_breakdown_models.dart';
import 'package:tashil_web/features/sell_out_analytics/data/target_repository.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/target_breakdown_export.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_breakdown_dialog.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/target_management_panel.dart';

final int _baseYear = DateTime.now().year >= 2026 ? DateTime.now().year : 2026;

Map<String, dynamic> _sku(
  String key,
  String name, {
  required double share,
  required double target,
  int? units,
  double? cartons,
  double? price,
  double actual = 0,
  int actualUnits = 0,
  double? ach,
  double gap = 0,
}) =>
    {
      'sku_key': key,
      'sku_name': name,
      'category': 'عصائر',
      'units_per_carton': cartons == null ? 0 : 12,
      'baseline_revenue_egp': share * 1000,
      'share_pct': share,
      'avg_unit_price_egp': price,
      'allocated_target_egp': target,
      'allocated_target_units': units,
      'allocated_target_cartons': cartons,
      'actual_revenue_egp': actual,
      'actual_units': actualUnits,
      'achievement_pct': ach,
      'gap_egp': gap,
    };

/// 150M target split 62.5% / 37.5%; branch A has a SKU without price (units —).
Map<String, dynamic> _breakdownJson({
  bool hasActuals = true,
  int year = 2026,
  String id = 't26',
}) =>
    {
      'target_id': id,
      'target_type': 'sell_out',
      'retailer_chain': 'fathalla',
      'chain_display_name': 'فتح الله',
      'year': year,
      'month': 0,
      'month_label': 'سنة $year',
      'branch_scope': 'كل الفروع',
      'category_scope': 'كل الفئات',
      'target_revenue_egp': 150000000,
      'target_units': 250000,
      'baseline': {
        'kind': 'prior_year',
        'year': year - 1,
        'months_covered': 12,
        'partial': false,
        'fallback_used': false,
        'total_revenue_egp': 100000000,
        'caption_ar': 'التوزيع حسب حصة كل فرع وصنف من مبيعات ${year - 1}',
      },
      'has_actuals': hasActuals,
      'actual_revenue_egp': hasActuals ? 127135120 : 0,
      'actual_units': hasActuals ? 1532854 : 0,
      'achievement_pct': hasActuals ? 84.8 : null,
      'gap_egp': hasActuals ? -22864880 : 0,
      'allocated_target_units': 250000,
      'allocated_target_cartons': 20000.5,
      'unattributed_actual_revenue_egp': hasActuals ? 1500000 : 0,
      'allocation_granularity_egp': 1,
      'branches': [
        {
          'branch_key': 'A',
          'branch_name': 'فتح الله - فرع المعادي',
          'baseline_revenue_egp': 62500000,
          'share_pct': 62.5,
          'allocated_target_egp': 93750000,
          'allocated_target_units': 150000,
          'allocated_target_cartons': 12500.0,
          'actual_revenue_egp': hasActuals ? 80000000 : 0,
          'actual_units': hasActuals ? 900000 : 0,
          'achievement_pct': hasActuals ? 85.3 : null,
          'gap_egp': hasActuals ? -13750000 : 0,
          'skus': [
            _sku('s1', 'عصير مانجو 1 لتر',
                share: 80,
                target: 75000000,
                units: 150000,
                cartons: 12500.0,
                price: 500,
                actual: hasActuals ? 60000000 : 0,
                actualUnits: hasActuals ? 120000 : 0,
                ach: hasActuals ? 80 : null,
                gap: hasActuals ? -15000000 : 0),
            _sku('s2', 'عصير برتقال بدون سعر',
                share: 20, target: 18750000, actual: 0, ach: hasActuals ? 0 : null,
                gap: hasActuals ? -18750000 : 0),
          ],
        },
        {
          'branch_key': 'B',
          'branch_name': 'فتح الله - فرع الزمالك',
          'baseline_revenue_egp': 37500000,
          'share_pct': 37.5,
          'allocated_target_egp': 56250000,
          'actual_revenue_egp': hasActuals ? 45635120 : 0,
          'actual_units': hasActuals ? 632854 : 0,
          'achievement_pct': hasActuals ? 81.1 : null,
          'gap_egp': hasActuals ? -10614880 : 0,
          'skus': [],
        },
      ],
      'no_history': [
        {
          'kind': 'branch',
          'branch_key': 'C',
          'branch_name': 'فتح الله - فرع جديد',
          'actual_revenue_egp': 1000,
          'actual_units': 10,
        },
      ],
      'source': 'memory',
    };

class _FakeRepo extends TargetRepository {
  _FakeRepo(this.items, this.breakdowns)
      : super(ApiClient(tenantId: 'tenant-fake-breakdown', allowMockFallback: false));

  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> breakdowns;
  final List<String> breakdownRequests = [];

  @override
  Future<Result<TargetsSummaryModel>> loadSummary({
    required String targetType,
    String? chain,
    int? year,
    bool forceRefresh = false,
  }) async {
    final filtered =
        items.where((i) => year == null || i['year'] == year).toList();
    double sum(String k) =>
        filtered.fold<double>(0, (a, i) => a + (i[k] as num).toDouble());
    return Success(TargetsSummaryModel.fromJson({
      'target_type': targetType,
      'total_target_revenue_egp': sum('target_revenue_egp'),
      'total_actual_revenue_egp': sum('actual_revenue_egp'),
      'total_target_units': sum('target_units'),
      'total_actual_units': sum('actual_units'),
      'items': filtered,
    }));
  }

  @override
  Future<Result<List<RetailChainModel>>> loadChains({bool forceRefresh = false}) async =>
      const Success(<RetailChainModel>[]);

  @override
  Future<Result<TargetBreakdownModel>> loadBreakdown(
    String targetId, {
    bool forceRefresh = false,
  }) async {
    breakdownRequests.add(targetId);
    final json = breakdowns[targetId];
    if (json == null) return const Failure(AppError.unknown('x'));
    return Success(TargetBreakdownModel.fromJson(json));
  }
}

Map<String, dynamic> _item(
  String id,
  int year, {
  required double target,
  required double actual,
  required bool hasActuals,
  required double units,
  required double actualUnits,
}) =>
    {
      'id': id,
      'target_type': 'sell_out',
      'retailer_chain': 'fathalla',
      'chain_display_name': 'فتح الله',
      'year': year,
      'month': 0,
      'month_label': 'سنة $year',
      'branch_name': 'كل الفروع',
      'category': 'كل الفئات',
      'target_revenue_egp': target,
      'actual_revenue_egp': actual,
      'variance_revenue_egp': hasActuals ? actual - target : 0,
      'achievement_rev_pct': hasActuals ? actual / target * 100 : 0,
      'target_units': units,
      'actual_units': actualUnits,
      'has_actuals': hasActuals,
      'status': hasActuals ? 'at_risk' : 'no_data',
      'status_ar': hasActuals ? 'قريب من المستهدف' : 'لا توجد مبيعات بعد',
    };

class _SpyApi extends ApiClient {
  _SpyApi() : super(tenantId: 'tenant-fake-breakdown', allowMockFallback: false);
  int? savedYear;
  double? savedRevenue;

  @override
  Future<TargetsSummaryModel> upsertTarget({
    String? id,
    required String targetType,
    required String retailerChain,
    required int year,
    required int month,
    String branchName = 'كل الفروع',
    String category = 'كل الفئات',
    required double targetRevenueEgp,
    required double targetUnits,
    String notes = '',
  }) async {
    savedYear = year;
    savedRevenue = targetRevenueEgp;
    return TargetsSummaryModel.empty(targetType);
  }
}

Future<void> _bigScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      builder: (context, c) => Directionality(textDirection: TextDirection.rtl, child: c!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('breakdown model + export', () {
    test('parses nullable fields as null, not 0', () {
      final m = TargetBreakdownModel.fromJson(_breakdownJson());
      final noPrice = m.branches.first.skus[1];
      expect(noPrice.allocatedUnits, isNull);
      expect(noPrice.allocatedCartons, isNull);
      expect(noPrice.avgUnitPriceEgp, isNull);
      expect(m.branches[1].allocatedUnits, isNull);
      expect(m.allocatedTotalEgp, 150000000);
      expect(m.hasBranches, isTrue);
    });

    test('export rows keep the exact target total and empty cells for gaps', () {
      final m = TargetBreakdownModel.fromJson(_breakdownJson());
      final rows = buildTargetBreakdownRows(m);
      final total = rows.firstWhere((r) => r[0] == 'الإجمالي');
      expect(total[4], '150000000');
      final branchSum = rows
          .where((r) => r[0] == 'فرع')
          .fold<double>(0, (s, r) => s + double.parse(r[4] as String));
      expect(branchSum, 150000000);
      final skuNoPrice = rows.firstWhere((r) => r[2] == 'عصير برتقال بدون سعر');
      expect(skuNoPrice[5], '');
      expect(skuNoPrice[6], '');
      expect(rows.last[0], 'بدون مبيعات سابقة');
      // shared "فتح الله - " prefix is display-only stripped
      expect(rows.firstWhere((r) => r[0] == 'فرع')[1], 'فرع المعادي');
      final csv = buildTargetBreakdownCsv(m);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(targetBreakdownFileName(m), 'target_breakdown_fathalla_2026.csv');
    });

    test('future-year export leaves actual columns empty (never 0)', () {
      final m = TargetBreakdownModel.fromJson(_breakdownJson(hasActuals: false, year: 2027));
      final rows = buildTargetBreakdownRows(m);
      final total = rows.firstWhere((r) => r[0] == 'الإجمالي');
      expect(total[7], '');
      expect(total[8], '');
      expect(total[9], '');
      expect(total[10], '');
    });
  });

  group('breakdown dialog', () {
    testWidgets('is RTL under an LTR app, and the title uses titleMedium', (tester) async {
      await _bigScreen(tester);
      final repo = _FakeRepo(const [], {'t26': _breakdownJson()});
      // Default MaterialApp locale is English (LTR), matching the app shell.
      // The dialog must impose RTL itself.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TargetBreakdownView(
            repository: repo,
            target: TargetComparisonModel.fromJson(_item('t26', 2026,
                target: 150000000,
                actual: 127135120,
                hasActuals: true,
                units: 250000,
                actualUnits: 1532854)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('target_breakdown_dialog'));
      expect(
        tester
            .widget<Directionality>(find.byKey(const ValueKey('target_breakdown_direction')))
            .textDirection,
        TextDirection.rtl,
      );
      expect(Directionality.of(tester.element(dialog)), TextDirection.rtl);

      double centerX(Finder f) => tester.getCenter(f).dx;
      expect(
        centerX(find.text('الفرع / الصنف')),
        greaterThan(centerX(find.text('الفرق (ج.م)'))),
        reason: 'branch column sits on the right, gap column on the left',
      );
      expect(
        centerX(find.byKey(const ValueKey('target_breakdown_kpi_target'))),
        greaterThan(centerX(find.byKey(const ValueKey('target_breakdown_kpi_actual')))),
      );
      expect(
        centerX(find.byKey(const ValueKey('target_breakdown_kpi_actual'))),
        greaterThan(centerX(find.byKey(const ValueKey('target_breakdown_kpi_achievement')))),
      );
      expect(
        centerX(find.byKey(const ValueKey('target_breakdown_kpi_achievement'))),
        greaterThan(centerX(find.byKey(const ValueKey('target_breakdown_kpi_gap')))),
      );
      expect(
        centerX(find.byKey(const ValueKey('target_breakdown_back'))),
        greaterThan(centerX(find.byKey(const ValueKey('target_breakdown_export')))),
        reason: 'back arrow on the right, export on the left',
      );

      final caption = find.byKey(const ValueKey('target_breakdown_caption'));
      expect(
        centerX(find.descendant(of: caption, matching: find.byIcon(Icons.info_outline_rounded))),
        greaterThan(centerX(find.descendant(of: caption, matching: find.byType(Text)))),
        reason: 'info icon leads the banner from the right',
      );

      final row = find.byKey(const ValueKey('target_breakdown_row_A'));
      expect(
        centerX(find.descendant(of: row, matching: find.byIcon(Icons.expand_more_rounded))),
        greaterThan(centerX(find.descendant(of: row, matching: find.text('فرع المعادي')))),
        reason: 'expand chevron sits at the start of the name cell',
      );

      final pct = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('target_breakdown_total_row')),
        matching: find.text('100.0%'),
      ));
      expect(pct.textDirection, TextDirection.ltr);

      final titleFinder = find.byKey(const ValueKey('target_breakdown_title'));
      final title = tester.widget<Text>(titleFinder);
      final theme = Theme.of(tester.element(titleFinder));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(title.data, contains('توزيع المستهدف'));
      expect(title.style?.fontSize, theme.textTheme.titleMedium?.fontSize);
      expect(title.style?.fontSize, 16);
      expect(title.style!.fontSize!, lessThan(theme.textTheme.titleLarge!.fontSize!));
    });

    testWidgets('shows caption, exact totals, expandable SKUs and zero-baseline list',
        (tester) async {
      await _bigScreen(tester);
      final repo = _FakeRepo(const [], {'t26': _breakdownJson()});
      await tester.pumpWidget(_host(TargetBreakdownView(
        repository: repo,
        target: TargetComparisonModel.fromJson(_item('t26', 2026,
            target: 150000000, actual: 127135120, hasActuals: true, units: 250000, actualUnits: 1532854)),
      )));
      await tester.pumpAndSettle();

      expect(find.text('التوزيع حسب حصة كل فرع وصنف من مبيعات 2025'), findsOneWidget);
      // Branch rows with shared prefix stripped.
      expect(find.text('فرع المعادي'), findsOneWidget);
      expect(find.text('فرع الزمالك'), findsOneWidget);
      // Exact total row.
      final total = find.byKey(const ValueKey('target_breakdown_total_row'));
      expect(find.descendant(of: total, matching: find.textContaining('150,000,000')), findsOneWidget);
      expect(find.descendant(of: total, matching: find.text('100.0%')), findsOneWidget);
      // One-line headers.
      expect(find.text('المستهدف (ج.م)'), findsOneWidget);

      // SKUs hidden until the branch is expanded.
      expect(find.text('عصير مانجو 1 لتر'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('target_breakdown_row_A')));
      await tester.pumpAndSettle();
      expect(find.text('عصير مانجو 1 لتر'), findsOneWidget);
      final noPrice = find.byKey(const ValueKey('target_breakdown_sku_A_s2'));
      expect(noPrice, findsOneWidget);
      // SKU without a price: units and cartons are «—», not 0.
      expect(find.descendant(of: noPrice, matching: find.text('—')), findsNWidgets(2));

      // Unattributed actuals note and qty method note.
      expect(find.textContaining('غير منسوبة'), findsOneWidget);
      expect(find.textContaining('متوسط سعر الوحدة'), findsOneWidget);

      // Zero-baseline list is collapsed and then listed.
      expect(find.textContaining('بدون مبيعات سابقة (1)'), findsOneWidget);
      expect(find.text('فرع جديد'), findsNothing);
      await tester.ensureVisible(find.textContaining('بدون مبيعات سابقة (1)'));
      await tester.tap(find.textContaining('بدون مبيعات سابقة (1)'));
      await tester.pumpAndSettle();
      expect(find.text('فرع جديد'), findsOneWidget);
    });

    testWidgets('future year: achieved, achievement and gap read «—» with the note',
        (tester) async {
      await _bigScreen(tester);
      final repo = _FakeRepo(const [], {
        't27': _breakdownJson(hasActuals: false, year: 2027, id: 't27'),
      });
      await tester.pumpWidget(_host(TargetBreakdownView(
        repository: repo,
        target: TargetComparisonModel.fromJson(_item('t27', 2027,
            target: 180000000, actual: 0, hasActuals: false, units: 100, actualUnits: 0)),
      )));
      await tester.pumpAndSettle();

      for (final k in ['actual', 'achievement', 'gap']) {
        final card = find.byKey(ValueKey('target_breakdown_kpi_$k'));
        expect(find.descendant(of: card, matching: find.text('—')), findsOneWidget, reason: k);
        expect(find.descendant(of: card, matching: find.text('لا توجد مبيعات بعد')), findsOneWidget, reason: k);
      }
      expect(find.textContaining('من مبيعات 2026'), findsOneWidget);
      expect(find.text('0.0%'), findsNothing);
    });

    testWidgets('no baseline data: explains instead of showing fake zeros', (tester) async {
      await _bigScreen(tester);
      final json = _breakdownJson()
        ..['branches'] = <dynamic>[]
        ..['no_history'] = <dynamic>[]
        ..['baseline'] = {'kind': 'none', 'caption_ar': ''};
      final repo = _FakeRepo(const [], {'t26': json});
      await tester.pumpWidget(_host(TargetBreakdownView(
        repository: repo,
        target: TargetComparisonModel.fromJson(_item('t26', 2026,
            target: 150000000, actual: 0, hasActuals: false, units: 1, actualUnits: 0)),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('target_breakdown_no_baseline')), findsOneWidget);
      expect(find.byKey(const ValueKey('target_breakdown_total_row')), findsNothing);
    });

    testWidgets('load failure shows retry', (tester) async {
      await _bigScreen(tester);
      final repo = _FakeRepo(const [], {});
      await tester.pumpWidget(_host(TargetBreakdownView(
        repository: repo,
        target: TargetComparisonModel.fromJson(_item('missing', 2026,
            target: 1, actual: 0, hasActuals: false, units: 1, actualUnits: 0)),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('target_breakdown_retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('target_breakdown_retry')));
      await tester.pumpAndSettle();
      expect(repo.breakdownRequests, ['missing', 'missing']);
    });
  });

  group('targets panel', () {
    final items = [
      _item('t26', 2026,
          target: 150000000, actual: 127135120, hasActuals: true, units: 250000, actualUnits: 1532854),
      _item('t27', 2027,
          target: 180000000, actual: 0, hasActuals: false, units: 2273513, actualUnits: 0),
    ];

    Future<_FakeRepo> pumpPanel(WidgetTester tester, {ApiClient? api}) async {
      await _bigScreen(tester);
      final repo = _FakeRepo(items, {
        't26': _breakdownJson(),
        't27': _breakdownJson(hasActuals: false, year: 2027, id: 't27'),
      });
      await tester.pumpWidget(_host(TargetManagementPanel(
        apiClient: api ?? ApiClient(tenantId: 'tenant-fake-breakdown', allowMockFallback: false),
        targetType: 'sell_out',
        repository: repo,
      )));
      await tester.pumpAndSettle();
      return repo;
    }

    String textIn(WidgetTester tester, String key, {int index = 0}) {
      final texts = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Text),
          ))
          .map((t) => t.data ?? '')
          .toList();
      return texts[index];
    }

    testWidgets('all years: achievement and gap only compare periods with sales',
        (tester) async {
      await pumpPanel(tester);
      // Target card keeps both years (330M) and says so.
      expect(textIn(tester, 'targets_kpi_card_مستهدف المبيعات', index: 1), contains('330'));
      expect(find.text('يشمل مستهدفات سنوات قادمة'), findsOneWidget);
      // 84.8% (not 38.5%) and −22.86M (not −202.86M).
      // The comparison table repeats 84.8% without the status phrase.
      expect(textIn(tester, 'targets_kpi_card_نسبة التحقيق', index: 1), '84.8%');
      expect(find.text('84.8%'), findsWidgets);
      expect(find.textContaining('38.5'), findsNothing);
      final gap = textIn(tester, 'targets_kpi_card_الفرق', index: 1);
      expect(gap, contains('22.86'));
      expect(gap, isNot(contains('202')));
    });

    testWidgets('future-year row shows «—» and the no-sales note, not 0', (tester) async {
      await pumpPanel(tester);
      expect(find.byKey(const ValueKey('targets_actual_dash_t27')), findsOneWidget);
      expect(find.byKey(const ValueKey('targets_actual_dash_t26')), findsNothing);
      expect(find.text('لا توجد مبيعات بعد'), findsOneWidget);
      String pillText(String id) => tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(ValueKey('targets_achievement_$id')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(pillText('t27'), '—');
      expect(pillText('t26'), startsWith('84.8%'));
      expect(pillText('t26'), contains('أقل من المستهدف'));
    });

    testWidgets('only a future year selected: achieved / % / gap cards are «—»', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.widgetWithText(TextField, 'كل السنوات'));
      await tester.pumpAndSettle();
      // The table period is also "2027". DropdownMenu mounts the entry
      // twice; either copy selects the year.
      await tester.tap(find.widgetWithText(MenuItemButton, '2027').last);
      await tester.pumpAndSettle();
      expect(textIn(tester, 'targets_kpi_card_المحقق', index: 1), '—');
      expect(textIn(tester, 'targets_kpi_card_نسبة التحقيق', index: 1), '—');
      expect(textIn(tester, 'targets_kpi_card_الفرق', index: 1), '—');
    });

    testWidgets('tapping a row opens the full-page detail; back closes it',
        (tester) async {
      final repo = await pumpPanel(tester);
      await tester.tap(find.byKey(const ValueKey('targets_period_t26')));
      await tester.pumpAndSettle();
      expect(repo.breakdownRequests, ['t26']);
      expect(find.byKey(const ValueKey('target_detail_page')), findsOneWidget);
      expect(find.byKey(const ValueKey('target_breakdown_dialog')), findsNothing);
      expect(find.text('رفع ملف المستهدفات'), findsNothing);
      expect(find.text('تنزيل القالب'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('target_detail_back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('target_detail_page')), findsNothing);
      expect(find.byKey(const ValueKey('targets_main_table')), findsOneWidget);
    });

    testWidgets('the add form saves a target for a future year', (tester) async {
      final api = _SpyApi();
      await pumpPanel(tester, api: api);
      await tester.tap(find.text('إضافة مستهدف').first);
      await tester.pumpAndSettle();
      // Sell-out add flow: choose value target before the form dialog.
      await tester.tap(find.byKey(const ValueKey('target_type_value')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('target_dialog_year_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${_baseYear + 1}').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'المستهدف (ج.م) *'), '180000000');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(api.savedYear, _baseYear + 1);
      expect(api.savedRevenue, 180000000);
    });
  });
}

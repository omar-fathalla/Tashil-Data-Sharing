import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/target_kpi.dart';

Map<String, dynamic> _item(
  String id,
  int year, {
  required double target,
  required double actual,
  required double units,
  required double actualUnits,
  bool? hasActuals,
}) =>
    {
      'id': id,
      'retailer_chain': 'fathalla',
      'chain_display_name': 'فتح الله',
      'year': year,
      'month_label': 'سنة $year',
      'target_revenue_egp': target,
      'actual_revenue_egp': actual,
      'target_units': units,
      'actual_units': actualUnits,
      if (hasActuals != null) 'has_actuals': hasActuals,
    };

TargetsSummaryModel _summary(List<Map<String, dynamic>> items) =>
    TargetsSummaryModel.fromJson({
      'target_type': 'sell_out',
      'items': items,
    });

final _t2026 = _item('t26', 2026,
    target: 150000000, actual: 127135120, units: 250000, actualUnits: 1532854, hasActuals: true);
final _t2027 = _item('t27', 2027,
    target: 180000000, actual: 0, units: 2273513, actualUnits: 0, hasActuals: false);

void main() {
  test('2026 only: 84.8% and gap −22,864,880', () {
    final k = TargetKpis.fromSummary(_summary([_t2026]));
    expect(k.targetRevenue, 150000000);
    expect(k.actualRevenue, 127135120);
    expect(k.achievementPct, 84.8);
    expect(k.gapRevenue, -22864880);
    expect(k.includesNoData, isFalse);
  });

  test('all years: the 2027 target does not drag achievement to 38.5%', () {
    final k = TargetKpis.fromSummary(_summary([_t2026, _t2027]));
    expect(k.targetRevenue, 330000000);
    expect(k.actualRevenue, 127135120);
    expect(k.comparableTargetRevenue, 150000000);
    expect(k.achievementPct, 84.8);
    expect(k.gapRevenue, -22864880);
    expect(k.noDataCount, 1);
    expect(k.noDataTargetRevenue, 180000000);
    expect(k.includesNoData, isTrue);
    // UI year-scope: Target card should prefer comparableTargetRevenue so
    // Target / Achievement / Gap share the same 150M denominator.
    expect(k.comparableTargetRevenue, k.comparableActualRevenue + (-k.gapRevenue!));
  });

  test('only a future year: nothing is comparable, % and gap are null (shown as —)', () {
    final k = TargetKpis.fromSummary(_summary([_t2027]));
    expect(k.hasTargets, isTrue);
    expect(k.onlyNoData, isTrue);
    expect(k.achievementPct, isNull);
    expect(k.gapRevenue, isNull);
  });

  test('no targets at all', () {
    final k = TargetKpis.fromSummary(TargetsSummaryModel.empty('sell_out'));
    expect(k.hasTargets, isFalse);
    expect(k.achievementPct, isNull);
  });

  test('over-achievement keeps one-decimal rounding and a positive gap', () {
    final k = TargetKpis.fromSummary(_summary([
      _item('a', 2026,
          target: 1000, actual: 1234.5, units: 10, actualUnits: 12, hasActuals: true),
    ]));
    expect(k.achievementPct, 123.5);
    expect(k.gapRevenue, closeTo(234.5, 1e-9));
  });

  test('legacy backend without has_actuals: derived from actual value / units', () {
    final s = _summary([
      _item('old26', 2026, target: 100, actual: 50, units: 10, actualUnits: 5),
      _item('old27', 2027, target: 300, actual: 0, units: 30, actualUnits: 0),
    ]);
    expect(s.items[0].hasActuals, isTrue);
    expect(s.items[1].hasActuals, isFalse);
    final k = TargetKpis.fromSummary(s);
    expect(k.achievementPct, 50.0);
    expect(k.gapRevenue, -50);
  });

  test('units-only targets fall back to the unit achievement', () {
    final k = TargetKpis.fromSummary(_summary([
      _item('u', 2026, target: 0, actual: 0, units: 200, actualUnits: 100, hasActuals: true),
    ]));
    expect(k.achievementPct, 50.0);
  });
}

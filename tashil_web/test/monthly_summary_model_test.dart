import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  test('ExecutiveKPIsModel parses monthly_summary honesty fields', () {
    final kpis = ExecutiveKPIsModel.fromJson({
      'total_revenue': 1250000,
      'revenue_growth_pct': 12.4,
      'total_units_sold': 42000,
      'units_growth_pct': 6.5,
      'active_stores_count': 37,
      'oos_rate_pct': 11.2,
      'total_oos_incidents': 3,
      'estimated_lost_revenue': 15000,
      'currency': 'EGP',
      'reporting_period': 'CUSTOM',
      'chain_shares': <dynamic>[],
      'daily_trends': <dynamic>[],
      'monthly_summary': {
        'narrative_ar': 'ملخص شهري: إجمالي المبيعات 1250000 EGP',
        'mapping_source': 'deterministic',
        'confidence': 0.95,
        'grounded': true,
        'aggregates': {
          'total_revenue': 1250000,
          'total_units': 42000,
        },
      },
    });

    expect(kpis.monthlySummary, isNotNull);
    expect(kpis.monthlySummary!.narrativeAr, contains('1250000'));
    expect(kpis.monthlySummary!.mappingSource, 'deterministic');
    expect(kpis.monthlySummary!.grounded, isTrue);
    expect(kpis.monthlySummary!.confidence, closeTo(0.95, 0.001));
    expect(kpis.monthlySummary!.aggregates['total_units'], 42000);
  });

  test('ExecutiveKPIsModel tolerates missing monthly_summary', () {
    final kpis = ExecutiveKPIsModel.fromJson({
      'total_revenue': 0,
      'revenue_growth_pct': 0,
      'total_units_sold': 0,
      'units_growth_pct': 0,
      'active_stores_count': 0,
      'oos_rate_pct': 0,
      'total_oos_incidents': 0,
      'estimated_lost_revenue': 0,
      'currency': 'EGP',
      'reporting_period': 'MTD',
      'chain_shares': <dynamic>[],
      'daily_trends': <dynamic>[],
    });
    expect(kpis.monthlySummary, isNull);
  });
}

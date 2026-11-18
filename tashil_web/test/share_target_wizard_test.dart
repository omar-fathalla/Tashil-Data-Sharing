import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/sell_out_analytics/data/share_target_models.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/share_target_plan.dart';

void main() {
  test('preview model parses cascade JSON', () {
    final preview = ShareTargetPreview.fromJson({
      'can_save': true,
      'plan': {
        'market_growth_pct': 0,
        'months_with_data': 10,
        'annualized': false,
        'categories': [
          {
            'category': 'صابون',
            'current_share_pct': 39,
            'desired_share_pct': 44,
            'own_revenue_egp': 100,
            'market_revenue_egp': 250,
            'projected_market_egp': 250,
            'target_revenue_egp': 110,
            'uplift_revenue_egp': 10,
            'uplift_pct': 10,
            'avg_price_egp': 10,
            'current_units': 10,
            'target_units': 11,
            'uplift_units': 1,
            'below_current': false,
            'exceeds_market': false,
          },
        ],
      },
      'cascades': [
        {
          'category': {
            'category': 'صابون',
            'desired_share_pct': 44,
            'target_revenue_egp': 110,
          },
          'branches': [
            {
              'branch_name': 'الرحاب',
              'historical_share_pct': 70,
              'target_egp': 77,
              'uplift_egp': 7,
              'skus': [
                {
                  'sku_name': 'S1',
                  'share_pct': 50,
                  'target_egp': 38.5,
                  'target_units': 3.85,
                },
              ],
            },
          ],
          'months': [
            {'month': 1, 'share_pct': 8.3, 'target_egp': 9.17},
          ],
        },
      ],
    });
    expect(preview.canSave, isTrue);
    expect(preview.plan.totalTargetEgp, 110);
    expect(preview.cascades.first.branches.first.branchName, 'الرحاب');
    expect(preview.cascades.first.months.first.month, 1);
  });

  test('baseline model fromJson', () {
    final b = ShareTargetBaseline.fromJson({
      'retailer_chain': 'fathalla',
      'chain_display_name': 'فتح الله',
      'year': 2026,
      'months_with_data': 10,
      'total_own_egp': 98.89,
      'total_market_egp': 450.86,
      'overall_current_share_pct': 21.9,
      'categories': [
        {
          'category': 'صابون سائل اطباق',
          'current_share_pct': 39,
          'own_revenue_egp': 43.44,
          'market_revenue_egp': 111.24,
          'own_units': 100,
          'avg_price_egp': 10,
        },
      ],
      'branches': [
        {'branch_key': 's1', 'branch_name': 'الرحاب', 'own_revenue_egp': 10},
      ],
    });
    expect(b.monthsWithData, 10);
    expect(b.categories.single.category, 'صابون سائل اطباق');
    expect(b.branches.single.branchName, 'الرحاب');
    expect(b.categories.single.toInput().ownRevenueEgp, 43.44);
  });

  test('live plan blocks share > 100', () {
    final sum = planAll(
      const [
        ShareCategoryInput(
          category: 'x',
          currentSharePct: 40,
          ownRevenueEgp: 40,
          marketRevenueEgp: 100,
        ),
      ],
      const [101],
      const SharePlanOptions(annualize: false),
    );
    expect(sum.canProceed, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/share_target_plan.dart';

const million = 1000000.0;

List<ShareCategoryInput> _fixtureInputs() {
  return workedExampleFathalla2026()
      .map(
        (r) => ShareCategoryInput(
          category: r.category,
          currentSharePct: r.currentSharePct,
          ownRevenueEgp: r.ownM * million,
          marketRevenueEgp: r.marketM * million,
          ownUnits: r.currentUnits,
          avgPriceEgp: r.avgPrice,
        ),
      )
      .toList();
}

void main() {
  test('+5pt flat 10-month base → 98.89M → 121.43M', () {
    final sum = planAllDelta(
      _fixtureInputs(),
      5,
      const SharePlanOptions(
        marketGrowthPct: 0,
        monthsWithData: 10,
        annualize: false,
      ),
    );
    expect(sum.totalOwnEgp / million, closeTo(98.89, 0.005));
    expect(sum.totalTargetEgp / million, closeTo(121.43, 0.005));
    expect(sum.totalUpliftEgp / million, closeTo(22.54, 0.01));
    expect(sum.canProceed, isTrue);
    expect(sum.hasShareOver100, isFalse);

    final rows = workedExampleFathalla2026();
    for (var i = 0; i < rows.length; i++) {
      expect(
        sum.categories[i].targetRevenueEgp / million,
        closeTo(rows[i].targetM, 0.015),
        reason: rows[i].category,
      );
    }
  });

  test('annualize ×12/10 scales totals', () {
    final sum = planAllDelta(
      _fixtureInputs(),
      5,
      const SharePlanOptions(
        marketGrowthPct: 0,
        monthsWithData: 10,
        annualize: true,
      ),
    );
    expect(sum.annualizationFactor, 1.2);
    expect(sum.totalOwnEgp / million, closeTo(98.89 * 1.2, 0.01));
    expect(sum.totalTargetEgp / million, closeTo(121.43 * 1.2, 0.02));
  });

  test('share >100% blocks; below current warns only', () {
    final over = planAll(
      const [
        ShareCategoryInput(
          category: 'x',
          currentSharePct: 40,
          ownRevenueEgp: 40,
          marketRevenueEgp: 100,
          avgPriceEgp: 10,
          ownUnits: 4,
        ),
      ],
      const [100.1],
      const SharePlanOptions(annualize: false),
    );
    expect(over.hasShareOver100, isTrue);
    expect(over.canProceed, isFalse);

    final below = planAll(
      const [
        ShareCategoryInput(
          category: 'x',
          currentSharePct: 40,
          ownRevenueEgp: 40,
          marketRevenueEgp: 100,
          avgPriceEgp: 10,
          ownUnits: 4,
        ),
      ],
      const [35],
      const SharePlanOptions(annualize: false),
    );
    expect(below.hasBelowCurrent, isTrue);
    expect(below.canProceed, isTrue);
  });

  test('units = target ÷ avg price', () {
    final p = planCategory(
      const ShareCategoryInput(
        category: 'c',
        currentSharePct: 10,
        ownRevenueEgp: 1000,
        marketRevenueEgp: 10000,
        ownUnits: 100,
        avgPriceEgp: 10,
      ),
      20,
      const SharePlanOptions(annualize: false),
    );
    expect(p.targetRevenueEgp, 2000);
    expect(p.targetUnits, 200);
  });
}

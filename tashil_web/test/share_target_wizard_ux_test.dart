import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/sell_out_analytics/data/share_target_models.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/share_target_wizard.dart';

class _ShareWizardApi extends ApiClient {
  _ShareWizardApi({required this.baseline, required this.preview})
      : super(tenantId: 'tenant-share-ux', allowMockFallback: false);

  final ShareTargetBaseline baseline;
  final ShareTargetPreview preview;
  int previewCalls = 0;

  @override
  Future<ShareTargetBaseline> getShareTargetBaseline({
    required String chain,
    required int year,
  }) async =>
      baseline;

  @override
  Future<ShareTargetPreview> previewShareTarget({
    required String retailerChain,
    required int year,
    double marketGrowthPct = 0,
    int monthsWithData = 0,
    bool annualize = true,
    List<String> branchKeys = const [],
    required List<({String category, double desiredSharePct})> categories,
    double? deltaPts,
  }) async {
    previewCalls++;
    return preview;
  }
}

ShareTargetBaseline _baselineWithCategories(int n) {
  return ShareTargetBaseline.fromJson({
    'retailer_chain': 'fathalla',
    'chain_display_name': 'أسواق فتح الله',
    'year': 2026,
    'months_with_data': 10,
    'total_own_egp': 100,
    'total_market_egp': 400,
    'overall_current_share_pct': 25,
    'categories': [
      for (var i = 0; i < n; i++)
        {
          'category': 'فئة ${i + 1}',
          'current_share_pct': i == 0 ? 39.0 : (i == 1 ? 15.0 : 10.0 + i),
          'own_revenue_egp': 10.0 + i,
          'market_revenue_egp': 40.0 + i,
          'own_units': 100,
          'avg_price_egp': 10,
        },
    ],
    'branches': [
      {'branch_key': 's1', 'branch_name': 'الرحاب', 'own_revenue_egp': 50},
    ],
  });
}

ShareTargetPreview _emptyPreviewFromBaseline(ShareTargetBaseline b) {
  return ShareTargetPreview.fromJson({
    'can_save': true,
    'plan': {
      'market_growth_pct': 0,
      'months_with_data': b.monthsWithData,
      'annualized': true,
      'categories': [
        for (final c in b.categories)
          {
            'category': c.category,
            'current_share_pct': c.currentSharePct,
            'desired_share_pct': c.currentSharePct,
            'own_revenue_egp': c.ownRevenueEgp,
            'market_revenue_egp': c.marketRevenueEgp,
            'projected_market_egp': c.marketRevenueEgp,
            'target_revenue_egp': c.ownRevenueEgp,
            'uplift_revenue_egp': 0,
            'uplift_pct': 0,
            'avg_price_egp': c.avgPriceEgp,
            'current_units': c.ownUnits,
            'target_units': c.ownUnits,
            'uplift_units': 0,
            'below_current': false,
            'exceeds_market': false,
          },
      ],
    },
    'cascades': [
      if (b.categories.isNotEmpty)
        {
          'category': {
            'category': b.categories.first.category,
            'desired_share_pct': b.categories.first.currentSharePct,
            'target_revenue_egp': b.categories.first.ownRevenueEgp,
          },
          'branches': [
            {
              'branch_name': 'الرحاب',
              'historical_share_pct': 100,
              'target_egp': b.categories.first.ownRevenueEgp,
              'uplift_egp': 0,
              'skus': [],
            },
          ],
          'months': [
            for (var m = 1; m <= 12; m++)
              {'month': m, 'share_pct': 8.3, 'target_egp': 1},
          ],
        },
    ],
  });
}

Future<void> _pumpWizard(
  WidgetTester tester, {
  required ApiClient api,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              showShareTargetWizard(
                context: context,
                apiClient: api,
                chainOptions: const [(code: 'fathalla', label: 'أسواق فتح الله')],
                initialChain: 'fathalla',
                initialYear: 2026,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('step 2 lists every baseline category (not just first viewport)',
      (tester) async {
    final baseline = _baselineWithCategories(20);
    final api = _ShareWizardApi(
      baseline: baseline,
      preview: _emptyPreviewFromBaseline(baseline),
    );
    await _pumpWizard(tester, api: api);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('share_category_count')), findsOneWidget);
    expect(find.text('20 فئة'), findsOneWidget);

    // Scroll through the category list — all 20 cards must be reachable.
    final list = find.byKey(const ValueKey('share_category_list'));
    expect(list, findsOneWidget);
    final verticalScrollable = find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(verticalScrollable, findsOneWidget);
    for (var i = 1; i <= 20; i++) {
      final card = find.byKey(ValueKey('share_cat_فئة $i'));
      await tester.scrollUntilVisible(card, 240, scrollable: verticalScrollable);
      expect(card, findsOneWidget);
    }
  });

  testWidgets('share % field shows full value and accepts multi-digit typing',
      (tester) async {
    final baseline = _baselineWithCategories(2);
    final api = _ShareWizardApi(
      baseline: baseline,
      preview: _emptyPreviewFromBaseline(baseline),
    );
    await _pumpWizard(tester, api: api);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('share_pct_field_فئة 1'));
    expect(field, findsOneWidget);

    // Initial 39.0 must be fully visible in the controller (not clipped to "39.").
    final tf = tester.widget<TextField>(field);
    expect(tf.controller!.text, '39.0');

    // Field is wide enough for multi-digit shares + % suffix.
    final box = tester.getSize(field);
    expect(box.width, greaterThanOrEqualTo(100));

    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, '35');
    await tester.pumpAndSettle();
    expect(tf.controller!.text, '35');

    // Second card starts at 15.0 — full digits retained.
    final field2 = find.byKey(const ValueKey('share_pct_field_فئة 2'));
    final tf2 = tester.widget<TextField>(field2);
    expect(tf2.controller!.text, '15.0');
  });

  testWidgets('step 3 review lists the same category count as step 2',
      (tester) async {
    final baseline = _baselineWithCategories(20);
    final api = _ShareWizardApi(
      baseline: baseline,
      preview: _emptyPreviewFromBaseline(baseline),
    );
    await _pumpWizard(tester, api: api);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('20 فئة'), findsOneWidget);

    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share_review_category_count')), findsOneWidget);
    expect(find.textContaining('الحصص (20 فئة)'), findsOneWidget);
    expect(api.previewCalls, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/sell_table_shared.dart';

SKUBranchInventoryModel _item({
  double margin = 0,
  int sellOutUnits = 10,
  double factoryCost = 100,
  String itemType = 'عادي',
  double grossMargin = 0,
}) =>
    SKUBranchInventoryModel(
      skuName: 'x',
      brand: 'b',
      sector: 'MT',
      subCategory: '',
      regionCode: '',
      governorate: '',
      salesRep: '',
      sellInCases: 1,
      sellInValueEgp: 1,
      sellOutEstCases: 1,
      sellOutValueEgp: 1,
      returnCases: 0,
      returnValueEgp: 0,
      estimatedStockCases: 0,
      estimatedStockValueEgp: 0,
      dailyRunRateCases: 0,
      daysOfInventory: 0,
      stockStatus: 'optimal',
      stockStatusAr: '',
      casePriceEgp: 0,
      weightTons: 0,
      suggestedPoCases: 0,
      suggestedPoValueEgp: 0,
      suggestedPoTons: 0,
      retailerMarginPct: margin,
      sellOutUnits: sellOutUnits,
      factoryCartonCost: factoryCost,
      itemType: itemType,
      chainGrossMarginEgp: grossMargin,
    );

void main() {
  group('matchesSellInMarginFilter', () {
    test('classifies margins only with a real basis', () {
      expect(matchesSellInMarginFilter(_item(margin: 15), 'healthy'), isTrue);
      expect(matchesSellInMarginFilter(_item(margin: 5), 'low_margin'), isTrue);
      expect(matchesSellInMarginFilter(_item(margin: -3), 'negative_margin'), isTrue);
      expect(matchesSellInMarginFilter(_item(margin: 15, sellOutUnits: 0), 'healthy'), isFalse);
      expect(matchesSellInMarginFilter(_item(margin: 0, factoryCost: 0), 'low_margin'), isFalse);
      expect(matchesSellInMarginFilter(_item(itemType: 'عرض'), 'promo'), isTrue);
      expect(matchesSellInMarginFilter(_item(), 'promo'), isFalse);
      expect(matchesSellInMarginFilter(_item(), 'all'), isTrue);
    });
  });

  testWidgets('shared chips render label (count) with AppIcons and select', (tester) async {
    String selected = 'all';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SellTableFilterChips(
            options: SellTableFilterChips.marginOptions(
                all: 5, healthy: 2, lowMargin: 1, negativeMargin: 1, promo: 1),
            selected: selected,
            onSelected: (v) => setState(() => selected = v),
          ),
        ),
      ),
    ));
    expect(find.text('عروض ترويجية (1)'), findsOneWidget);
    expect(find.text('بيع بأقل من التكلفة / حرق سعر (1)'), findsOneWidget);
    expect(find.byIcon(AppIcons.promo), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sell_filter_chip_promo')));
    await tester.pump();
    expect(selected, 'promo');
    final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('sell_filter_chip_promo')));
    expect(chip.selected, isTrue);
  });

  testWidgets('Sell-In upload button matches Sell-Out button design', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(children: [
            SellActionButtons.upload(context,
                label: 'Upload Sell-Out', onTap: () {}, key: const ValueKey('a')),
            SellActionButtons.upload(context,
                label: 'Upload Sell-In', onTap: () {}, key: const ValueKey('b')),
          ]),
        ),
      ),
    ));
    expect(find.text('Upload Sell-In'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('a'))).height,
        tester.getSize(find.byKey(const ValueKey('b'))).height);
    expect(find.byIcon(AppIcons.uploadFile), findsNWidgets(2));
  });
}

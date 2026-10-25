import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/product_master/data/chain_discount_repository.dart';
import 'package:tashil_web/features/product_master/presentation/widgets/chain_discount_profiles_card.dart';

Widget _host(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  test('net unit cost = list × (1 − inv) × (1 − add); defaults 10% / 0%', () {
    const def = ChainDiscountProfileModel(
        chain: 'x', invoiceDiscountPct: kDefaultInvoiceDiscountPct, additionalDiscountPct: kDefaultAdditionalDiscountPct);
    expect(def.netUnitCost(100), closeTo(90, 1e-9));
    const p = ChainDiscountProfileModel(chain: 'x', invoiceDiscountPct: 12, additionalDiscountPct: 5);
    expect(p.netUnitCost(100), closeTo(83.6, 1e-9));
  });

  testWidgets('add, edit and delete send the full list', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    List<ChainDiscountProfileModel> saved = [];
    var profiles = <ChainDiscountProfileModel>[];
    Future<void> onSave(List<ChainDiscountProfileModel> next) async {
      saved = next;
    }

    await tester.pumpWidget(_host(ChainDiscountProfilesCard(profiles: profiles, onSave: onSave)));
    expect(find.textContaining('لا توجد خصومات مخصصة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chain_discount_chain_field')), 'fathalla');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '12');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_additional_field')), '5');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(saved.single.chain, 'fathalla');
    expect(saved.single.invoiceDiscountPct, 12);
    expect(saved.single.additionalDiscountPct, 5);

    profiles = saved;
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(profiles: profiles, onSave: onSave)));
    expect(find.text('fathalla'), findsOneWidget);

    // Invalid percentage is rejected in the dialog.
    await tester.tap(find.byTooltip('تعديل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '120');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('النسب يجب'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '15');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(saved.single.invoiceDiscountPct, 15);

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });
}

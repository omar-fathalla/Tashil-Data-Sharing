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

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  test('net unit cost = list × (1 − inv) × (1 − add); defaults 14% / 10% / 0%', () {
    expect(kDefaultVatRatePct, 14);
    const def = ChainDiscountProfileModel(
        chain: 'x', invoiceDiscountPct: kDefaultInvoiceDiscountPct, additionalDiscountPct: kDefaultAdditionalDiscountPct);
    expect(def.netUnitCost(100), closeTo(90, 1e-9));
    expect(def.effectiveVatRatePct, 14);
    const p = ChainDiscountProfileModel(chain: 'x', invoiceDiscountPct: 12, additionalDiscountPct: 5, vatRatePct: 5);
    expect(p.netUnitCost(100), closeTo(83.6, 1e-9));
    expect(p.effectiveVatRatePct, 5);
  });

  test('JSON round trip keeps VAT; unset VAT stays unset', () {
    final withVat = ChainDiscountProfileModel.fromJson({
      'chain': 'a',
      'invoice_discount_pct': 10,
      'additional_discount_pct': 20,
      'vat_rate_pct': 5
    });
    expect(withVat.vatRatePct, 5);
    expect(withVat.toJson()['vat_rate_pct'], 5);
    final noVat = ChainDiscountProfileModel.fromJson(
        {'chain': 'b', 'invoice_discount_pct': 10, 'additional_discount_pct': 0});
    expect(noVat.vatRatePct, isNull);
    expect(noVat.toJson().containsKey('vat_rate_pct'), isFalse);
    expect(noVat.effectiveVatRatePct, 14);
    final zero = ChainDiscountProfileModel.fromJson({'chain': 'z', 'vat_rate_pct': 0});
    expect(zero.effectiveVatRatePct, 0, reason: 'an explicit 0% VAT is kept');
  });

  testWidgets('table columns, add / row-tap edit / delete send the full list', (tester) async {
    _bigView(tester);
    List<ChainDiscountProfileModel> saved = [];
    var profiles = <ChainDiscountProfileModel>[];
    Future<void> onSave(List<ChainDiscountProfileModel> next) async {
      saved = next;
    }

    await tester.pumpWidget(_host(ChainDiscountProfilesCard(profiles: profiles, onSave: onSave)));
    expect(find.textContaining('لا توجد سلاسل مضافة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chain_discount_chain_field')), 'fathalla');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_vat_field')), '5');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '12');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_additional_field')), '20');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(saved.single.chain, 'fathalla');
    expect(saved.single.vatRatePct, 5);
    expect(saved.single.invoiceDiscountPct, 12);
    expect(saved.single.additionalDiscountPct, 20);

    profiles = saved;
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(profiles: profiles, onSave: onSave)));
    for (final col in ['المؤسسة / السلسلة', 'الضريبة', 'خصم الفاتورة', 'الخصم الإضافي', 'آخر تحديث']) {
      expect(find.text(col), findsOneWidget, reason: col);
    }
    expect(find.text('fathalla'), findsOneWidget);
    expect(find.text('5%'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);

    // Row tap opens the form with the saved values; the chain name is locked.
    await tester.tap(find.byKey(const ValueKey('chain_terms_row_fathalla')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('chain_discount_vat_field'))).controller!.text, '5');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('chain_discount_chain_field'))).enabled, isFalse);

    // Out-of-range values are rejected in the dialog.
    await tester.enterText(find.byKey(const ValueKey('chain_discount_vat_field')), '120');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('الضريبة يجب'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chain_discount_vat_field')), '22.5');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '100');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('الخصومات يجب'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '15');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(saved.single.invoiceDiscountPct, 15);
    expect(saved.single.vatRatePct, 22.5, reason: 'VAT accepts any number in range');

    // Delete from the form returns the chain to the defaults.
    await tester.tap(find.byKey(const ValueKey('chain_terms_row_fathalla')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chain_discount_delete_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chain_discount_confirm_delete_btn')));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('duplicate chain names are rejected', (tester) async {
    _bigView(tester);
    var calls = 0;
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: const [
        ChainDiscountProfileModel(chain: 'Fathalla', invoiceDiscountPct: 10, additionalDiscountPct: 0)
      ],
      onSave: (_) async => calls++,
    )));
    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chain_discount_chain_field')), ' fathalla ');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('مضافة بالفعل'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('read-only for non-admin roles: no add, no save, no delete', (tester) async {
    _bigView(tester);
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      canEdit: false,
      profiles: const [
        ChainDiscountProfileModel(chain: 'fathalla', invoiceDiscountPct: 10, additionalDiscountPct: 0, vatRatePct: 14)
      ],
      onSave: (_) async => fail('read-only must never save'),
    )));
    expect(find.byKey(const ValueKey('chain_discount_add_btn')), findsNothing);
    expect(find.byKey(const ValueKey('chain_terms_read_only_hint')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chain_terms_row_fathalla')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_save_btn')), findsNothing);
    expect(find.byKey(const ValueKey('chain_discount_delete_btn')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('chain_discount_vat_field'))).enabled, isFalse);
  });
}

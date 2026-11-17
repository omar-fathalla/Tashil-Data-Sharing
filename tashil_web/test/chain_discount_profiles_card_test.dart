import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/product_master/data/chain_discount_repository.dart';
import 'package:tashil_web/features/product_master/presentation/widgets/chain_discount_profiles_card.dart';

import 'helpers/m3_dropdown_tester.dart';

const _fathalla = KnownChain(
  key: 'fathalla',
  displayName: 'أسواق فتح الله (Fathalla Market)',
);
const _gomla = KnownChain(
  key: 'gomla',
  displayName: 'جملة ماركت (Gomla Market)',
);

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

    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: profiles,
      knownChains: const [_fathalla],
      onSave: onSave,
    )));
    expect(find.textContaining('لا توجد سلاسل مضافة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_chain_field')), findsNothing);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    final menu = tester.widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>));
    expect(menu.enableSearch, isFalse);
    expect(menu.enableFilter, isFalse);
    expect(menu.requestFocusOnTap, isFalse);
    final chainField = tester.widget<TextField>(find.descendant(
      of: find.byKey(const ValueKey('chain_discount_chain_dropdown')),
      matching: find.byType(TextField),
    ));
    expect(chainField.readOnly, isTrue, reason: 'the chain control accepts no typing');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('chain_discount_chain_dropdown')),
        matching: find.byType(TextField),
      ),
      'typed-chain',
    );
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(find.text(kKnownChainsPickMessage), findsOneWidget);
    expect(saved, isEmpty);
    await selectM3Option(
      tester,
      find.byKey(const ValueKey('chain_discount_chain_dropdown')),
      'فتح الله',
    );
    await tester.enterText(find.byKey(const ValueKey('chain_discount_vat_field')), '5');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_invoice_field')), '12');
    await tester.enterText(find.byKey(const ValueKey('chain_discount_additional_field')), '20');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(saved.single.chain, 'fathalla',
        reason: 'the saved key is the enrichment key, not the Arabic display name');
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

  testWidgets('chains already saved are disabled with مضافة بالفعل', (tester) async {
    _bigView(tester);
    List<ChainDiscountProfileModel> saved = [];
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: const [
        ChainDiscountProfileModel(chain: 'Fathalla', invoiceDiscountPct: 10, additionalDiscountPct: 0)
      ],
      knownChains: const [_fathalla, _gomla],
      onSave: (next) async => saved = next,
    )));
    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chain_discount_chain_dropdown')));
    await tester.pumpAndSettle();
    expect(find.textContaining(kKnownChainsAlreadyAdded), findsWidgets);
    final disabled = tester
        .widgetList<MenuItemButton>(find.byType(MenuItemButton))
        .where((b) => b.onPressed == null);
    expect(disabled, isNotEmpty, reason: 'the saved chain cannot be chosen again');
    expect(
      tester.widgetList<MenuItemButton>(find.byType(MenuItemButton)).where((b) => b.onPressed != null),
      isNotEmpty,
      reason: 'a chain without saved terms stays selectable',
    );
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('chain_discount_chain_dropdown')),
      matching: find.byType(TextField),
    ));
    await tester.pumpAndSettle();
    await selectM3Option(
      tester,
      find.byKey(const ValueKey('chain_discount_chain_dropdown')),
      'جملة',
    );
    await tester.enterText(find.byKey(const ValueKey('chain_discount_vat_field')), '14');
    await tester.tap(find.byKey(const ValueKey('chain_discount_save_btn')));
    await tester.pumpAndSettle();
    expect(saved.map((p) => p.chain).toList(), ['Fathalla', 'gomla']);
  });

  testWidgets('empty chain list shows Arabic retry and no free-text field', (tester) async {
    _bigView(tester);
    var calls = 0;
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: const [],
      loadKnownChains: () async {
        calls++;
        if (calls == 1) return const [];
        return const [_fathalla];
      },
      onSave: (_) async {},
    )));
    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_chains_empty')), findsOneWidget);
    expect(find.text(kKnownChainsEmptyMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('chain_discount_chain_field')), findsNothing);
    expect(find.byType(DropdownMenu<String>), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('chain_discount_save_btn'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('chain_discount_chains_retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('chain_discount_chain_dropdown')), findsOneWidget);
  });

  testWidgets('chain list failure shows Arabic retry and never a raw exception', (tester) async {
    _bigView(tester);
    var calls = 0;
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: const [],
      loadKnownChains: () async {
        calls++;
        if (calls == 1) {
          throw TimeoutException('Future not completed', const Duration(seconds: 5));
        }
        return const [_fathalla];
      },
      onSave: (_) async => fail('must not save without a selected chain'),
    )));
    await tester.tap(find.byKey(const ValueKey('chain_discount_add_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_chains_error')), findsOneWidget);
    expect(find.text(kKnownChainsTimeoutMessage), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
    expect(find.textContaining('Future not completed'), findsNothing);
    expect(find.byType(DropdownMenu<String>), findsNothing);
    expect(find.byKey(const ValueKey('chain_discount_chain_field')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chain_discount_chains_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain_discount_chain_dropdown')), findsOneWidget);
    expect(calls, 2);
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

  test('آخر تحديث is date only — never email or clock time', () {
    expect(
      formatChainDiscountUpdatedAt(DateTime.utc(2026, 11, 17, 19, 45)),
      '2026-11-17',
    );
    expect(formatChainDiscountUpdatedAt(null), isEmpty);
  });

  testWidgets('آخر تحديث column shows yyyy-MM-dd only, not email or time',
      (tester) async {
    _bigView(tester);
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: [
        ChainDiscountProfileModel(
          chain: 'fathalla',
          invoiceDiscountPct: 10,
          additionalDiscountPct: 10,
          vatRatePct: 14,
          updatedAt: DateTime.utc(2026, 11, 17, 19, 45),
          updatedBy: 'admin@adeco.test',
        ),
      ],
      onSave: (_) async {},
    )));
    expect(find.text('2026-11-17'), findsOneWidget);
    expect(find.textContaining('admin@adeco.test'), findsNothing);
    expect(find.textContaining('19:45'), findsNothing);
    expect(find.textContaining('21:45'), findsNothing);
  });

  testWidgets('while saving the add button and the table rows are disabled', (tester) async {
    _bigView(tester);
    var saves = 0;
    const profiles = [
      ChainDiscountProfileModel(chain: 'fathalla', invoiceDiscountPct: 10, additionalDiscountPct: 0, vatRatePct: 14)
    ];
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: profiles,
      saving: true,
      onSave: (_) async => saves++,
    )));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('chain_discount_add_btn'))).onPressed, isNull);
    expect(tester.widget<AbsorbPointer>(find.byKey(const ValueKey('pm_chain_discount_absorb'))).absorbing, isTrue);
    await tester.tap(find.byKey(const ValueKey('chain_terms_row_fathalla')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('chain_discount_save_btn')), findsNothing,
        reason: 'no edit dialog opens while a save is in flight');
    expect(saves, 0);

    await tester.pumpWidget(_host(ChainDiscountProfilesCard(profiles: profiles, onSave: (_) async => saves++)));
    expect(tester.widget<AbsorbPointer>(find.byKey(const ValueKey('pm_chain_discount_absorb'))).absorbing, isFalse);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('chain_discount_add_btn'))).onPressed, isNotNull);
  });

  testWidgets('a double tap on «حفظ» submits once', (tester) async {
    _bigView(tester);
    final saved = <List<ChainDiscountProfileModel>>[];
    await tester.pumpWidget(_host(ChainDiscountProfilesCard(
      profiles: const [
        ChainDiscountProfileModel(chain: 'fathalla', invoiceDiscountPct: 10, additionalDiscountPct: 0, vatRatePct: 14)
      ],
      onSave: (next) async => saved.add(next),
    )));
    await tester.tap(find.byKey(const ValueKey('chain_terms_row_fathalla')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('chain_discount_save_btn'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/widgets/sell_in_price_waterfall_card.dart';

import 'oos_m3_support.dart';
import 'support/sell_in_waterfall_fixture.dart';

class _WaterfallApi extends ApiClient {
  _WaterfallApi(this.response) : super(tenantId: 'tenant-adeco');
  final SellInExplorerResponse response;

  @override
  Future<SellInExplorerResponse> getSellInRecords({
    String? chain,
    int? year,
    int? month,
    String? region,
    String? sector,
    String? brand,
    String? query,
    int limit = 250,
    int offset = 0,
    bool cacheable = true,
  }) async =>
      response;
}

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SellInExplorerScreen(apiClient: api)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The card alone at a page content width, in the 250dp-sidebar shell, with the real Cairo font.
Future<void> _pumpCard(WidgetTester tester, double viewport, SellInExplorerResponse data, {bool loading = false}) async {
  tester.view.physicalSize = Size(viewport, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Row(children: [
          const SizedBox(width: 250),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SellInPriceWaterfallCard(data: data, chainLabel: (c) => c, loading: loading),
            ),
          ),
        ]),
      ),
    ),
  ));
  await tester.pump();
}

String _value(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey('sellin_waterfall_${key}_value'))).data!;

String _badge(WidgetTester tester, String key) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(ValueKey('sellin_waterfall_${key}_badge')), matching: find.byType(Text)))
    .data!;

String _tooltip(WidgetTester tester, String key) => tester
    .widget<Tooltip>(find.ancestor(of: find.byKey(ValueKey('sellin_waterfall_$key')), matching: find.byType(Tooltip)).first)
    .message!;

const _labels = [
  'السعر الرسمي',
  'خصم الفاتورة',
  'خصم إضافي',
  'الصافي المتوقع',
  'فروق التنفيذ',
  'بلا سعر رسمي',
  'صافي التوريد',
  'الضريبة',
  'الفواتير',
];

void main() {
  setUp(AppCache.clear);

  test('SellInExplorerResponse parses the expected net, execution, unpriced and chain terms', () {
    final r = SellInExplorerResponse.fromJson({
      'total_value_egp': 135.5,
      'total_net_excl_vat_egp': 135.5,
      'total_official_list_excl_vat_egp': 100.0,
      'total_invoice_discount_egp': 10.0,
      'total_extra_chain_discount_egp': 4.5,
      'total_expected_net_egp': 85.5,
      'total_execution_difference_egp': 0.0,
      'total_other_difference_egp': 0.0,
      'total_unpriced_net_egp': 50.0,
      'invoice_discount_pct': 10.0,
      'extra_discount_pct': 5.0,
      'terms_averaged': false,
      'vat_rate_pct': 14.0,
      'chain_terms': [
        {'chain': 'fathalla', 'saved': true, 'invoice_discount_pct': 10, 'extra_discount_pct': 5, 'vat_rate_pct': 14},
      ],
    });
    expect(r.totalExpectedNetEgp, 85.5);
    expect(r.totalUnpricedNetEgp, 50.0);
    expect(r.extraDiscountPct, 5.0);
    expect(r.termsAveraged, isFalse);
    expect(r.chainTerms.single.saved, isTrue);
    expect(r.chainTerms.single.extraDiscountPct, 5.0);
  });

  test('older payloads still add up: the whole list − net gap is the execution difference', () {
    final r = SellInExplorerResponse.fromJson({
      'total_value_egp': 900.0,
      'total_official_list_excl_vat_egp': 1000.0,
      'total_discount_granted_egp': 100.0,
    });
    expect(r.vatRatePct, 14.0);
    expect(r.totalExpectedNetEgp, 1000.0);
    expect(r.totalExecutionDifferenceEgp, 100.0);
    expect(r.totalUnpricedNetEgp, 0.0);
    expect(r.invoiceDiscountPct, 0.0);
  });

  test('expected carton price = list × (1 − invoice) × (1 − extra) per row', () {
    final rows = {for (final r in demoRecords) r.recordId: r};
    expect(rows['a']!.expectedCartonExclVatEgp, 85.5);
    expect(rows['f']!.expectedCartonExclVatEgp, 90.0);
    expect(rows['e']!.expectedCartonExclVatEgp, 0.0);
  });

  test('demo fixture reconciles like the backend card', () {
    for (final d in [demoWaterfallResponse(demoAllChains), demoWaterfallResponse(demoFathalla)]) {
      int c(double v) => (v * 100).round();
      expect(c(d.totalOfficialListExclVatEgp) - c(d.totalInvoiceDiscountEgp) - c(d.totalExtraChainDiscountEgp),
          c(d.totalExpectedNetEgp));
      expect(c(d.totalExpectedNetEgp) - c(d.totalExecutionDifferenceEgp) + c(d.totalUnpricedNetEgp),
          c(d.totalNetExclVatEgp));
      expect(c(d.totalNetExclVatEgp) + c(d.totalVat14Egp), c(d.totalGrossInclVatEgp));
    }
  });

  test('CPFR payload carries the matched factory cost excl. VAT', () {
    expect(
        CPFRDashboardModel.fromJson({
          'matched_sell_out_factory_cost_egp': 114.0,
          'matched_sell_out_factory_cost_excl_vat_egp': 100.0,
        }).matchedSellOutFactoryCostExclVatEgp,
        100.0);
    expect(
        CPFRDashboardModel.fromJson({
          'matched_sell_out_factory_cost_egp': 114.0,
        }).matchedSellOutFactoryCostExclVatEgp,
        114.0);
  });

  testWidgets('one chain: badges show the saved terms exactly (extra 5%, not 4.5% of official)', (tester) async {
    await _pump(tester, _WaterfallApi(demoWaterfallResponse(demoFathalla)));
    expect(find.byKey(const ValueKey('sellin_waterfall_row_settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('sellin_waterfall_row_actual')), findsOneWidget);
    for (final l in _labels) {
      expect(find.text(l), findsWidgets, reason: 'missing $l');
    }
    expect(find.text('فروق أخرى'), findsNothing);
    expect(_badge(tester, 'invoice'), '10%');
    expect(_badge(tester, 'extra'), '5%');
    expect(_badge(tester, 'vat'), '14%');
    expect(find.text('fathalla • إعدادات محفوظة'), findsNothing); // chain names are localised
    expect(find.text('فتح الله • إعدادات محفوظة'), findsOneWidget);
    // Amounts in M; the full value is in the tooltip.
    expect(_value(tester, 'official'), contains('80'));
    expect(_value(tester, 'official'), contains('M'));
    expect(_tooltip(tester, 'expected'), contains('68,400,000.00'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all chains: weighted «متوسط» badges with the per-chain breakdown in the tooltip', (tester) async {
    final data = demoWaterfallResponse(demoAllChains);
    await _pump(tester, _WaterfallApi(data));
    expect(_badge(tester, 'invoice'), 'متوسط ${SellInPriceWaterfallCard.pct(data.invoiceDiscountPct, decimals: 1)}');
    expect(_tooltip(tester, 'invoice'), contains(SellInPriceWaterfallCard.pct(data.invoiceDiscountPct)));
    expect(_badge(tester, 'extra'), startsWith('متوسط '));
    expect(find.text('كل السلاسل • كل سلسلة بإعداداتها'), findsOneWidget);
    final tip = _tooltip(tester, 'extra');
    expect(tip, contains('فتح الله: 5%'));
    expect(tip, contains('جملة ماركت: 0% (افتراضي)'));
    expect(tip, contains('كارفور: 2%'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('execution differences can be negative (rows invoiced above expected)', (tester) async {
    await _pump(
        tester, _WaterfallApi(demoWaterfallResponse(const [DemoChain('fathalla', 100, extraPct: 5, saved: true, execution: -19.5)])));
    expect(find.text('أعلى من المتوقع'), findsOneWidget);
    expect(_value(tester, 'execution'), contains('\u2212'));
    expect(_value(tester, 'net'), contains('105'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading shows skeletons instead of amounts', (tester) async {
    await _pumpCard(tester, 1280, demoWaterfallResponse(demoFathalla), loading: true);
    expect(find.byKey(const ValueKey('sell_in_waterfall_skeleton')), findsNWidgets(9));
    expect(find.byKey(const ValueKey('sellin_waterfall_net_value')), findsNothing);
  });

  group('layout with the real Cairo font', () {
    setUpAll(loadOosFonts);

    for (final width in const [1024.0, 1280.0, 1440.0]) {
      for (final entry in {'all chains': demoAllChains, 'one chain': demoFathalla}.entries) {
        testWidgets('no clipped label or amount @$width (${entry.key})', (tester) async {
          await _pumpCard(tester, width, demoWaterfallResponse(entry.value));
          final strip = find.byKey(const ValueKey('sellin_waterfall_strip'));
          final stripRect = tester.getRect(strip);
          final chipRects = <Rect>[];
          for (final key in ['official', 'invoice', 'extra', 'expected', 'execution', 'unpriced', 'net', 'vat', 'invoices']) {
            final chip = find.byKey(ValueKey('sellin_waterfall_$key'));
            final r = tester.getRect(chip);
            expect(r.left, greaterThanOrEqualTo(stripRect.left - 0.5), reason: '$key clipped');
            expect(r.right, lessThanOrEqualTo(stripRect.right + 0.5), reason: '$key clipped');
            for (final other in chipRects) {
              expect(r.overlaps(other.deflate(0.5)), isFalse, reason: '$key overlaps another step');
            }
            chipRects.add(r);
            for (final p in tester.renderObjectList<RenderParagraph>(find.descendant(of: chip, matching: find.byType(RichText)))) {
              expect(p.didExceedMaxLines, isFalse, reason: '$key: "${p.text.toPlainText()}" ellipsized');
            }
          }
          // Wide enough: each row stays on one line, both with the row label beside the chips.
          if (width >= 1280) {
            final top = chipRects.first.top;
            expect(chipRects.take(4).every((r) => (r.top - top).abs() < 1), isTrue);
            final top2 = chipRects[4].top;
            expect(chipRects.skip(4).every((r) => (r.top - top2).abs() < 1), isTrue);
            expect(chipRects[4].right, closeTo(chipRects[0].right, 1), reason: 'row 2 fell back to stacked label');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('records table: expected carton price and its difference vs actual', (tester) async {
    await _pump(
        tester,
        _WaterfallApi(demoWaterfallResponse(demoFathalla, records: demoRecords, cases: 6, units: 60)));
    expect(find.byKey(const ValueKey('sellin_expected_carton_header')), findsOneWidget);
    final expected = tester.widgetList<Text>(find.byKey(const ValueKey('sellin_record_expected_carton'))).map((t) => t.data).toList();
    final diffs = tester.widgetList<Text>(find.byKey(const ValueKey('sellin_record_expected_carton_diff'))).map((t) => t.data!).toList();
    expect(expected.first, contains('85.50'));
    expect(expected.contains('—'), isTrue); // unpriced row
    expect(diffs.first, 'مطابق');
    expect(diffs[1], contains('5.50'));
    expect(diffs[1], contains('\u2212'));
    expect(diffs[3], contains('+19.50'));
    expect(tester.takeException(), isNull);
  });

  test('card file follows the M3 conventions', () {
    final src = File('lib/features/sell_out_analytics/presentation/widgets/sell_in_price_waterfall_card.dart').readAsStringSync();
    expect(RegExp(r'(?<![A-Za-z0-9_])Colors\.').hasMatch(src), isFalse);
    expect(src.contains('purple'), isFalse, reason: 'VAT uses a theme colour role, not violet');
    expect(RegExp(r'fontSize:\s*[\d.]+').hasMatch(src), isFalse);
  });
}

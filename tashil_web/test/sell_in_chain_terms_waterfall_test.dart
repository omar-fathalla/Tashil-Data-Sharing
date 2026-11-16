import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/data/app_cache.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart';

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

void main() {
  setUp(AppCache.clear);

  test('SellInExplorerResponse parses the waterfall split and chain VAT', () {
    final r = SellInExplorerResponse.fromJson({
      'total_value_egp': 900.0,
      'total_official_list_excl_vat_egp': 1000.0,
      'total_discount_granted_egp': 100.0,
      'total_invoice_discount_egp': 80.0,
      'total_extra_chain_discount_egp': 18.0,
      'total_other_difference_egp': 2.0,
      'vat_rate_pct': 5.0,
    });
    expect(r.totalInvoiceDiscountEgp, 80.0);
    expect(r.totalExtraChainDiscountEgp, 18.0);
    expect(r.totalOtherDifferenceEgp, 2.0);
    expect(r.vatRatePct, 5.0);
  });

  test('old payloads default to 14% VAT and put the whole discount in "other"',
      () {
    final r = SellInExplorerResponse.fromJson({
      'total_value_egp': 900.0,
      'total_official_list_excl_vat_egp': 1000.0,
      'total_discount_granted_egp': 100.0,
    });
    expect(r.vatRatePct, 14.0);
    expect(r.totalExtraChainDiscountEgp, 0.0);
    expect(r.totalOtherDifferenceEgp, 100.0);
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

  testWidgets(
      'waterfall shows invoice discount, the extra chain discount line and the chain VAT rate',
      (tester) async {
    await _pump(
      tester,
      _WaterfallApi(const SellInExplorerResponse(
        records: [],
        totalCount: 0,
        totalValueEgp: 8100000,
        totalCases: 1000,
        totalWeightTons: 1,
        totalExpectedEgp: 0,
        totalOfficialListExclVatEgp: 10000000,
        totalDiscountGrantedEgp: 1900000,
        totalInvoiceDiscountEgp: 1000000,
        totalExtraChainDiscountEgp: 900000,
        totalOtherDifferenceEgp: 0,
        vatRatePct: 5,
        totalNetExclVatEgp: 8100000,
        totalVat14Egp: 405000,
        totalGrossInclVatEgp: 8505000,
      )),
    );
    expect(find.text('2. خصم الفاتورة'), findsWidgets);
    expect(find.text('3. خصم إضافي للسلسلة'), findsWidgets);
    expect(find.text('4. فروق أخرى'), findsNothing);
    expect(find.text('5. الضريبة 5%'), findsWidgets);
    expect(find.text('5. الضريبة 14%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leftover price difference gets its own line', (tester) async {
    await _pump(
      tester,
      _WaterfallApi(const SellInExplorerResponse(
        records: [],
        totalCount: 0,
        totalValueEgp: 8000000,
        totalCases: 1000,
        totalWeightTons: 1,
        totalExpectedEgp: 0,
        totalOfficialListExclVatEgp: 10000000,
        totalDiscountGrantedEgp: 2000000,
        totalInvoiceDiscountEgp: 1000000,
        totalExtraChainDiscountEgp: 0,
        totalOtherDifferenceEgp: 1000000,
        totalNetExclVatEgp: 8000000,
        totalVat14Egp: 1120000,
        totalGrossInclVatEgp: 9120000,
      )),
    );
    expect(find.text('4. فروق أخرى'), findsWidgets);
    expect(find.text('6. الضريبة 14%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sell-Out card is labelled as the consumer retail price',
      (tester) async {
    await _pump(tester, ApiClient(tenantId: 'tenant-adeco'));
    final tab = find.textContaining(RegExp('^المخزون وإعادة الطلب\$'));
    await tester.ensureVisible(tab.first);
    await tester.tap(tab.first);
    await tester.pumpAndSettle();
    expect(find.text('Sell-Out بسعر البيع للمستهلك'), findsWidgets);
    expect(find.text('Sell-Out بالتكلفة'), findsNothing);
  });
}

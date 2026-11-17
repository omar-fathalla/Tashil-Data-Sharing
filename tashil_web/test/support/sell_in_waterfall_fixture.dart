import 'package:tashil_web/core/network/api_client.dart';

/// Made-up demo data for the Sell-In «من السعر الرسمي إلى الفاتورة» card (tests and screenshots only).

double _r2(double v) => (v * 100).roundToDouble() / 100;

class DemoChain {
  const DemoChain(this.chain, this.official,
      {this.invoicePct = 10, this.extraPct = 0, this.vatPct = 14, this.saved = false, this.execution = 0, this.unpriced = 0});

  final String chain;
  final double official;
  final double invoicePct;
  final double extraPct;
  final double vatPct;
  final bool saved;
  final double execution;
  final double unpriced;

  double get invoice => _r2(official * invoicePct / 100);
  double get extra => _r2((official - official * invoicePct / 100) * extraPct / 100);
  double get expected => _r2(official - invoice - extra);
  double get net => _r2(expected - execution + unpriced);
}

/// Builds the response the backend would send, rounded like `sellInCard` so the card adds up.
SellInExplorerResponse demoWaterfallResponse(List<DemoChain> chains,
    {List<SellInRecordItem> records = const [], double cases = 0, int units = 0}) {
  double sum(double Function(DemoChain c) f) => _r2(chains.fold(0.0, (a, c) => a + f(c)));
  final official = sum((c) => c.official);
  final invoice = sum((c) => c.invoice);
  final extra = sum((c) => c.extra);
  final expected = _r2(official - invoice - extra);
  final unpriced = sum((c) => c.unpriced);
  final net = sum((c) => c.net);
  final gross = sum((c) => _r2(c.net * (1 + c.vatPct / 100)));
  final averaged = chains.length > 1;
  return SellInExplorerResponse(
    records: records,
    totalCount: records.length,
    totalValueEgp: net,
    totalCases: cases,
    totalUnitsPieces: units,
    totalWeightTons: 0,
    totalExpectedEgp: 0,
    totalOfficialListExclVatEgp: official,
    totalDiscountGrantedEgp: _r2(official - (net - unpriced)),
    effectiveDiscountPct: official > 0 ? _r2((official - (net - unpriced)) / official * 100) : 0,
    totalInvoiceDiscountEgp: invoice,
    totalExtraChainDiscountEgp: extra,
    totalExpectedNetEgp: expected,
    totalExecutionDifferenceEgp: _r2(expected + unpriced - net),
    totalUnpricedNetEgp: unpriced,
    invoiceDiscountPct: averaged ? _r2(invoice / official * 100) : chains.single.invoicePct,
    extraDiscountPct: averaged ? _r2(extra / (official - invoice) * 100) : chains.single.extraPct,
    termsAveraged: averaged,
    chainTerms: [
      for (final c in chains)
        SellInChainTerms(
          chain: c.chain,
          saved: c.saved,
          invoiceDiscountPct: c.invoicePct,
          extraDiscountPct: c.extraPct,
          vatRatePct: c.vatPct,
          officialListExclVatEgp: c.official,
          invoiceDiscountEgp: c.invoice,
          extraDiscountEgp: c.extra,
          expectedNetEgp: c.expected,
          unpricedNetEgp: c.unpriced,
          netExclVatEgp: c.net,
        ),
    ],
    vatRatePct: averaged ? _r2((gross - net) / net * 100) : chains.single.vatPct,
    totalNetExclVatEgp: net,
    totalVat14Egp: _r2(gross - net),
    totalGrossInclVatEgp: gross,
  );
}

const demoAllChains = [
  DemoChain('fathalla', 80000000, extraPct: 5, saved: true, execution: 5000000, unpriced: 2100000),
  DemoChain('gomla', 50000000, execution: 3500000, unpriced: 1200000),
  DemoChain('carrefour', 36370000, invoicePct: 12, extraPct: 2, saved: true, execution: 1000000, unpriced: 630000),
];

const demoFathalla = [DemoChain('fathalla', 80000000, extraPct: 5, saved: true, execution: 5000000, unpriced: 2100000)];

SellInRecordItem demoRecord(String id, String name, String chain, double cases, double net,
    {double carton = 100, double invoicePct = 10, double extraPct = 0}) {
  return SellInRecordItem(
    recordId: id,
    tenantId: 'tenant-demo',
    retailerChain: chain,
    year: 2026,
    monthNum: 9,
    monthEn: 'September',
    monthAr: 'سبتمبر',
    periodWeek: 'Full Month',
    regionCode: 'ALX',
    governorate: 'الاسكندرية',
    sector: 'MT',
    customerName: chain,
    itemCode: carton > 0 ? 'DEMO-0000-$id' : '',
    brand: 'علامة تجريبية',
    subCategory: 'فئة تجريبية',
    itemName: name,
    unitsPerCarton: 10,
    promotionType: 'عادي',
    salesManager: '',
    kaOfficer: '',
    salesRep: 'مندوب تجريبي',
    netQtyCases: cases,
    netValueEgp: net,
    weightTons: 0.1,
    expectedQtyCases: 0,
    expectedValueEgp: 0,
    transactionType: 'مسحوبات بيع (Sale)',
    totalUnitsSupplied: (cases * 10).round(),
    officialCartonExclVatEgp: carton,
    invoiceDiscountPct: carton > 0 ? invoicePct : 0,
    extraDiscountPct: carton > 0 ? extraPct : 0,
    grossValueInclVatEgp: _r2(net * 1.14),
    vatAmountEgp: _r2(net * 0.14),
    officialListValueExclEgp: _r2(cases * carton),
    actualCasePriceExclEgp: cases != 0 ? _r2(net / cases) : 0,
  );
}

/// The owner's 100 EGP scenarios (Fathalla invoice 10% / extra 5% → expected 85.50) plus a default chain row.
final demoRecords = [
  demoRecord('a', 'صنف تجريبي أ — مطابق للمتوقع', 'fathalla', 1, 85.5, extraPct: 5),
  demoRecord('b', 'صنف تجريبي ب — خصم أعمق', 'fathalla', 1, 80, extraPct: 5),
  demoRecord('c', 'صنف تجريبي ج — بدون الخصم الإضافي', 'fathalla', 1, 90, extraPct: 5),
  demoRecord('d', 'صنف تجريبي د — أعلى من القائمة', 'fathalla', 1, 105, extraPct: 5),
  demoRecord('e', 'صنف تجريبي هـ — بلا سعر رسمي', 'fathalla', 1, 50, carton: 0),
  demoRecord('f', 'صنف تجريبي و — سلسلة بالافتراضي 10%', 'gomla', 1, 90),
];

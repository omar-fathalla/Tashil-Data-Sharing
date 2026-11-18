import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';
import 'package:tashil_web/features/sell_out_analytics/domain/branch_brand_filter.dart';

SellOutRecordModel _rec({
  required String sku,
  required String store,
  required double rev,
  int units = 1,
  String chain = 'fathalla',
  String itemCode = '',
  String barcode = '',
}) {
  return SellOutRecordModel(
    recordId: 'r_$sku$store',
    retailerChain: chain,
    storeId: store,
    storeName: store,
    itemCode: itemCode,
    barcode: barcode.isEmpty ? 'bc_$sku' : barcode,
    skuName: sku,
    category: 'منظفات',
    quantitySold: units,
    netRevenue: rev,
    unitPrice: rev,
    transactionDate: '2026-03-15',
  );
}

void main() {
  group('brandLabelMatches', () {
    test('matches Arabic, English, and full labels with ڤ/ف fold', () {
      expect(brandLabelMatches('ديفا (Diva)', 'Diva'), isTrue);
      expect(brandLabelMatches('ديفا (Diva)', 'ديفا'), isTrue);
      expect(brandLabelMatches('فلڤيتا (Velveta)', 'فلفيتا'), isTrue);
      expect(brandLabelMatches('فلڤيتا (Velveta)', 'Velveta'), isTrue);
      expect(brandLabelMatches('ديفا (Diva)', 'Velveta'), isFalse);
    });

    test('all-brands filter matches every label (record filter semantics)', () {
      expect(isAllBrandsFilter('all'), isTrue);
      expect(isAllBrandsFilter('كل العلامات التجارية'), isTrue);
      expect(brandLabelMatches('ديفا (Diva)', 'all'), isTrue);
    });
  });

  group('resolvePerfBrandDropdownValue', () {
    test('all filter stays all — never picks first catalog brand', () {
      const brands = ['ديفا (Diva)', 'فلڤيتا (Velveta)', 'كلوريل (Clorel)'];
      expect(resolvePerfBrandDropdownValue('all', brands), 'all');
      expect(resolvePerfBrandDropdownValue('كل العلامات التجارية', brands), 'all');
      // Regression: brandLabelMatches(brand, 'all') is true for every brand;
      // firstWhere would have "restored" ديفا after hard refresh.
      expect(
        brands.any((b) => brandLabelMatches(b, 'all')),
        isTrue,
        reason: 'documents why dropdown must not use brandLabelMatches for value',
      );
    });

    test('resolves concrete filter to catalog label', () {
      const brands = ['ديفا (Diva)', 'فلڤيتا (Velveta)', 'كلوريل (Clorel)'];
      expect(resolvePerfBrandDropdownValue('Diva', brands), 'ديفا (Diva)');
      expect(resolvePerfBrandDropdownValue('فلفيتا', brands), 'فلڤيتا (Velveta)');
      expect(resolvePerfBrandDropdownValue('unknown', brands), 'all');
    });
  });

  group('SmartBrandExtractor Divatol → Diva', () {
    test('ديفاتول maps into the Diva brand bucket', () {
      expect(
        SmartBrandExtractor.inferBrand('ديفاتول مطهر 750 مل'),
        'ديفا (Diva)',
      );
      expect(
        SmartBrandExtractor.inferBrand('أي صنف', itemCode: 'FGDG-0750-0091'),
        'ديفا (Diva)',
      );
    });
  });

  group('branch performance brand filter', () {
    final records = [
      _rec(sku: 'شامبو ديفا 400 مل', store: 's1', rev: 1000, units: 10),
      _rec(sku: 'ديفاتول مطهر 750 مل', store: 's2', rev: 500, units: 5),
      _rec(sku: 'فلفيتا جيل 750 مل', store: 's1', rev: 800, units: 8),
      _rec(sku: 'كلوريل أبيض 1050 جم', store: 's2', rev: 2000, units: 20),
      _rec(sku: 'صنف عشوائي بلا علامة معروفة xyz', store: 's1', rev: 300, units: 3),
    ];

    test('selecting Diva / Velveta filters records and changes KPI aggregates', () {
      final allRev = records.fold<double>(0, (s, r) => s + r.netRevenue);
      expect(allRev, 4600);

      final diva = filterRecordsByBrand(records, 'Diva');
      final divaRev = diva.fold<double>(0, (s, r) => s + r.netRevenue);
      expect(divaRev, 1500);

      final vel = filterRecordsByBrand(records, 'فلفيتا');
      expect(vel.fold<double>(0, (s, r) => s + r.netRevenue), 800);

      final skusDiva = aggregatePerfSkus(diva);
      expect(skusDiva.first.brand, 'ديفا (Diva)');
      expect(skusDiva.fold<double>(0, (s, i) => s + i.revenue), 1500);

      final skusAll = aggregatePerfSkus(records);
      expect(skusAll.first.revenue, greaterThan(skusDiva.first.revenue));
    });

    test('all-brand total equals Σ named brands + unbranded remainder', () {
      final all = records.fold<double>(0, (s, r) => s + r.netRevenue);
      final diva = filterRecordsByBrand(records, 'Diva')
          .fold<double>(0, (s, r) => s + r.netRevenue);
      final vel = filterRecordsByBrand(records, 'Velveta')
          .fold<double>(0, (s, r) => s + r.netRevenue);
      final clorel = filterRecordsByBrand(records, 'Clorel')
          .fold<double>(0, (s, r) => s + r.netRevenue);
      final rem = all - diva - vel - clorel;
      expect(rem, closeTo(300, 0.01));
      expect(diva + vel + clorel + rem, closeTo(all, 0.01));

      // Helper reports the same remainder when fed the named catalog brands.
      expect(
        unbrandedRevenueRemainder(records, const [
          'ديفا (Diva)',
          'فلڤيتا (Velveta)',
          'كلوريل (Clorel)',
        ]),
        closeTo(300, 0.01),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';

void main() {
  group('competitorFromAiSuggestion brand legend', () {
    late ApiClient api;

    setUp(() {
      api = ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false);
    });

    CompetitorSuggestionModel sug({
      required String skuName,
      String brand = '',
      String supplier = '',
    }) {
      return CompetitorSuggestionModel(
        id: 'csug_oxi',
        ownBarcode: 'OWN1',
        ownSkuName: 'فيبا بلس اوكسي',
        ownCategory: 'مساحيق جيل اتوماتيك',
        competitorBarcode: 'COMP_OXI',
        competitorSkuName: skuName,
        competitorBrand: brand,
        competitorSupplier: supplier,
        category: 'مسحوق جيل اتوماتيك',
        retailerChain: 'fathalla',
        reasonAr: 'نفس الفئة',
        confidence: 0.82,
        rank: 1,
        status: 'pending',
        ownUnitPrice: 180,
        competitorUnitPrice: 150,
        ownUnits: 10,
        competitorUnits: 8,
        sizeLabelCompetitor: '3 كجم',
      );
    }

    test('infers أوكسي from SKU when brand/supplier empty (no generic منافس)', () {
      final model = api.competitorFromAiSuggestion(
        sug(skuName: 'أوكسى جيل اوتوماتيك نسيم العطور 3كجم'),
        ownUnitPrice: 180,
      );
      expect(model.brand, isNot(equals('منافس')));
      expect(model.brand, contains('أوكسي'));
    });

    test('keeps stored brand when present', () {
      final model = api.competitorFromAiSuggestion(
        sug(skuName: 'أوكسى جيل', brand: 'أوكسي (Oxi)'),
        ownUnitPrice: 180,
      );
      expect(model.brand, 'أوكسي (Oxi)');
    });

    test('replaces literal منافس placeholder via SKU inference', () {
      final model = api.competitorFromAiSuggestion(
        sug(skuName: 'بريل ليمون 1 لتر', brand: 'منافس'),
        ownUnitPrice: 180,
      );
      expect(model.brand, isNot(equals('منافس')));
      expect(model.brand, contains('بريل'));
    });

    test('Oxi spelling variants all resolve', () {
      for (final name in [
        'اوكسى جيل',
        'أوكسى جيل',
        'اوكسي جيل',
        'أوكسي جيل',
      ]) {
        final brand = ApiClient.inferBrandFromSkuOrSupplier(name, '');
        expect(brand, contains('أوكسي'), reason: name);
      }
    });
  });
}

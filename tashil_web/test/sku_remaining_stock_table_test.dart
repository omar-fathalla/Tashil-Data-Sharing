import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/cpfr_replenishment/domain/cpfr_models.dart';

void main() {
  group('SmartBrandExtractor AI Brand Inference', () {
    test('extracts known brands from arabic and english sku names', () {
      expect(
        SmartBrandExtractor.inferBrand('ماكسيل باور جل للغسيل 3 لتر'),
        equals('ماكسيل (Maxell)'),
      );
      expect(
        SmartBrandExtractor.inferBrand('Maxell Clean Powder 5kg'),
        equals('ماكسيل (Maxell)'),
      );
      expect(
        SmartBrandExtractor.inferBrand('شامبو ديفا للشعر الجاف 400 مل'),
        equals('ديفا (Diva)'),
      );
      expect(
        SmartBrandExtractor.inferBrand('صابون دوف مرطب 100 جم'),
        equals('دوف (Dove)'),
      );
      expect(
        SmartBrandExtractor.inferBrand('منعم ملابس فلڤيتا لافندر 2 لتر'),
        equals('فلڤيتا (Velveta)'),
      );
      expect(
        SmartBrandExtractor.inferBrand('سائل فيبا ليمون غسيل أطباق 1 لتر'),
        equals('فيبا (Feba)'),
      );
    });

    test('dynamically extracts brand tokens for novel companies and items', () {
      expect(
        SmartBrandExtractor.inferBrand('الضحى أرز مصري فاخر 5 كجم'),
        equals('الضحى'),
      );
      expect(
        SmartBrandExtractor.inferBrand('دومتي جبنة بيضاء فيتا 500 جم'),
        equals('دومتي'),
      );
      expect(
        SmartBrandExtractor.inferBrand('Corona Dark Chocolate 100g'),
        equals('Corona'),
      );
      expect(
        SmartBrandExtractor.inferBrand('بسكريم ماجيك شوكولاتة 50 جم'),
        equals('بسكريم ماجيك'),
      );
    });

    test('preserves valid existing brand if already accurately set', () {
      expect(
        SmartBrandExtractor.inferBrand('أي صنف عشوائي', existingBrand: 'نستله'),
        equals('نستله'),
      );
    });
  });

  group('SKUBranchInventoryModel fromJson Brand Inference', () {
    test('infers brand during model deserialization if missing or generic', () {
      final json = {
        'sku_name': 'ماكسيل صابون سائل 4 لتر',
        'brand': 'عام',
        'sector': 'MT',
        'sub_category': 'منظفات',
        'region_code': 'CIR',
        'governorate': 'القاهرة',
        'sales_rep': 'أحمد إبراهيم',
        'sell_in_cases': 100.0,
        'sell_in_value_egp': 25000.0,
        'sell_out_est_cases': 60.0,
        'sell_out_value_egp': 16000.0,
        'return_cases': 0.0,
        'return_value_egp': 0.0,
        'estimated_stock_cases': 40.0,
        'estimated_stock_value_egp': 9000.0,
        'daily_run_rate_cases': 2.0,
        'days_of_inventory': 20.0,
        'stock_status': 'optimal',
        'stock_status_ar': 'رصيد آمن',
        'case_price_egp': 250.0,
        'weight_tons': 1.2,
        'suggested_po_cases': 0,
        'suggested_po_value_egp': 0.0,
        'suggested_po_tons': 0.0,
      };

      final model = SKUBranchInventoryModel.fromJson(json);
      expect(model.skuName, equals('ماكسيل صابون سائل 4 لتر'));
      expect(model.brand, equals('ماكسيل (Maxell)'));
      expect(model.estimatedStockCases, equals(40.0));
      expect(model.daysOfInventory, equals(20.0));
    });

    test('paginates 60 items into exactly 25 items per page', () {
      final items = List.generate(60, (i) {
        return SKUBranchInventoryModel(
          skuName: 'صنف رقم $i',
          brand: i % 2 == 0 ? 'ماكسيل (Maxell)' : 'ديفا (Diva)',
          sector: 'MT',
          subCategory: 'عام',
          regionCode: 'CIR',
          governorate: 'القاهرة',
          salesRep: 'مندوب $i',
          sellInCases: (100 + i).toDouble(),
          sellInValueEgp: (1000 + i * 10).toDouble(),
          sellOutEstCases: 50.0,
          sellOutValueEgp: 500.0,
          returnCases: 0.0,
          returnValueEgp: 0.0,
          estimatedStockCases: (50 + i).toDouble(),
          estimatedStockValueEgp: (500 + i * 10).toDouble(),
          dailyRunRateCases: 2.0,
          daysOfInventory: (10 + i).toDouble(),
          stockStatus: 'optimal',
          stockStatusAr: 'رصيد آمن',
          casePriceEgp: 10.0,
          weightTons: 0.5,
          suggestedPoCases: 0,
          suggestedPoValueEgp: 0.0,
          suggestedPoTons: 0.0,
        );
      });

      const pageSize = 25;
      final totalPages = (items.length / pageSize).ceil();
      expect(totalPages, equals(3)); // 25 + 25 + 10 = 60 items

      // Page 0
      final page0 = items.sublist(0, 25);
      expect(page0.length, equals(25));
      expect(page0.first.skuName, equals('صنف رقم 0'));
      expect(page0.last.skuName, equals('صنف رقم 24'));

      // Page 1
      final page1 = items.sublist(25, 50);
      expect(page1.length, equals(25));
      expect(page1.first.skuName, equals('صنف رقم 25'));
      expect(page1.last.skuName, equals('صنف رقم 49'));

      // Page 2
      final page2 = items.sublist(50, 60);
      expect(page2.length, equals(10));
      expect(page2.first.skuName, equals('صنف رقم 50'));
      expect(page2.last.skuName, equals('صنف رقم 59'));
    });
  });
}


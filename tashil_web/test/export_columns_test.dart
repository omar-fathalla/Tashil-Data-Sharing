import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/utils/excel_export_service.dart';
import 'package:tashil_web/core/utils/export_columns.dart';

/// Pins the Excel export column order. If a UI change reorders a table,
/// exports must NOT change; update these lists only on purpose.
void main() {
  final expected = <String, List<String>>{
    'cpfrReplenishment': [
      'اسم الصنف (SKU)',
      'العلامة التجارية (Brand)',
      'القطاع (Sector)',
      'الإقليم (Region)',
      'المحافظة (Governorate)',
      'مندوب المبيعات (Sales Rep)',
      'إجمالي التوريد بالكرتونة (Sell-In Cases)',
      'البيع الفعلي التقديري بالكرتونة (Sell-Out Cases)',
      'المرتجعات بالكرتونة (Returns)',
      'الرصيد التقديري الحالي بالكرتونة (Est. Stock Cases)',
      'قيمة الرصيد التقديري (Est. Stock EGP)',
      'معدل السحب اليومي (Daily Run-Rate Cases)',
      'أيام تغطية المخزون (DOI Days)',
      'حالة الرصيد (Stock Status)',
      'أمر التوريد المقترح بالكرتونة (Suggested PO Cases)',
      'قيمة أمر التوريد المقترح (Suggested PO EGP)',
      'وزن أمر التوريد بالطن (Suggested PO Tons)',
    ],
    'sellInReconciliation': [
      'السنة (Year)',
      'الشهر (Month)',
      'حالة الفترة',
      'رصيد أول الشهر بالكرتونة (Opening Cases)',
      'رصيد أول الشهر بالجنيه (Opening EGP)',
      'التوريد الشهري بالكرتونة (Sell-In Cases)',
      'قيمة التوريد الشهري (Sell-In EGP)',
      'المبيعات الفعلية بالكرتونة التقديرية (Sell-Out Cases)',
      'قيمة المبيعات الفعلية (Sell-Out EGP)',
      'صافي حركة الشهر بالكرتونة (Monthly Net Cases)',
      'صافي حركة الشهر بالجنيه (Monthly Net EGP)',
      'الرصيد المتبقي آخر الشهر بالكرتونة (Closing Stock Cases)',
      'الرصيد المتبقي آخر الشهر بالجنيه (Closing Stock EGP)',
      'نسبة التصريف (Sell-Through %)',
      'تشخيص حالة الرصيد (Stock Health)',
    ],
    'sellInRecords': [
      'السنة',
      'الشهر',
      'السلسلة',
      'المحافظة / الإقليم',
      'العميل / الفرع',
      'القطاع',
      'العلامة التجارية',
      'الفئة الفرعية',
      'كود الصنف (Item Code)',
      'الباركود (Barcode)',
      'اسم الصنف',
      'مندوب المبيعات',
      'شد الكرتونة (Units/Carton)',
      'الكمية بالكرتونة (Cases)',
      'إجمالي الكمية بالقطعة (Units)',
      'سعر الكرتونة الرسمي (Official Carton Excl VAT)',
      'سعر الكرتونة الفعلي (Actual Case Price Excl VAT)',
      'نسبة الخصم الفعلي %',
      'صافي قيمة التوريد غير شامل الضريبة (Net EGP)',
      'ضريبة القيمة المضافة 14% (VAT EGP)',
      'إجمالي قيمة الفاتورة شامل الضريبة (Gross Incl VAT EGP)',
      'الوزن بالطن (Tons)',
      'حالة التسعير (Pricing Wave)',
      'الشيت المصدري (Source Sheet)',
    ],
    'sellOutRecords': [
      'الباركود الدولي',
      'اسم الصنف',
      'السلسلة',
      'الفرع',
      'الفئة',
      'الكمية المباعة',
      'سعر الوحدة',
      'صافي المبيعات (ج.م)',
      'تاريخ البيع',
    ],
  };
  final actual = <String, List<String>>{
    'cpfrReplenishment': ExportColumns.cpfrReplenishment,
    'sellInReconciliation': ExportColumns.sellInReconciliation,
    'sellInRecords': ExportColumns.sellInRecords,
    'sellOutRecords': ExportColumns.sellOutRecords,
  };

  for (final name in expected.keys) {
    test('$name export columns keep their exact order', () {
      expect(actual[name], orderedEquals(expected[name]!));
    });

    test('$name CSV header row follows the column order', () {
      final csv = ExcelExportService.generateCsv(headers: actual[name]!, rows: const []);
      final header = csv.substring(1).split('\n').first.trim();
      expect(header, expected[name]!.map((h) => '"$h"').join(','));
    });
  }
}
